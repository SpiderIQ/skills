# Verify the output — measure it, then report it

A SpiderVideo job that says `completed` has finished. It has not told you the video is right. This
file is how you find out, and what to say when you could not.

## The verifier

`scripts/verify-video.py` — python3 (stdlib only) + ffmpeg/ffprobe. It prints a PASS/FAIL table and
exits **0** (all passed), **1** (something failed) or **2** (it could not measure — never a pass).

| Mode | When | Input |
|---|---|---|
| `preflight <request.json>` | before a stitch | the payload you are about to send (API or `create_video` field names) |
| `render <file-or-url> --request <request.json>` | after a stitch | the mp4 — usually `data.upload.seaweedfs_url` |
| `frames <results.json>` | after an extract | the saved `GET /jobs/{id}/results` body |
| `--self-test` | once, on a new machine | nothing — builds its own bad fixtures and requires every check to fail |

## What each check measures

| Check | Mode | FAIL means |
|---|---|---|
| `scene-N-reachable` / `scene-N-video` | preflight | the URL does not open as a video — the job will fail at asset preparation |
| `scene-N-length` | preflight | the clip is shorter than its `durationInSeconds` — the render will carry a frozen tail |
| `music-audio` / `voice-audio` | preflight | the file has no audio stream — the job will fail |
| `voice-length` | preflight | the voice outlasts the video and will be cut |
| `duck` | preflight | `duckMusic` without both tracks (422); INFO when both tracks are sent without it |
| `captions` / `captions-length` | preflight | a token ends before it starts (422), or after the video ends (not drawn) |
| `codec` / `dimensions` / `duration` | render | the file is not what the request describes (duration uses the transition arithmetic in `stitch-scenes.md`) |
| `black` | render | a black run ≥ 0.5 s, with its scene |
| `frozen` | render | a frozen run ≥ 0.5 s, with its scene — usually a clip shorter than declared |
| `audio` | render | music/voice was requested but the track is missing or silent (mean below −60 dB) |
| `count` / `reachable` | frames | the pattern and the count disagree, or frames are missing |
| `still-*` / `width-*` | frames | a "frame" is an animated file, or the wrong width |
| `motion` | frames | the sampled frames are byte-identical — the animation will not move |

**WRONG** — reasoning from what the job returned:

```
Job 9f2c… completed. fileSize 6.9 MB, h264 1080x1920, 5.0 s. The video rendered successfully.
```

Every fact in that line was also true of the measured frozen-tail render.

**RIGHT** — report the table:

```
verify-video — render https://media.spideriq.ai/…/spring-promo-reel.mp4
  PASS  codec       h264 (the renderer writes h264)
  PASS  dimensions  1080x1920, expected 1080x1920 for 9:16
  PASS  duration    14.000 s, expected 14.000 s (+/-0.1)
  PASS  black       no black run >= 0.5 s
  FAIL  frozen      1 frozen run(s) >= 0.5 s: 2.95-3.47 s (scene 1) — the usual cause is a scene clip shorter than its durationInSeconds
  PASS  audio       mean volume -21.4 dB (silent below -60)
```

then either fix the scene and re-render, or carry the table into your summary.

## When a check FAILs

A FAIL is a decision, not an order. Three honest outcomes — say which one you took:

1. **Fix it** — shorten the scene, replace the clip, re-time the captions — and re-run.
2. **The absence is correct for this video** — a deliberate black intro, a deliberate freeze-frame.
   Say so, with the timestamp, in your report.
3. **You cannot fix it now** — include the table **verbatim** in a section titled *What I did NOT
   verify*. The verifier's own footer asks for exactly this.

Not an outcome: reporting success and letting the user find the frozen scene.

## What the verifier does NOT check — do these by hand or say you did not

### Measuring ducking

You cannot measure "the music's level under the voice" on a real song — the voice sits in the same
frequencies. To prove the duck works on your account, render once with a test music track that the
voice cannot produce:

1. Music: an 11 kHz sine (`ffmpeg -f lavfi -i "sine=f=11000" -t 15 tone.wav`). Not 15 kHz — the AAC
   encoder's low-pass removes it.
2. Voice: your narration (speech has little above 8 kHz).
3. Render twice, `duckMusic: true` and `false`, everything else identical.
4. Isolate the tone and read its level during a spoken word and during a pause:
   `ffmpeg -i out.mp4 -ss 1.0 -t 1.0 -af "highpass=9500,highpass=9500,highpass=9500,highpass=9500,volumedetect" -f null -`

Expected: about 12 dB lower under speech than in the pause with ducking on; flat with it off. A
measured run: −56.2 dB under speech vs −44.0 dB in the pause (12.2 dB), control flat at −44.0 dB.

### Checking captions

Pull a frame at the middle of a word and at the middle of a pause, and look:

```bash
ffmpeg -ss 1.35 -i out.mp4 -frames:v 1 word.png     # expect that word highlighted yellow
ffmpeg -ss 3.20 -i out.mp4 -frames:v 1 pause.png    # expect no caption at all
```

Pick the timestamps from your own `captions` list. This proves the captions follow your timings; it
cannot prove your timings match the voice.

### Whether it is the video the user wanted

The verifier finds defects. It does not know the brief. Watch it, or say you did not.

## Gotchas

- `render` needs the file. Without `upload.enabled` there is no URL to give it (see `stitch-scenes.md`).
- Exit **2** means nothing was verified: a missing ffmpeg, a URL that would not open, a results file
  with no manifest. Never report a 2 as a pass.
- `--min-run` (default 0.5 s) sets the shortest black/frozen run that fails. Lower it for short
  cuts; do not raise it to make a FAIL go away.
- Run `--self-test` once per machine. If it is not 16/16, the checks cannot be trusted there.
