# Extract frames for a scroll animation (Path B)

Turn one video into a numbered image sequence (`frame_0001.webp` …) in your SpiderMedia bucket, for
a canvas that scrubs through the frames as the visitor scrolls. The result plugs straight into the
`sys-scroll-sequence` component's three props: `base_url`, `pattern`, `count`. No Remotion, no
transitions, no audio — this path is ffmpeg only.

## Two ways in

| You want | Use | Result |
|---|---|---|
| The frames **on a page**, as a draft block | MCP `video_to_scroll_sequence` · CLI `spideriq video to-scroll-sequence` · `POST /dashboard/scroll-sequence/from-video` | manifest + the inserted block + the page, as a DRAFT |
| **Only** the frames | `POST /jobs/spiderVideo/extract-frames/submit` | a job whose results carry the manifest |

`video_to_scroll_sequence` submits the extract, waits for it (default up to 300 s), builds the block
and inserts it into an **existing** page as a draft. It never publishes — deploy afterwards
(`content_deploy_site_preview`, then `content_deploy_site_production`; see spiderpublish).

⚠️ Its `dry_run: true` still **runs and pays for the extraction job**; it only skips writing the
page. And the page must already exist even in a dry run.

⚠️ There is no MCP tool that submits a bare extract. `submit_job` with type `spiderVideo` reaches the
**stitch** route and answers 422 (`projectName` / `scenes` required).

## Steps — frames only, over HTTP

```bash
curl -sS -X POST https://spideriq.ai/api/v1/jobs/spiderVideo/extract-frames/submit \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" -H "Content-Type: application/json" \
  -d '{"payload": {
        "action": "extract_frames",
        "video_url": "https://media.spideriq.ai/client-cli-abc123/source/hero.mp4",
        "strategy": "target_frames",
        "target_frames": 120,
        "output_format": "webp",
        "output_width": 1280,
        "output_quality": 80
      }}'
# 201 → {"job_id": "…", "status": "queued", …}
```

Poll `GET /jobs/{job_id}/status`, then `GET /jobs/{job_id}/results > results.json`, then:

```bash
python3 scripts/verify-video.py frames results.json
```

## Strategies — pick exactly one

| `strategy` | Also send | Frames produced |
|---|---|---|
| `target_frames` | `target_frames` (10–600) | exactly N, spread over the whole video — the usual choice |
| `fps` | `fps` (1–60) | ⌊duration × fps⌋ over the whole video |
| `duration_fps` | `fps` + `duration_seconds` (1–120) | the first `duration_seconds`, at `fps` |

Missing the companion field is a 422 naming it (`strategy=target_frames requires target_frames`).

| Output field | Default | Limits |
|---|---|---|
| `output_format` | `webp` | `webp` or `jpeg` — WebP is about half the bytes at the same quality |
| `output_width` | 1280 | 320–1920; height follows the source's aspect |
| `output_quality` | 80 | 50–95 |

## The manifest

`data` in the results (and `manifest` in the one-call tool's response):

```json
{
  "action": "extract_frames",
  "base_url": "https://media.spideriq.ai/client-cli-abc123/content/scroll-sequences/<job_id>",
  "pattern": "frame_{0001..0120}.webp",
  "count": 120,
  "format": "webp",
  "width": 1280,
  "frame_size_bytes_avg": 38400,
  "total_payload_bytes": 4608000,
  "source_duration_seconds": 7.467,
  "sample_fps": 16.0714
}
```

`pattern`'s zero-padding is the width the component's URL generator expects — pass it through
unchanged. Frame N is `<base_url>/frame_000N.webp` (four digits here).

## Gotchas

- **The source must be reachable by URL.** `media.spideriq.ai` and `media.di-atomic.com` are trusted.
  Any other host must answer with `Content-Type` `video/mp4`, `video/webm` or `video/quicktime`, a
  `Content-Length` under 500 MB, and finish downloading within 30 s — otherwise the job fails. The
  result will NOT say which rule broke (the reason is withheld from client responses), so check the
  source yourself first: `curl -sI <video_url>`. Host a large source on SpiderMedia.
- **The account needs a SpiderMedia bucket** — the frames are uploaded there. Without one every
  extract fails.
- **The frames also appear in your SpiderMedia library.** Cleaning up a test means deleting the
  files, not just forgetting the job.
- **A very short source cannot make a sequence.** Fewer than 2 frames computed fails the job, and so
  does ffmpeg producing fewer frames than planned. `ffprobe` the source duration before choosing
  `target_frames`.
- **An identical request within 24 hours returns the EARLIER job** — including through
  `video_to_scroll_sequence`, which then hands back the earlier manifest. If you deleted those frames,
  that manifest points at nothing. Change a field (e.g. `target_frames` 120 → 121) to force a new run.
- **The published API reference example for this route shows a stitch payload.** Copying it returns
  422. The payload above is the one the route accepts (see `learnings/`).
- Uploads are sequential: 120 frames take roughly 30–60 s after ffmpeg finishes.

## Verify

`python3 scripts/verify-video.py frames results.json` — every frame URL answers 200, the pattern
expands to `count`, the sampled frames are single stills (not one animated file) at the manifest's
width, and the first, middle and last frames differ. Byte-identical frames mean the scroll animation
will not move: the source was a still, or the strategy sampled one moment. Then check the page with
spiderpublish's visual check after deploying — the verifier checks files, not the rendered page.
