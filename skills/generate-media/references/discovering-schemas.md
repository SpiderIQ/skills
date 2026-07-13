# Discover the schema before you generate

The whole point of this surface is that **each model declares exactly which params
it accepts**. Read that declaration first — it is the contract, and anything not in
it is dropped silently.

## Steps

1. **List the models for your modality.**
   ```bash
   spideriq gate media-models --modality text-to-image        # or text-to-video | tts
   ```
   MCP: `gate_media_models({ modality: "text-to-image" })` ·
   HTTP: `GET /api/gate/v1/media/models?modality=text-to-image`.

2. **Read the target model's `inputs`.** Each key is a param you may set; the value
   describes its type / enum / range / default:
   ```json
   "inputs": {
     "prompt":          {"type":"string","required":true,"maxLength":4000},
     "negative_prompt": {"type":"string","default":""},
     "aspect_ratio":    {"type":"enum","enum":["1:1","16:9","9:16"],"default":"1:1"},
     "guidance_scale":  {"type":"float","min":1,"max":20,"step":0.5,"default":7.5},
     "seed":            {"type":"int"}
   }
   ```
   Keys NOT in this map (`cfg_scale`, `steps`, `1024x1024` as a `size`) do not exist
   for this model and will be discarded.

3. **Pre-flight your params — make the contract a check, not a hope:**
   ```bash
   node scripts/validate-media-params.mjs --model fal/flux-dev \
     --params '{"prompt":"a fox","negative_prompt":"blurry","seed":7}'
   ```
   It reports each param HONORED / DROPPED / OUT-OF-ENUM / OUT-OF-RANGE / MISSING-REQ
   and exits non-zero on any problem. Fix, then generate.

## WRONG / RIGHT

**WRONG — carry OpenAI-image habits onto a fal model:**
```json
{ "model": "fal/flux-dev", "params": { "size": "1024x1024", "quality": "hd", "cfg_scale": 7 } }
```
`fal/flux-dev` declares `aspect_ratio` (not `size`), `guidance_scale` (not `cfg_scale`),
and no `quality`. All three are dropped → the image ignores every tunable you set.

**RIGHT — pass what the model declares:**
```json
{ "model": "fal/flux-dev", "params": { "prompt": "…", "aspect_ratio": "1:1", "guidance_scale": 7.5, "seed": 7 } }
```

## Gotchas

- Param names differ per provider for the SAME concept (`guidance_scale` vs `cfg` vs
  `cfg_scale`; `aspect_ratio` vs `size`; `num_images` vs `n` vs `number_of_images`).
  Never assume — read `inputs`.
- `include_inactive=true` shows `coming_soon` models too; those are NOT generatable
  yet (a `generate` call 503s). Generate only `status: active` models.

## Verify

`validate-media-params.mjs` exits 0 ⇒ every param is declared and in range. Only then
call `gate_media_generate`.
