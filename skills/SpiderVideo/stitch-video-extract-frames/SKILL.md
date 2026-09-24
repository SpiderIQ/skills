---
name: stitch-video-extract-frames
description: >
  SpiderVideo — two jobs behind one service. STITCH: join video clips (scenes) into one
  mp4 with fade transitions, portrait 9:16 or landscape 16:9, background music, a
  voiceover track, music that ducks under the voice, and burned word-by-word captions;
  optionally upload it to SpiderMedia. FRAMES: pull a numbered WebP/JPEG image sequence
  out of a video for a scroll-linked hero (the sys-scroll-sequence component). Use for
  "stitch these clips", "make a video from scenes", "join AI video clips", "add music /
  a voiceover / narration / subtitles / captions to a video", "duck the music", "render
  a 9:16 reel", "turn this video into a scroll animation", "extract frames", "image
  sequence from video", or "create_video". Measures every output before reporting it —
  a render that completes can still be wrong. Generating the clips or the voice is
  generate-media; publishing a page is spiderpublish; hosting and browsing files is
  spideriq-media-catalog.
version: "0.1.0"
category: media
---

# stitch-video-extract-frames

SpiderVideo turns clips you already have into a finished video, or a video you already have into
frames for a scroll animation. It generates nothing: every scene, music track and voice is a URL
you supply.

```
  PATH A — STITCH  (create_video · POST /jobs/spiderVideo/submit)
    scene URLs + music/voice URLs + caption timings ──► one mp4 (h264, 30 fps)
                                                         └─ upload:true ──► data.upload.seaweedfs_url

  PATH B — FRAMES  (video_to_scroll_sequence · POST /jobs/spiderVideo/extract-frames/submit)
    one video URL ──► frame_0001.webp … frame_NNNN.webp ──► {base_url, pattern, count}
                                                         └─ the three props sys-scroll-sequence reads
```

The two paths share an endpoint family and almost nothing else — different payload, different
engine, different result, different agent tool. **Path B is the one with regular production
traffic; Path A has had very little**, so treat a first Path A job as something to measure, not to
trust. Pick the path first; every mistake below is cheaper there than after a render.

## Approach

1. **Pick the path** — a finished video from clips is A; frames for a page hero is B.
2. **Preflight** (Path A) — `python3 scripts/verify-video.py preflight request.json` opens every
   scene, music and voice URL before you spend a render. It catches the one defect the job itself
   never reports (step 5).
3. **Submit** — the tool or route in the table below. Both return `job_id` + `status: queued`,
   never a video.
4. **Poll** — `get_job_status` every 5–10 s, then `get_job_results`. `queued` for minutes is
   normal: a render runs on its first attempt without ever reading `processing`.
5. **Measure** — run the verifier on what came back (`render` for A, `frames` for B).
6. **Report** — the verifier's table, verbatim if anything FAILED.

<HARD-GATE>
Never report a SpiderVideo output as correct because the job completed. On this renderer a scene
clip shorter than its `durationInSeconds` finishes with status `completed`, exit 0, h264, the
requested dimensions, the requested duration and the requested frame count — and the missing
seconds are a FROZEN copy of the clip's last frame. Measured on the live worker image: a 2 s clip
declared as 5 s rendered 150 frames at 5.000 s, metadata identical to a correct render, with
frames 61–150 (60% of the video) frozen and ZERO of them black, so a black-frame check passes it
too. If you are about to write "the video rendered successfully" from a `completed` status, a
file size or an ffprobe line, you skipped the measurement. Run
`python3 scripts/verify-video.py render <url> --request request.json` and paste its table.
</HARD-GATE>

## Rules (Non-Negotiable)

**Measure pixels, loudness or a hash — never the absence of an error.** Pixels for anything
visual (frozen/black runs), loudness for anything audible (a silent track still has an audio
stream), a hash for anything that must or must not change. Why: every failure listed under
*What completes and is still wrong* returns `completed`.

**Set `upload` when you need the file.** Without it the mp4 stays inside the render worker and the
result's `outputFile` is a path on that machine — nothing you or a user can download, and nothing
the verifier can open. With it, the file is at `data.upload.seaweedfs_url`. Why: it is the only
way the video leaves the renderer. (The account needs SpiderMedia storage, or the job fails.)

**Diagnose a failure from the INPUT, never from `error_message`.** For this service a failed job's
`error_message` is one fixed sentence asking you to quote the `job_id` to support — the real reason
is withheld from client responses. Why: parsing it tells you nothing, and retrying an input failure
fails identically. `preflight` is how you find the broken URL yourself.

**Captions are drawn exactly as you timed them.** Nothing listens to the audio — there is no
speech recognition and no alignment. Wrong timings render as wrong captions, with no error.
Why: "captions appear" is not "captions are correct"; timings from a transcription tool are what
was *heard*, not what the script says. See `references/audio-lane.md`.

**`duckMusic` is OFF unless you set it, and needs BOTH tracks.** Music + voice without it plays
the music at one flat level under the speech. With it but without both URLs, the API answers 422.
Why: an omitted flag produces a valid, plausible mix with no warning.

**`create_video` sends a FIXED field list.** It forwards `project_name`, `scenes`, `aspect_ratio`,
`music_url`, `music_volume`, `voice_url`, `voice_volume`, `duck_music` (only when `true`),
`captions`, `transition_frames`, `upload`, `preprocess` (only when `true`) and `test` — and drops
anything else without an error. A field the API gained after your MCP package was built is
unreachable through the tool; send it over HTTP instead. Why: a dropped field is a silent 201.

**Only http(s) URLs are fetched.** The API accepts any string for `videoUrl` and `musicUrl` and
answers 201; a `file://`, `ftp://` or bare path then fails the job at download. `voiceUrl` is
checked up front (422). Why: a 201 is not an accepted asset.

**An identical request within 24 hours returns the EARLIER job.** The submit carries
`from_cache: true`. Why: replacing the file behind the same URL and resubmitting gets you the old
render. Change `projectName` (e.g. append `-v2`) to force a new one.

## Decision tree — pick a reference

| You want to… | Read |
|---|---|
| Stitch scenes into one video (payload, durations, transitions, what comes back) | `references/stitch-scenes.md` |
| Add a voiceover, duck the music, burn captions | `references/audio-lane.md` — **always read** before sending `voiceUrl` or `captions` |
| Turn a video into scroll-animation frames | `references/extract-frames.md` |
| Check an output before telling anyone it worked | `references/verify-the-output.md` — **always read** |
| Understand a failed or odd-looking job | `references/read-results-and-failures.md` |

## The surfaces

| Path | MCP tool | HTTP (`https://spideriq.ai/api/v1`, Bearer `client_id:api_key:api_secret`) | CLI |
|---|---|---|---|
| A — stitch | `create_video` (`@spideriq/mcp-leads`, `@spideriq/mcp`) | `POST /jobs/spiderVideo/submit` | `spideriq jobs submit -t spiderVideo -p '<payload>'` |
| B — frames into a page | `video_to_scroll_sequence` (`@spideriq/mcp-publish`, `@spideriq/mcp`) | `POST /dashboard/scroll-sequence/from-video` | `spideriq video to-scroll-sequence` |
| B — frames only | — (no MCP tool submits a bare extract) | `POST /jobs/spiderVideo/extract-frames/submit` | — |
| Poll | `get_job_status` · `get_job_results` | `GET /jobs/{job_id}/status` · `GET /jobs/{job_id}/results` | `spideriq jobs status\|results <id>` |

⚠️ **`submit_job` with type `spiderVideo` always reaches the STITCH route**, whatever the payload
says. An `action: "extract_frames"` payload sent that way is validated as a stitch and answers 422
(`projectName` / `scenes` required). Frames go through the frames route or
`video_to_scroll_sequence`.

Every HTTP submit wraps the fields in `payload`: `{"payload": {...}}`. A flat body is a 422.

## What you get back

`GET /jobs/{job_id}/results` → `{success, job_id, type, status, completed_at, data, error_message}`.

| | `data` carries |
|---|---|
| **A, `upload` on** | `outputFile` (worker path — ignore), `fileSize`, `renderTime`, `upload.seaweedfs_url` **← the file**, `upload.watch_url` / `embed_url` / `download_url` (video hosting, `status: "importing"` at first), `warnings[]` |
| **A, `upload` off** | `outputFile` only — not retrievable |
| **B** | `{action, base_url, pattern, count, format, width, frame_size_bytes_avg, total_payload_bytes, source_duration_seconds, sample_fps}` |

⚠️ An `upload` object with an `error` key (`"PeerTube import failed: …"`) sits on a job whose status
is `completed`: the mp4 reached `seaweedfs_url`, the hosted-player copy did not. Read `data.upload`,
not the status.

⚠️ `data.warnings[]` means *rendered, but not everything you sent*: a voice longer than the video
is cut, captions past the last frame are not shown. A non-empty `warnings` is a finding to report.

## What completes and is still wrong

| You sent | Status | What you actually get | Caught by |
|---|---|---|---|
| a scene clip shorter than its `durationInSeconds` | completed | a frozen tail on that scene | `preflight` (`scene-N-length`), `render` (`frozen`) |
| music + voice, no `duckMusic` | completed | flat music under the speech | `preflight` (`duck` INFO) |
| captions timed from a transcript of the wrong take | completed | wrong words on screen | nothing automatic — see `references/audio-lane.md` |
| a voice longer than the scenes | completed | voice cut at the last frame, one `warnings[]` line | `preflight` (`voice-length`) |
| the same payload as yesterday | the OLD job | yesterday's render | `from_cache: true` on the submit |
| `upload` off | completed | no file you can open | the absence of `data.upload` |

And the ones that DO fail, correctly: a scene or voice URL that 404s or carries no media stream
(after 3 attempts), `duckMusic` without both tracks (422), a caption ending before it starts (422).

## References (loaded on demand)

- **`references/stitch-scenes.md`** — Path A payload, the duration arithmetic (transitions overlap —
  three 5 s scenes are 14 s, not 15), preprocessing, upload, timing.
- **`references/audio-lane.md`** — voice, ducking and captions: each contract, the caption format,
  the ~42–52 ms lead captions have over the heard audio. **Always read** before an audio job.
- **`references/extract-frames.md`** — Path B strategies, source-host rules, the manifest, the
  one-call page path and why its `dry_run` still spends a job.
- **`references/verify-the-output.md`** — the three verifier modes, what each check measures, what it
  cannot, and how to measure ducking yourself. **Always read.**
- **`references/read-results-and-failures.md`** — statuses, retries, error messages, the dedup
  cache, and how long a render may take.

## Learnings

`learnings/` holds what went wrong before, with provenance. They are starting points, not ground
truth — confirm against the live API before relying on a number.

- `2026-09-23-exit-0-is-not-a-correct-render` — the measured frozen-tail render, and why the black
  check did not see it.
- `2026-09-22-ducking-was-chosen-by-measuring-the-music-under-the-voice`
- `2026-09-22-audio-lands-42-to-52ms-after-the-timeline`
- `2026-09-22-only-http-urls-are-fetched`
- `2026-09-23-a-failed-job-does-not-say-why` — the reason is withheld; diagnose from the input.
- `2026-09-23-the-extract-frames-api-example-is-a-stitch-payload` — copying the published example
  returns 422; use the payload in `references/extract-frames.md`.

## See also

- **generate-media** (`@spideriq/gateway-skills`) — make the clips, images or voiceover first.
- **spiderpublish** (`@spideriq/publish-skills`) — the page a scroll sequence lands on, and deploying it.
- **spideriq-media-catalog** (`@spideriq/media-skills`) — find and host the files you stitch.
- `scripts/verify-video.py --self-test` — proves every check in the verifier can fail (16 cases).
