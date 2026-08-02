# Generate speech (text-to-speech)

Generate narration / a voiceover from text and get a stored audio URL back. Unlike
the OpenAI-compat `/v1/audio/speech` passthrough (which streams raw bytes), this path
uploads the clip to SpiderMedia and returns a URL — much easier for an agent to hand off.

## Steps

1. `gate_media_models --modality tts` → `openai/tts-1` (read its `inputs`).
2. Pre-flight params.
3. Generate:
   ```bash
   spideriq gate media-generate -m openai/tts-1 \
     -p '{"text":"Welcome to SpiderIQ.","voice":"nova","speed":1.0,"format":"mp3"}'
   ```
   MCP: `gate_media_generate({ model:"openai/tts-1", params:{ text:"…", voice:"nova" } })`.
4. Response: `data[0].url` (stored audio) + `est_cost` (per-1k-chars).

## Declared params (openai/tts-1)

| Param | Notes |
|---|---|
| `text` | required — the words to speak (this is the field name, NOT `input` or `prompt`) |
| `voice` | enum: `alloy | echo | fable | onyx | nova | shimmer` (default `alloy`) |
| `speed` | float 0.25–4 (default 1) |
| `format` | enum: `mp3 | wav | opus` (default `mp3`) |

## Gotchas

- The text field is **`text`**, not `input`/`prompt`. Passing `input` → DROPPED → the
  call has no text → 400. (The endpoint maps the declared `text` onto the provider's
  `input` internally; you pass `text`.)
- Cost is per-1000-characters — long text costs proportionally; the char count drives
  `est_cost`.
- `openai/tts-1-hd` (higher quality, ~2× cost) rides the same tool once activated —
  check `gate_media_models` for its status.

## Verify

Fetch `data[0].url`, confirm `content-type: audio/*` (`verify-media-result.mjs`).
