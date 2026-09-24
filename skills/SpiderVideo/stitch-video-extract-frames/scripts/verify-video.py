#!/usr/bin/env python3
"""verify-video.py — measure a SpiderVideo output instead of trusting that the job finished.

    python3 verify-video.py preflight <request.json>                      # BEFORE you submit a stitch
    python3 verify-video.py render    <file-or-url.mp4> [--request request.json]
    python3 verify-video.py frames    <results.json>                        # an extract_frames manifest
    python3 verify-video.py --self-test                                     # prove every check can FAIL

Needs python3 (stdlib only) plus ffmpeg + ffprobe on PATH.

WHY THIS EXISTS. On this renderer a scene clip SHORTER than its `durationInSeconds` renders
without error: exit 0, h264, the requested dimensions, the requested duration, the requested
frame count — and the missing seconds are a FROZEN copy of the clip's last frame. Measured on
the live worker image v1.6.0 (2026-09-23): a 2 s clip declared as 5 s produced 150 frames at
5.000 s, byte-for-byte the same metadata as a correct render, with frames 61-150 (60% of the
video) frozen. Zero of those frames were black, so a black-frame check passes it too. Only a
frame-to-frame difference caught it. A job that says `completed` has told you it finished, not
that the video is right.

EXIT CODES
    0  every check that ran PASSED
    1  at least one check FAILED
    2  CANNOT MEASURE — a tool is missing or the input could not be read. This is never a pass.
"""
import argparse
import hashlib
import http.server
import json
import os
import re
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.request

FPS = 30                      # the VideoStitcher compositions render at 30 fps (Root.tsx)
DEFAULT_TRANSITION = 15       # transitionDurationInFrames default (SpiderVideoJobPayload)
DIMENSIONS = {"9:16": (1080, 1920), "16:9": (1920, 1080)}
UA = {"User-Agent": "spideriq-verify-video/1.0"}   # spideriq.ai + the bundle CDN 403 python-urllib's default UA

FOOTER = (
    "Fix the FAIL items, OR include this report verbatim in your final summary's "
    "\"What I did NOT verify\" section so the user knows what is broken."
)
NOT_VERIFIED_RENDER = [
    "ducking depth — needs a band-separated measurement (references/verify-the-output.md#ducking)",
    "caption timing and wording — the renderer draws what you timed; nothing here reads the pixels",
    "whether the scenes are the RIGHT scenes — this measures defects, not intent",
]


class CannotMeasure(Exception):
    pass


# ----------------------------------------------------------------------------- report
class Report:
    def __init__(self, title):
        self.title = title
        self.rows = []

    def add(self, verdict, check, detail):
        self.rows.append((verdict, check, detail))

    def failed(self):
        return any(v == "FAIL" for v, _, _ in self.rows)

    def verdict_of(self, check):
        for v, c, _ in self.rows:
            if c == check:
                return v
        return None

    def render(self, not_verified):
        out = ["verify-video — %s" % self.title, ""]
        w = max([len(c) for _, c, _ in self.rows] + [5])
        for v, c, d in self.rows:
            out.append("  %-4s  %-*s  %s" % (v, w, c, d))
        out.append("")
        if not_verified:
            out.append("  NOT VERIFIED by this script:")
            for n in not_verified:
                out.append("    - %s" % n)
            out.append("")
        n_fail = sum(1 for v, _, _ in self.rows if v == "FAIL")
        n_pass = sum(1 for v, _, _ in self.rows if v == "PASS")
        if n_fail:
            out.append("  RESULT: FAIL — %d failed, %d passed." % (n_fail, n_pass))
            out.append("  " + FOOTER)
        else:
            out.append("  RESULT: PASS — %d passed, 0 failed." % n_pass)
        return "\n".join(out)


# ----------------------------------------------------------------------------- tools
def require_tools():
    missing = [t for t in ("ffmpeg", "ffprobe") if shutil.which(t) is None]
    if missing:
        raise CannotMeasure("missing on PATH: %s (install ffmpeg)" % ", ".join(missing))


def run(cmd, timeout=600):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def probe(src):
    """ffprobe a local path or http(s) URL. Returns the parsed JSON or raises CannotMeasure."""
    p = run(["ffprobe", "-v", "error", "-print_format", "json", "-show_format", "-show_streams", src], timeout=120)
    if p.returncode != 0:
        raise CannotMeasure("ffprobe could not open %s: %s" % (src, (p.stderr.strip() or "no output")[:300]))
    try:
        return json.loads(p.stdout)
    except ValueError:
        raise CannotMeasure("ffprobe returned non-JSON for %s" % src)


def stream(info, kind):
    for s in info.get("streams", []):
        if s.get("codec_type") == kind:
            return s
    return None


def duration_of(info):
    try:
        return float(info.get("format", {}).get("duration"))
    except (TypeError, ValueError):
        return None


def ffmpeg_log(src, filters, audio=False):
    """Run an analysis filter and return ffmpeg's stderr at info level."""
    cmd = ["ffmpeg", "-hide_banner", "-nostats", "-v", "info", "-i", src]
    cmd += (["-af", filters, "-vn"] if audio else ["-vf", filters, "-an"])
    cmd += ["-f", "null", "-"]
    p = run(cmd, timeout=1800)
    if p.returncode != 0:
        raise CannotMeasure("ffmpeg analysis failed on %s: %s" % (src, p.stderr.strip()[-300:]))
    return p.stderr


def black_runs(src, min_seconds):
    log = ffmpeg_log(src, "blackdetect=d=%s:pix_th=0.10" % min_seconds)
    runs = []
    for m in re.finditer(r"black_start:([\d.]+)\s+black_end:([\d.]+)\s+black_duration:([\d.]+)", log):
        runs.append((float(m.group(1)), float(m.group(2))))
    return runs


def frozen_runs(src, min_seconds, total):
    log = ffmpeg_log(src, "freezedetect=n=0.001:d=%s" % min_seconds)
    starts = [float(x) for x in re.findall(r"freeze_start:\s*([\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"freeze_end:\s*([\d.]+)", log)]
    runs = []
    for i, s in enumerate(starts):
        e = ends[i] if i < len(ends) else total    # a freeze that lasts to EOF has no freeze_end
        runs.append((s, e if e is not None else s))
    return runs


def mean_volume(src):
    log = ffmpeg_log(src, "volumedetect", audio=True)
    m = re.search(r"mean_volume:\s*(-?[\d.]+|-inf) dB", log)
    if not m:
        raise CannotMeasure("volumedetect printed no mean_volume for %s" % src)
    return float("-inf") if m.group(1) == "-inf" else float(m.group(1))


# ----------------------------------------------------------------------------- request math
def load_request(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise CannotMeasure("cannot read request %s: %s" % (path, e))
    return data.get("payload", data) if isinstance(data, dict) else {}


def get(req, camel, snake, default=None):
    """Accept both the API field names (camelCase) and the create_video tool's snake_case."""
    if camel in req:
        return req[camel]
    if snake in req:
        return req[snake]
    return default


def scene_windows(req):
    """[(index, start_s, end_s)] on the output timeline — the same arithmetic as calculateDuration()."""
    scenes = req.get("scenes") or []
    t = int(get(req, "transitionDurationInFrames", "transition_frames", DEFAULT_TRANSITION) or 0)
    windows, cursor = [], 0
    for i, s in enumerate(scenes):
        frames = int(round(float(s.get("durationInSeconds", 0)) * FPS))
        windows.append((i + 1, cursor / FPS, (cursor + frames) / FPS))
        cursor += frames - (t if i < len(scenes) - 1 else 0)
    return windows, cursor / FPS


def scene_at(windows, t):
    hits = [str(i) for i, a, b in windows if a <= t < b]
    return "scene " + "/".join(hits) if hits else "outside every scene"


# ----------------------------------------------------------------------------- preflight
def cmd_preflight(args):
    require_tools()
    req = load_request(args.request)
    rep = Report("preflight %s" % args.request)
    scenes = req.get("scenes") or []
    if not scenes:
        rep.add("FAIL", "scenes", "no scenes in the request")
    music = get(req, "musicUrl", "music_url")
    voice = get(req, "voiceUrl", "voice_url")
    duck = get(req, "duckMusic", "duck_music", False) is True

    for i, s in enumerate(scenes, 1):
        url, declared = s.get("videoUrl"), float(s.get("durationInSeconds", 0))
        try:
            info = probe(url)
        except CannotMeasure as e:
            rep.add("FAIL", "scene-%d-reachable" % i, "cannot open: %s" % str(e)[:160])
            continue
        v = stream(info, "video")
        if v is None:
            rep.add("FAIL", "scene-%d-video" % i, "no video stream (an HTML error page or an audio file?)")
            continue
        real = duration_of(info)
        rep.add("PASS", "scene-%d-reachable" % i, "%s %sx%s, %.3f s" % (v.get("codec_name"), v.get("width"), v.get("height"), real or 0))
        if real is None:
            rep.add("FAIL", "scene-%d-length" % i, "duration unreadable — cannot predict a frozen tail")
        elif declared > real + 1.0 / FPS:
            rep.add("FAIL", "scene-%d-length" % i,
                    "declared %.3f s but the clip is %.3f s — the last %.3f s will render as a FROZEN still, with no error"
                    % (declared, real, declared - real))
        else:
            rep.add("PASS", "scene-%d-length" % i, "declared %.3f s <= clip %.3f s" % (declared, real))

    for name, url in (("music", music), ("voice", voice)):
        if not url:
            continue
        try:
            info = probe(url)
        except CannotMeasure as e:
            # A voice that cannot be downloaded FAILS the job. A music track that cannot be
            # downloaded also fails it (asset preparation) — say so before the render is spent.
            rep.add("FAIL", "%s-reachable" % name, "cannot open: %s" % str(e)[:160])
            continue
        if stream(info, "audio") is None:
            rep.add("FAIL", "%s-audio" % name, "reachable but carries no audio stream — the job will fail")
        else:
            rep.add("PASS", "%s-audio" % name, "audio stream present, %.3f s" % (duration_of(info) or 0))
            if name == "voice":
                _, total = scene_windows(req)
                dv = duration_of(info)
                if dv and total and dv > total + 0.05:
                    rep.add("FAIL", "voice-length",
                            "voice is %.2f s but the video is %.2f s — the last %.2f s of the voice is cut (only a warnings[] entry says so)"
                            % (dv, total, dv - total))

    if duck and not (music and voice):
        rep.add("FAIL", "duck", "duckMusic needs BOTH a music URL and a voice URL — the API answers 422")
    elif music and voice and not duck:
        rep.add("INFO", "duck", "music + voice without duckMusic: the music stays at a FLAT level under the voice")

    caps = req.get("captions") or []
    if caps:
        _, total = scene_windows(req)
        bad = [c for c in caps if float(c.get("endMs", 0)) < float(c.get("startMs", 0))]
        late = [c for c in caps if float(c.get("endMs", 0)) > total * 1000 + 50]
        if bad:
            rep.add("FAIL", "captions", "%d token(s) end before they start — the API answers 422" % len(bad))
        if late:
            rep.add("FAIL", "captions-length", "%d token(s) end after the video (%.2f s) — not shown" % (len(late), total))
        if not bad and not late:
            rep.add("PASS", "captions", "%d tokens, all inside the %.2f s video (timing is NOT checked — see NOT VERIFIED)" % (len(caps), total))

    print(rep.render(["caption timing against the voice — the renderer draws what you send, nothing aligns it"]))
    return 1 if rep.failed() else 0


# ----------------------------------------------------------------------------- render
def cmd_render(args):
    require_tools()
    req = load_request(args.request) if args.request else {}
    rep = Report("render %s" % args.src)
    info = probe(args.src)                               # liveness: an unreadable file is CANNOT, never FAIL
    v = stream(info, "video")
    if v is None:
        raise CannotMeasure("%s has no video stream" % args.src)
    total = duration_of(info) or 0.0

    codec = v.get("codec_name")
    rep.add("PASS" if codec == "h264" else "FAIL", "codec", "%s (the renderer writes h264)" % codec)

    aspect = args.expect_aspect or (get(req, "aspectRatio", "aspect_ratio", "9:16") if req else None)
    dims = (v.get("width"), v.get("height"))
    if aspect in DIMENSIONS:
        want = DIMENSIONS[aspect]
        rep.add("PASS" if tuple(dims) == want else "FAIL", "dimensions", "%sx%s, expected %sx%s for %s" % (dims + want + (aspect,)))
    else:
        rep.add("INFO", "dimensions", "%sx%s (pass --request or --expect-aspect to check)" % dims)

    windows, expected = scene_windows(req) if req.get("scenes") else ([], args.expect_seconds)
    if expected:
        ok = abs(total - expected) <= 0.1
        rep.add("PASS" if ok else "FAIL", "duration", "%.3f s, expected %.3f s (+/-0.1)" % (total, expected))
    else:
        rep.add("INFO", "duration", "%.3f s (pass --request or --expect-seconds to check)" % total)

    blacks = black_runs(args.src, args.min_run)
    if blacks:
        where = "; ".join("%.2f-%.2f s (%s)" % (a, b, scene_at(windows, a)) for a, b in blacks)
        rep.add("FAIL", "black", "%d black run(s) >= %.1f s: %s" % (len(blacks), args.min_run, where))
    else:
        rep.add("PASS", "black", "no black run >= %.1f s" % args.min_run)

    frozen = frozen_runs(args.src, args.min_run, total)
    if frozen:
        where = "; ".join("%.2f-%.2f s (%s)" % (a, b, scene_at(windows, a)) for a, b in frozen)
        rep.add("FAIL", "frozen",
                "%d frozen run(s) >= %.1f s: %s — the usual cause is a scene clip shorter than its durationInSeconds"
                % (len(frozen), args.min_run, where))
    else:
        rep.add("PASS", "frozen", "no frozen run >= %.1f s" % args.min_run)

    wants_audio = args.expect_audio or bool(get(req, "musicUrl", "music_url") or get(req, "voiceUrl", "voice_url"))
    a = stream(info, "audio")
    if wants_audio:
        if a is None:
            rep.add("FAIL", "audio", "the request carries music/voice but the file has NO audio stream")
        else:
            mv = mean_volume(args.src)
            rep.add("PASS" if mv > -60 else "FAIL", "audio", "mean volume %.1f dB (silent below -60)" % mv)
    else:
        rep.add("INFO", "audio", "no music/voice requested — not checked")

    print(rep.render(NOT_VERIFIED_RENDER))
    return 1 if rep.failed() else 0


# ----------------------------------------------------------------------------- frames
def find_manifest(obj):
    """Walk a results envelope until a dict carries base_url + pattern + count."""
    if isinstance(obj, dict):
        if all(k in obj for k in ("base_url", "pattern", "count")):
            return obj
        for val in obj.values():
            m = find_manifest(val)
            if m:
                return m
    if isinstance(obj, list):
        for val in obj:
            m = find_manifest(val)
            if m:
                return m
    return None


def expand_pattern(pattern):
    m = re.match(r"^(.*)\{(\d+)\.\.(\d+)\}(.*)$", pattern)
    if not m:
        raise CannotMeasure("pattern %r is not the frame_{0001..NNNN}.ext shape" % pattern)
    pre, a, b, post = m.groups()
    width = len(a)
    return [pre + str(n).zfill(width) + post for n in range(int(a), int(b) + 1)]


def webp_is_animated(body):
    """Read the RIFF container, not ffprobe: animated-WebP decoding depends on the ffmpeg build,
    and this is the one property the check exists for (ffmpeg's default WebP encoder once wrote
    a whole sequence into ONE animated file)."""
    if body[:4] != b"RIFF" or body[8:12] != b"WEBP":
        return False
    if body[12:16] == b"VP8X" and len(body) > 20 and body[20] & 0x02:
        return True
    return b"ANMF" in body or b"ANIM" in body[12:64]


def fetch(url, head=False):
    req = urllib.request.Request(url, headers=UA, method="HEAD" if head else "GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, (b"" if head else r.read())
    except urllib.error.HTTPError as e:
        return e.code, b""
    except (urllib.error.URLError, OSError) as e:
        return None, str(e).encode()


def cmd_frames(args):
    require_tools()
    try:
        with open(args.results) as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        raise CannotMeasure("cannot read %s: %s" % (args.results, e))
    man = find_manifest(doc)
    if not man:
        raise CannotMeasure("no {base_url, pattern, count} manifest in %s — is this an extract_frames result?" % args.results)
    names = expand_pattern(man["pattern"])
    base = man["base_url"].rstrip("/")
    rep = Report("frames %s" % base)
    count = int(man["count"])
    rep.add("PASS" if len(names) == count else "FAIL", "count", "pattern expands to %d, manifest says %d" % (len(names), count))

    statuses = {}
    for n in names:
        st, _ = fetch("%s/%s" % (base, n), head=True)
        if st == 405:                                   # a store that refuses HEAD: fall back to GET
            st, _ = fetch("%s/%s" % (base, n))
        statuses[n] = st
    missing = [n for n, st in statuses.items() if st != 200]
    if statuses and len(missing) == len(statuses):
        raise CannotMeasure("0 of %d frames answered 200 (first: %s -> %s) — check the base_url and your network"
                            % (len(names), names[0], statuses[names[0]]))
    rep.add("FAIL" if missing else "PASS", "reachable",
            "%d/%d frames answer 200%s" % (len(names) - len(missing), len(names), ("; missing: " + ", ".join(missing[:5])) if missing else ""))

    tmp = tempfile.mkdtemp(prefix="sv-frames-")
    try:
        picks = sorted(set([names[0], names[len(names) // 2], names[-1]]))
        digests = []
        for n in picks:
            st, body = fetch("%s/%s" % (base, n))
            if st != 200 or not body:
                continue
            p = os.path.join(tmp, n)
            with open(p, "wb") as f:
                f.write(body)
            digests.append(hashlib.sha256(body).hexdigest())
            if webp_is_animated(body):
                rep.add("FAIL", "still-%s" % n, "an ANIMATED WebP — a whole sequence in one file, not one frame of it")
                continue
            rep.add("PASS", "still-%s" % n, "a single still image (%d bytes)" % len(body))
            v = stream(probe(p), "video") or {}
            want_w = man.get("width")
            if want_w:
                rep.add("PASS" if v.get("width") == int(want_w) else "FAIL", "width-%s" % n, "%s px, manifest says %s" % (v.get("width"), want_w))
        if len(digests) >= 2:
            same = len(set(digests)) == 1
            rep.add("FAIL" if same else "PASS", "motion",
                    "first/middle/last frames are byte-IDENTICAL — the scroll sequence will not move" if same
                    else "%d sampled frames, %d distinct" % (len(digests), len(set(digests))))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(rep.render(["whether the frames show the moment you wanted — this checks the files, not the story"]))
    return 1 if rep.failed() else 0


# ----------------------------------------------------------------------------- self-test
def _ff(*a):
    p = run(["ffmpeg", "-hide_banner", "-v", "error", "-y"] + list(a))
    if p.returncode != 0:
        raise CannotMeasure("fixture build failed: %s" % p.stderr.strip()[-300:])


def _serve(root):
    handler_cls = type("Quiet", (http.server.SimpleHTTPRequestHandler,), {"log_message": lambda *a: None})
    srv = socketserver.TCPServer(("127.0.0.1", 0), lambda *a, **k: handler_cls(*a, directory=root, **k))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, "http://127.0.0.1:%d" % srv.server_address[1]


def self_test():
    require_tools()
    d = tempfile.mkdtemp(prefix="sv-selftest-")
    me = os.path.abspath(__file__)
    results = []

    def case(name, argv, want_rc, want=None):
        """want: {check: verdict} — asserted by CHECK NAME, never by exit code alone."""
        p = run([sys.executable, me] + argv, timeout=600)
        ok = p.returncode == want_rc
        for check, verdict in (want or {}).items():
            line = re.search(r"^\s+(PASS|FAIL|INFO)\s+%s\s" % re.escape(check), p.stdout, re.M)
            ok = ok and bool(line) and line.group(1) == verdict
        results.append((ok, name, p.returncode, want_rc))
        if not ok:
            sys.stdout.write("---- %s (rc %s, wanted %s)\n%s%s\n" % (name, p.returncode, want_rc, p.stdout, p.stderr))

    try:
        W, H = 540, 960                                 # half-size 9:16 keeps the suite fast
        src = "testsrc2=size=%dx%d:rate=30" % (W, H)
        _ff("-f", "lavfi", "-i", src, "-f", "lavfi", "-i", "sine=f=440", "-t", "5",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", os.path.join(d, "good.mp4"))
        # frozen tail: 2 s of motion, then the last frame held to 5 s — the measured defect's shape.
        # The 2 s limit lives on the SOURCE: an output `-t 2` would cut the padded tail back off,
        # and the fixture would silently stop containing the defect it exists to carry.
        src2 = src + ":duration=2"
        _ff("-f", "lavfi", "-i", src2, "-vf", "tpad=stop_mode=clone:stop_duration=3",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", os.path.join(d, "frozen.mp4"))
        _ff("-f", "lavfi", "-i", src2, "-vf", "tpad=stop_mode=add:stop_duration=3:color=black",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", os.path.join(d, "black.mp4"))
        _ff("-f", "lavfi", "-i", src, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", "5",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", os.path.join(d, "silent.mp4"))
        _ff("-f", "lavfi", "-i", src, "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", os.path.join(d, "clip2.mp4"))
        _ff("-f", "lavfi", "-i", "sine=f=220", "-t", "3", os.path.join(d, "voice.wav"))

        def request(name, **kw):
            p = os.path.join(d, name)
            with open(p, "w") as f:
                json.dump(kw, f)
            return p

        one = [{"videoUrl": "x", "durationInSeconds": 5}]
        r_plain = request("plain.json", scenes=one, transitionDurationInFrames=0)
        r_music = request("music.json", scenes=one, transitionDurationInFrames=0, musicUrl="x")
        g = os.path.join(d, "good.mp4")
        dims = ["--expect-aspect", "16:9"]              # half-size fixtures: check dimensions only where it is the subject

        # render — the positive control first: a check that never PASSES proves nothing either
        case("render: good file passes", ["render", g, "--request", r_music, "--expect-aspect", "none"], 0,
             {"black": "PASS", "frozen": "PASS", "audio": "PASS", "duration": "PASS"})
        case("render: frozen tail FAILS frozen (and passes black)", ["render", os.path.join(d, "frozen.mp4"), "--request", r_plain, "--expect-aspect", "none"], 1,
             {"frozen": "FAIL", "black": "PASS", "duration": "PASS"})
        case("render: black tail FAILS black", ["render", os.path.join(d, "black.mp4"), "--request", r_plain, "--expect-aspect", "none"], 1,
             {"black": "FAIL"})
        case("render: silent audio FAILS audio", ["render", os.path.join(d, "silent.mp4"), "--request", r_music, "--expect-aspect", "none"], 1,
             {"audio": "FAIL"})
        case("render: wrong duration FAILS duration", ["render", g, "--expect-seconds", "8"], 1, {"duration": "FAIL"})
        case("render: wrong dimensions FAIL dimensions", ["render", g] + dims, 1, {"dimensions": "FAIL"})
        case("render: unreadable input is CANNOT (2), never FAIL", ["render", os.path.join(d, "nope.mp4")], 2)

        srv, base = _serve(d)
        try:
            ok_req = request("pre_ok.json", scenes=[{"videoUrl": base + "/good.mp4", "durationInSeconds": 5}])
            short_req = request("pre_short.json", scenes=[{"videoUrl": base + "/clip2.mp4", "durationInSeconds": 5}])
            gone_req = request("pre_404.json", scenes=[{"videoUrl": base + "/does-not-exist.mp4", "durationInSeconds": 5}])
            duck_req = request("pre_duck.json", scenes=[{"videoUrl": base + "/good.mp4", "durationInSeconds": 5}],
                               musicUrl=base + "/voice.wav", duckMusic=True)
            long_voice = request("pre_voice.json", scenes=[{"videoUrl": base + "/clip2.mp4", "durationInSeconds": 2}],
                                 voiceUrl=base + "/voice.wav")
            case("preflight: good request passes", ["preflight", ok_req], 0, {"scene-1-length": "PASS"})
            case("preflight: short clip FAILS scene-1-length", ["preflight", short_req], 1, {"scene-1-length": "FAIL"})
            case("preflight: 404 scene FAILS scene-1-reachable", ["preflight", gone_req], 1, {"scene-1-reachable": "FAIL"})
            case("preflight: duck without voice FAILS duck", ["preflight", duck_req], 1, {"duck": "FAIL"})
            case("preflight: voice longer than video FAILS voice-length", ["preflight", long_voice], 1, {"voice-length": "FAIL"})

            fr = os.path.join(d, "fr")
            os.makedirs(fr)
            _ff("-f", "lavfi", "-i", "testsrc2=size=320x180:rate=4", "-t", "1", "-c:v", "libwebp", os.path.join(fr, "frame_%04d.webp"))
            man = {"action": "extract_frames", "base_url": base + "/fr", "pattern": "frame_{0001..0004}.webp", "count": 4, "width": 320}
            good_frames = request("frames_ok.json", data=man)
            case("frames: good manifest passes", ["frames", good_frames], 0, {"reachable": "PASS", "motion": "PASS"})
            gap = dict(man, pattern="frame_{0001..0006}.webp", count=6)
            case("frames: a missing frame FAILS reachable", ["frames", request("frames_gap.json", **gap)], 1, {"reachable": "FAIL"})
            same = os.path.join(d, "same")
            os.makedirs(same)
            for n in range(1, 4):
                shutil.copy(os.path.join(fr, "frame_0001.webp"), os.path.join(same, "frame_%04d.webp" % n))
            case("frames: identical frames FAIL motion",
                 ["frames", request("frames_same.json", **dict(man, base_url=base + "/same", pattern="frame_{0001..0003}.webp", count=3))],
                 1, {"motion": "FAIL"})
            anim = os.path.join(d, "anim")
            os.makedirs(anim)
            # the ffmpeg trap this pipeline once shipped: libwebp_anim writes ONE animated file
            _ff("-f", "lavfi", "-i", "testsrc2=size=320x180:rate=4", "-t", "1", "-c:v", "libwebp_anim", "-loop", "0",
                os.path.join(anim, "frame_0001.webp"))
            shutil.copy(os.path.join(fr, "frame_0002.webp"), os.path.join(anim, "frame_0002.webp"))
            case("frames: an animated file FAILS still-*",
                 ["frames", request("frames_anim.json", **dict(man, base_url=base + "/anim", pattern="frame_{0001..0002}.webp", count=2))],
                 1, {"still-frame_0001.webp": "FAIL"})
        finally:
            srv.shutdown()
    finally:
        shutil.rmtree(d, ignore_errors=True)

    for ok, name, rc, want in results:
        print("  %s  %s (rc %s)" % ("PASS" if ok else "FAIL", name, rc))
    bad = [r for r in results if not r[0]]
    print("\nself-test: %d/%d cases passed" % (len(results) - len(bad), len(results)))
    return 1 if bad else 0


# ----------------------------------------------------------------------------- main
def main():
    if "--self-test" in sys.argv[1:]:
        try:
            return self_test()
        except CannotMeasure as e:
            print("verify-video: CANNOT MEASURE — %s" % e)
            return 2
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="mode", required=True)
    p = sub.add_parser("preflight", help="check a stitch request BEFORE submitting it")
    p.add_argument("request")
    r = sub.add_parser("render", help="measure a rendered mp4 (path or URL)")
    r.add_argument("src")
    r.add_argument("--request", help="the payload you submitted (JSON) — enables duration/dimension/scene checks")
    r.add_argument("--expect-seconds", type=float)
    r.add_argument("--expect-aspect", help="9:16 or 16:9 ('none' skips the dimension check)")
    r.add_argument("--expect-audio", action="store_true")
    r.add_argument("--min-run", type=float, default=0.5, help="shortest black/frozen run that fails, seconds (default 0.5)")
    f = sub.add_parser("frames", help="check an extract_frames result manifest")
    f.add_argument("results")
    args = ap.parse_args()
    try:
        return {"preflight": cmd_preflight, "render": cmd_render, "frames": cmd_frames}[args.mode](args)
    except CannotMeasure as e:
        print("verify-video: CANNOT MEASURE — %s" % e)
        print("  This is not a pass. Nothing about the output was verified.")
        return 2


if __name__ == "__main__":
    sys.exit(main())
