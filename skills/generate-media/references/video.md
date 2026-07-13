# Generate a video

## Steps

1. `gate_media_models --modality text-to-video` → pick an active id (`kie/veo-3-fast`).
2. Pre-flight params.
3. Generate:
   ```bash
   spideriq gate media-generate -m kie/veo-3-fast \
     -p '{"prompt":"a drone shot over a coastline at sunset","duration":"6","aspect_ratio":"16:9"}'
   ```
4. Response: `data[0].url` (SpiderMedia-stored video) + `est_cost`.

## The thing that surprises agents

<!-- The #1 video gotcha: it is a long SYNCHRONOUS call. -->
**Video generation is SYNCHRONOUS and can take minutes.** The provider is a
submit→poll job; SpiderGate polls it server-side (up to ~20 min for veo) and returns
only when the clip is ready. A call that takes 3–15 minutes is **normal, not a hang** —
set a generous client/tool timeout and don't retry a still-running request (you'll pay twice).

## Common declared params (READ the model's `inputs`)

- `prompt` (required), `duration` (enum, e.g. `"4"|"6"|"8"` seconds — a STRING enum,
  not an int), `aspect_ratio` (`16:9|9:16|1:1`), and for image-to-video an
  `image_url` first-frame. Not every video model declares `negative_prompt`/`seed`/
  `resolution` — check.

## Gotchas

- `duration` is usually an **enum of strings** (`"6"`), not a free integer — passing
  `6` (number) or `"7"` (not in the enum) is OUT-OF-ENUM / dropped.
- Cost for credit-billed providers (kie) may show as `est_cost` in credits→USD; BYOK
  still bills 0 per request.

## Verify

Fetch `data[0].url`, confirm `content-type: video/*` (`verify-media-result.mjs`).
