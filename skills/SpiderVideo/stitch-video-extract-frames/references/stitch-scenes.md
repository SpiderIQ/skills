# Stitch scenes into one video (Path A)

Join clips you already host into one mp4 with fade transitions (or hard cuts) and, optionally, music,
a voiceover and captions. The renderer writes h264 at 30 fps, `yuv420p`, BT.709 limited range;
nothing is generated.

## Steps

1. **Write the request as a file** — the verifier reads the same JSON you submit:

   ```json
   {
     "projectName": "spring-promo-reel",
     "aspectRatio": "9:16",
     "scenes": [
       {"videoUrl": "https://media.spideriq.ai/client-cli-abc123/source/intro.mp4", "durationInSeconds": 3},
       {"videoUrl": "https://media.spideriq.ai/client-cli-abc123/source/product.mp4", "durationInSeconds": 8},
       {"videoUrl": "https://media.spideriq.ai/client-cli-abc123/source/outro.mp4", "durationInSeconds": 4}
     ],
     "transitionDurationInFrames": 15,
     "musicUrl": "https://media.spideriq.ai/client-cli-abc123/audio/upbeat.mp3",
     "musicVolume": 0.3,
     "upload": {"enabled": true}
   }
   ```

2. **Preflight it** — before any render is spent:

   ```bash
   python3 scripts/verify-video.py preflight request.json
   ```

   Fix every FAIL. `scene-N-length` FAIL means that clip is shorter than you declared and will render
   a frozen tail; either shorten `durationInSeconds` to the clip length or use a longer clip.

3. **Submit.** MCP:

   ```
   create_video({
     project_name: "spring-promo-reel", aspect_ratio: "9:16",
     scenes: [ {videoUrl: "…/intro.mp4", durationInSeconds: 3}, … ],
     music_url: "…/upbeat.mp3", music_volume: 0.3, upload: true
   })
   ```

   HTTP — the fields go inside `payload`:

   ```bash
   curl -sS -X POST https://spideriq.ai/api/v1/jobs/spiderVideo/submit \
     -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" -H "Content-Type: application/json" \
     -d "{\"payload\": $(cat request.json)}"
   # 201 → {"job_id": "…", "status": "queued", "from_cache": false, …}
   ```

   If the response says `"from_cache": true` you got an EARLIER job for an identical request — see
   `read-results-and-failures.md`.

4. **Poll** `GET /jobs/{job_id}/status` every 5–10 s until `completed` or `failed`, then read
   `GET /jobs/{job_id}/results`. The file is `data.upload.seaweedfs_url`.

5. **Measure** — `python3 scripts/verify-video.py render "<seaweedfs_url>" --request request.json`.

## The duration arithmetic

The output is **not** the sum of the scene lengths. Each fade overlaps the end of one scene with the
start of the next:

```
frames = Σ round(durationInSeconds × 30)  −  (scenes − 1) × transitionDurationInFrames
```

| Scenes | Transition | Output |
|---|---|---|
| 3 × 5 s | 15 frames (default) | 450 − 30 = 420 frames = **14.0 s** |
| 3 + 8 + 4 s | 15 frames | 450 − 30 = 420 frames = **14.0 s** |
| 3 × 5 s | 0 (hard cuts) | 450 frames = **15.0 s** |

Plan music, voice and caption timings against the **output** timeline, not the sum. With hard cuts
(`0`) the output timeline IS the sum, and each cut lands exactly on a scene boundary: 5.000 s and
10.000 s for 3 × 5 s.

**A fade must fit every scene.** Each fade overlaps two neighbouring scenes, so it cannot be longer
than either of them (equal is fine). A 20-frame fade next to a 0.5 s (15-frame) scene answers
**422** `SCHEMA_VALIDATION_FAILED`. The error's `msg`, under `what_was_expected.errors`, names the
scene and the largest fade that fits:

```
Value error, The 20-frame transition is longer than scene 2, which is 15 frames at 30 fps. Use a
transition of at most 15 frames, or 0 for hard cuts.
```

## Field reference

| Field | Default | Limits |
|---|---|---|
| `projectName` | — (required) | 1–200 chars; names the output file |
| `aspectRatio` | `9:16` | `9:16` → 1080×1920, `16:9` → 1920×1080 |
| `scenes[]` | — (required) | 1–50 scenes |
| `scenes[].durationInSeconds` | — (required) | > 0, ≤ 300 |
| `transitionDurationInFrames` | 15 | 0–60 (0 = hard cuts); never longer than a neighbouring scene (422) |
| `musicUrl` / `musicVolume` | none / 0.3 | volume 0–1 |
| `voiceUrl` / `voiceVolume` / `duckMusic` / `captions` | — | see `audio-lane.md` |
| `loudnessTarget` | none (off) | −30 to −10 LUFS; see `audio-lane.md` → *Loudness* |
| `upload.enabled` | false | needs SpiderMedia on the account |
| `preprocess.enabled` | on when omitted | see Gotchas |

## Gotchas

- **Clips are scaled to COVER the frame and cropped.** A 16:9 clip in a 9:16 video keeps its centre
  strip and loses the sides. Shoot or crop for the aspect you ask for.
- **A clip plays from its start for exactly `durationInSeconds`.** Longer clips are trimmed; shorter
  ones freeze on their last frame for the remainder — with `completed` status (the skill's HARD-GATE).
- **Music is not looped.** A 20 s track under a 30 s video leaves 10 s of silence; a longer track is
  cut at the last frame.
- **`preprocess` is ON when you omit it.** A scene whose format or codec the renderer cannot play is
  transcoded automatically before the render, which adds minutes per scene. Send
  `"preprocess": {"enabled": false}` over HTTP to refuse unplayable scenes instead. (`create_video`
  can only send `preprocess: true`, so through MCP it is always on.)
- **`test: true` is not a dry run.** It routes the job to a test queue that no production worker
  drains; the job waits there. There is no dry-run mode for a render.
- **One render runs at a time.** A job can sit `queued` behind another render before its own starts.
  The API's own estimate: 1–5 scenes 1–3 min, 5–15 scenes 3–8 min, 15–50 scenes 8–20 min. A render
  that exceeds 30 minutes fails.
- **Non-http(s) URLs are accepted, then fail.** `videoUrl` and `musicUrl` are plain strings at the
  API: a `file://` or relative path answers 201 and fails at download. Only http(s) is fetched.

## Verify

```bash
python3 scripts/verify-video.py render "$SEAWEEDFS_URL" --request request.json
```

Expect `duration` to equal the arithmetic above (±0.1 s), `dimensions` to match the aspect, and
`black` / `frozen` to PASS. A `frozen` FAIL names the scene; compare that scene's clip length with its
`durationInSeconds`. Paste the table; see `verify-the-output.md` for what it does not check.
