# A render that completes can still be wrong

**What happened.** We rendered the same one-scene stitch twice on the live worker image. The only
difference: the first scene clip was 5 s long, the second was 2 s long. Both declared
`durationInSeconds: 5`.

| | exit | codec | size | frames | duration | black frames | frozen frames |
|---|---|---|---|---|---|---|---|
| 5 s clip | 0 | h264 | 1080x1920 | 150 | 5.000 s | 0 | 0 |
| 2 s clip | 0 | h264 | 1080x1920 | 150 | 5.000 s | **0** | **90** (frames 61-150) |

Everything a job result or an ffprobe line can tell you was identical. The second video spends 3 of
its 5 seconds on a still of the clip's last frame.

**Why a black check misses it.** The renderer holds the last decoded frame instead of going black,
so the average brightness stays where the clip left it (126.9 on a 0-255 scale, every frame). Only a
frame-to-frame difference sees it.

**What does fail, correctly.** A scene URL that 404s: the download is retried three times, the job
fails, and no file is written. "A missing asset renders black with exit 0" is not how this renderer
behaves — it was checked, not assumed.

**What to do.**
- Before submitting: `python3 scripts/verify-video.py preflight request.json` opens every clip and
  FAILs `scene-N-length` when a clip is shorter than you declared.
- After rendering: `python3 scripts/verify-video.py render <url> --request request.json` FAILs
  `frozen` and names the scene.
- Never report "rendered successfully" from `completed`, a file size or an ffprobe line.
