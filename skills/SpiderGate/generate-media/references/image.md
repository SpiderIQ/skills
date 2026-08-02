# Generate an image

## Steps

1. `gate_media_models --modality text-to-image` → pick an id (`fal/flux-dev`,
   `openai/gpt-image-1`, `google/imagen-3`, `x_ai/grok-image`, …) and read its `inputs`.
2. Pre-flight your params (`validate-media-params.mjs`).
3. Generate:
   ```bash
   spideriq gate media-generate -m fal/flux-dev \
     -p '{"prompt":"a red fox in snow, cinematic","aspect_ratio":"16:9","seed":7}'
   ```
   MCP: `gate_media_generate({ model:"fal/flux-dev", params:{ prompt:"…", aspect_ratio:"16:9", seed:7 } })`.
4. The response carries `data[0].url` (SpiderMedia-stored) + `est_cost`.

## Common declared params (READ the model's own `inputs` — these vary)

| Concept | fal | openai (gpt-image-1) | google (imagen-3) |
|---|---|---|---|
| prompt | `prompt` | `prompt` | `prompt` |
| shape | `aspect_ratio` | `size` (`1024x1024`…) | `aspect_ratio` |
| count | `num_images` | `n` | `number_of_images` |
| guidance | `guidance_scale` | — | — |
| steps | `num_inference_steps` | — | — |
| seed | `seed` | — | — |
| negative | `negative_prompt` | — | — |

## Gotchas

- **Reproducibility needs a declared `seed`.** If the model doesn't declare `seed`
  (openai/google don't), you cannot pin the output — don't promise a reproducible image.
- `openai/gpt-image-1` uses `size` (`1024x1024`/`1024x1536`/`1536x1024`/`auto`), NOT
  `aspect_ratio`. Passing `aspect_ratio` to it → dropped.

## Verify

Fetch `data[0].url` and confirm it's a real image (`content-type: image/*`) — run
`scripts/verify-media-result.mjs --url <url>`. A 200 from generate is not proof the
asset rendered.
