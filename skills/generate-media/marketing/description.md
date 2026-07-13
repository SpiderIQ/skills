# Generate Media — image, video, and voice, schema-aware

The `generate-media` skill lets your agent create media through SpiderGate with one
Bearer/PAT call and get a **stored URL** back — no juggling fal / kie / Google / xAI /
OpenAI keys and their different param names.

- **"Make a 16:9 product shot"** → `gate_media_generate({ model:"fal/flux-dev", params:{ prompt:"…", aspect_ratio:"16:9", seed:7 } })` → a SpiderMedia image URL.
- **"Turn this into a short clip"** → `kie/veo-3-fast` (synchronous; takes minutes) → a stored video URL.
- **"Read this aloud in a warm voice"** → `openai/tts-1` with `text`/`voice`/`speed` → a stored audio URL.

**What makes it *schema-aware*.** Every model declares exactly which tunables it
accepts (`negative_prompt`, `guidance_scale`, `aspect_ratio`, `duration`, `voice`, …).
The skill teaches the discover-then-generate flow and ships a **deterministic pre-flight
script** — `validate-media-params.mjs` classifies every param HONORED / DROPPED /
OUT-OF-ENUM / OUT-OF-RANGE against the live schema and fails fast — so a param the model
would silently drop never costs you a wasted generation.

BYOK: generation runs on your brand's own provider key; `billed_usd: 0` on the response
is expected (BYOK is billed monthly by key-count, not per request).
