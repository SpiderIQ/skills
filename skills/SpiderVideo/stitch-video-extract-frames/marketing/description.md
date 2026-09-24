## stitch-video-extract-frames

Two jobs behind one service, and a verifier for both. Backed by the SpiderVideo worker.

### What this skill does

- **Stitch** (`create_video`, `POST /jobs/spiderVideo/submit`) — join 1-50 hosted clips into one
  h264 mp4 with fade transitions, portrait or landscape, background music, a voiceover, music that
  ducks 12 dB under the voice, and burned word-by-word captions. Upload it to SpiderMedia and get a
  URL back.
- **Frames** (`POST /jobs/spiderVideo/extract-frames/submit`, or `video_to_scroll_sequence` for the
  one-call page path) — pull a numbered WebP/JPEG sequence out of a video, ready for the
  `sys-scroll-sequence` scroll animation.
- **Measure** (`scripts/verify-video.py`) — check a request before a render is spent, check the
  rendered video for frozen or black runs, silence and the wrong length, and check a frames manifest
  for missing, animated or identical frames. It prints a PASS/FAIL table an agent can paste.

### Why the verifier ships with it

A render that completes can still be wrong. A scene clip shorter than its declared length renders
with no error and a frozen tail — same codec, size, duration and frame count as a correct render.
The skill's one hard rule is to measure before reporting, and the script is how.

### Typical workflows

- **A 9:16 reel from generated clips** — generate the clips and narration with `generate-media`,
  preflight the request, stitch with `duckMusic` and captions, verify, share the upload URL.
- **A cinematic scroll hero** — extract 120 frames from a product video, verify the manifest, place
  the sequence on a page with `spiderpublish`, deploy.
