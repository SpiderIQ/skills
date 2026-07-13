---
name: generate-media
description: >
  Generate an image, video, or audio clip through SpiderGate and get back a
  stored media URL — schema-aware, so you pass exactly the tunables each model
  declares.
  Trigger on: "generate an image", "make a picture / logo / illustration",
  "text to image", "generate a video", "make a short clip", "text to video",
  "image to video", "text to speech", "generate a voiceover / narration", "TTS",
  "read this text aloud", "negative prompt", "set the seed / cfg / guidance /
  steps", "aspect ratio", "pick a voice / speed", "which media models can I use",
  "list image/video/audio models". This skill SENDS a generation and stores the
  result. It does NOT send chat completions (that's use-the-gateway) and does NOT
  browse a tenant's already-stored assets (that's spideriq-media-catalog).
version: "0.1.0"
category: ai-gateway
---

# Generate Media (image / video / audio, schema-aware)

SpiderGate turns one Bearer/PAT call into a stored media asset. Unlike a raw
provider, each model carries a **declared `inputs` schema** — the exact tunables
it accepts (`negative_prompt`, `seed`, `guidance_scale`, `aspect_ratio`,
`duration`, `voice`, `speed`, …). You **discover the schema, then generate**; the
result is uploaded to SpiderMedia and you get a URL back plus a cost breakdown.

```
   ┌── GET /api/gate/v1/media/models            list models + each model's `inputs`
   │       (image · video · audio-TTS; filter by modality)
your ──Bearer PAT──▶
   │
   └── POST /api/gate/v1/media/generations       { model, params }
           model = "<provider>/<model>"  (fal/flux-dev · kie/veo-3-fast · openai/tts-1)
           params = the per-model tunables the model DECLARES
           → { data:[{url}], est_cost:{…}, request_kind }   (URL = SpiderMedia-stored)
```

## Approach

- **First time / unknown model** — call `gate_media_models` and read the target
  model's `inputs`. That map IS the contract: keys you can set, their type, enum,
  min/max. → [references/discovering-schemas.md](references/discovering-schemas.md).
- **Image** — `model: fal/flux-dev` (or another `text-to-image` id) + prompt and
  whatever the schema declares (`negative_prompt`/`seed`/`guidance_scale`/
  `aspect_ratio`). → [references/image.md](references/image.md).
- **Video** — `model: kie/veo-3-fast` + prompt/duration/aspect_ratio. **Video is
  synchronous and can take minutes** — don't treat a slow call as a hang.
  → [references/video.md](references/video.md).
- **Audio (text-to-speech)** — `model: openai/tts-1` + `text`/`voice`/`speed`/
  `format`. Returns a stored audio URL. → [references/audio.md](references/audio.md).
- **Whose key pays** — generation uses the brand's OWN provider key (BYOK).
  `billed_usd: 0` on the response is EXPECTED, not free. → [references/byok-keys.md](references/byok-keys.md).

## Decision tree

| You want to… | Method | Model id example |
|---|---|---|
| See which models + tunables exist | `gate_media_models` (filter `modality`) | — |
| Generate an image | `gate_media_generate` | `fal/flux-dev`, `openai/gpt-image-1` |
| Generate a video | `gate_media_generate` | `kie/veo-3-fast` |
| Generate speech (TTS) | `gate_media_generate` | `openai/tts-1` |

## The one rule that trips agents up

<HARD-GATE name="read-the-schema-before-you-generate">
Before you call `gate_media_generate`, call `gate_media_models` and read THIS
model's `inputs`. If you are about to pass `cfg_scale`, `steps`, `1024x1024`, or
`negative_prompt` **without having confirmed the model declares that exact key**,
you are guessing — and **undeclared params are silently dropped** before the
provider call. That means your `seed` never reaches the model, the result is not
reproducible, and you paid for a generation that ignored half your request. The
schema is the contract: pass only keys the model's `inputs` lists, with values
inside their declared enum / min–max.

**Make it a fact, not a hope** — run the pre-flight and paste its report:

```bash
node scripts/validate-media-params.mjs --model <id> --params '<json>'
# → each param HONORED / DROPPED / OUT-OF-ENUM / OUT-OF-RANGE; exits non-zero if any problem.
```
</HARD-GATE>

## Surfaces

- **MCP:** `gate_media_models`, `gate_media_generate` (the `@spideriq/mcp-gate` slice; also in the kitchen-sink `@spideriq/mcp` and the mac-128 slice).
- **CLI:** `spideriq gate media-models [--modality …]` · `spideriq gate media-generate -m <id> -p '<json>'`.
- **HTTP:** `GET /api/gate/v1/media/models` · `POST /api/gate/v1/media/generations`.

## See also

- **[use-the-gateway](../use-the-gateway/SKILL.md)** — SEND a chat completion (this skill is media, not chat).
- **[model-catalog](../model-catalog/SKILL.md)** — pick a *chat* model; media models are listed by `gate_media_models` here.
- **[spideriq-media-catalog](https://market.opvs.ai)** (`@spideriq/media-skills`) — BROWSE a tenant's already-stored assets (read-only DAM), not generation.
