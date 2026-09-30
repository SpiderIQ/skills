# Read results, and read failures

Both paths are asynchronous: the submit returns `{job_id, status: "queued"}` and nothing else. The
video or the frames arrive in the results, minutes later.

## Steps

1. **Submit**, keep the `job_id`, and check the submit response for `"from_cache": true` (below).
2. **Poll** `GET /jobs/{job_id}/status` (MCP `get_job_status`) every 5–10 s. Add `?format=yaml` to cut
   tokens.
3. **Read** `GET /jobs/{job_id}/results` (MCP `get_job_results`) once the status is terminal.
4. **Measure** the output (`verify-the-output.md`) before reporting it.

## Statuses

| Status | Means | Do |
|---|---|---|
| `queued` | waiting for the renderer, **or already rendering** — a first attempt never reads `processing` | keep polling; a render may take up to 30 min |
| `processing` | a **retry** is running after a failed attempt | keep polling — something in the input may be wrong |
| `completed` | finished — not necessarily right | read `data`, then measure |
| `failed` | every attempt failed — or the request was refused | the reason is withheld unless it starts `[invalid_video_request]` — see *A failed job does NOT tell you why* |
| `cancelled` | stopped | resubmit if you still need it |

A failed attempt is retried automatically (3 attempts in total, a short backoff between them), so a
bad URL takes about a minute to reach `failed`, not seconds. A request the renderer **refuses** is not
retried: it fails on the first attempt, because it would fail the same way every time.

## The results envelope

```json
{
  "success": true,
  "job_id": "…",
  "type": "spiderVideo",
  "status": "completed",
  "completed_at": "2026-09-22T14:44:05Z",
  "data": { … the render result or the frames manifest … },
  "error_message": null
}
```

Path A `data`: `upload.seaweedfs_url` is the file (only with `upload` on); `outputFile` is a path
inside the renderer — never hand it to a user. Path B `data`: the manifest in `extract-frames.md`.

## A failed job does NOT tell you why — unless it was refused

**The exception first.** A request the renderer refuses fails once, with a sentence written for you:

```
[invalid_video_request] The 20-frame transition is longer than scene 2, which is 15 frames at 30 fps. Use a transition of at most 15 frames, or 0 for hard cuts.
```

Do what it says and resubmit. You will rarely see one, because the API checks most of these at
submit and answers 422 instead (below).

**Every other failure.** For a SpiderVideo job, `error_message` in the results is the same sentence:

> *This job failed. The technical detail is internal, and has been recorded for support — quote this
> job id if you need help with it.*

The real reason is withheld from client responses by design (measured against the live API: a 404
scene, a missing storage bucket, a render timeout and a too-short source all read identically). So
do not parse `error_message`, and do not retry blindly — a failure caused by the input fails the
same way every time. Diagnose from the input instead:

| Likely cause | Path | How to find it yourself |
|---|---|---|
| a scene, music or voice URL does not download (404, 403, slow host) | A | `verify-video.py preflight request.json` → `*-reachable` FAIL |
| a scene URL is a web page, not a video file | A | `preflight` → `scene-N-video` FAIL |
| the voice or music file has no audio stream | A | `preflight` → `voice-audio` / `music-audio` FAIL |
| a non-http(s) URL (`file://`, a relative path) | A | read your request — only http(s) is fetched |
| `upload` on, but the account has no SpiderMedia storage | A | re-run without `upload`: if that completes, storage is the cause |
| the render ran past 30 minutes | A | fewer or shorter scenes; many transcoded scenes add minutes each |
| the source URL answers non-200, or a third-party host breaks the source rules (content type, 500 MB, 30 s) | B | `curl -sI <video_url>` — check status, `Content-Type`, `Content-Length` |
| no SpiderMedia storage on the account for the frames | B | the one-call tool fails the same way for every source |
| the source is too short for the strategy (fewer than 2 frames) | B | `ffprobe` the source duration; lower `target_frames` or use a longer source |

If none of these explains it, quote the `job_id` to support — they can read the recorded detail.

## 422 on submit — the request was refused, nothing ran

| 422 says | Fix |
|---|---|
| `duckMusic requires both musicUrl and voiceUrl` | send both, or drop `duckMusic` |
| `The N-frame transition is longer than scene K …` | shorten the fade to the number it gives, or send `0` for hard cuts |
| `Scene K rounds to zero frames at 30 fps …` | that scene is under 1/60 s — lengthen it or drop it |
| `loudnessTarget` greater/less than … | use −30 to −10 LUFS, or omit it |
| `endMs must be >= startMs` | a caption ends before it starts |
| `voiceUrl` pattern | the voice URL is not http(s) |
| `projectName` / `scenes` field required | a frames payload was sent to the stitch route — use `/jobs/spiderVideo/extract-frames/submit` |
| `strategy=… requires …` | the frames strategy is missing its companion field |
| a flat body | wrap the fields: `{"payload": {…}}` |

## The 24-hour dedup

An identical request from the same account within 24 hours returns the **earlier** job: the submit
answers `"from_cache": true` with the old `job_id`. That is usually what you want for a network
retry and never what you want after changing the file behind a URL.

**WRONG** — replace `intro.mp4` in storage, resubmit the same payload, report the "new" render.

**RIGHT** — change `projectName` (`spring-promo-reel` → `spring-promo-reel-v2`) so the request differs,
and check the submit says `"from_cache": false`.

## Gotchas

- Do not treat a long `queued` as stuck. Renders run one at a time, and a running render still reads
  `queued`. Only after 30 minutes of `queued` is something wrong.
- Read `status` first, then `success`. `success` is `true` only for a completed job with no recorded
  error.
- `data.warnings[]` on a completed render lists what was cut. Report it.
