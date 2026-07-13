# Author a model's settings panel (`settings_schema`)

The Studio/Playground **settings panel** a client sees for a chat/LLM model is
driven by a per-model `settings_schema` — a small JSON-schema-shaped object you
author with `setModelMeta` (`gate_catalog_model_set_meta`, `PATCH
/models/{model_id}/meta`). The panel is **schema-driven**: it is data, not code,
so adding or changing a model's controls is a curator write — **no deploy**.

This is the WRITE side of SF-16. The renderer is the dashboard `<SettingsPanel>`;
the resolution + provider defaults live in
`app/services/gate/settings_schema.py`.

## The unified dialect (what a schema looks like)

A `settings_schema` is a `type: "object"` root with a **non-empty `properties`
map** of control-name → control definition. Each control carries:

| Key | Meaning |
|---|---|
| `type` | Canonical JSON-schema type: `string` \| `integer` \| `number` \| `boolean` \| `array` \| `object` \| `image` |
| `x-control` | Render hint that drives the panel: `text` \| `textarea` \| `select` \| `segmented` \| `slider` \| `stepper` \| `seed` \| `dropzone` \| `toggle` |
| `title` | Label shown above the control |
| `description` | Helper text under the control |
| `default` | Pre-filled value |
| `enum` | A `[...]` list of allowed values — a MODIFIER on a string/number, **not** a type. Drives `select` / `segmented`. |
| `min` / `max` / `step` | Numeric bounds for `slider` / `stepper` |
| `required` | Whether the field must be set |

> **`min`/`max`, NOT `minimum`/`maximum`.** Slider and stepper bounds use the
> media-style `min` / `max` / `step` keys. The JSON-schema `minimum` / `maximum`
> keys are **silently ignored** and the control falls back to a 0–100 range. This
> is the #1 authoring mistake — always use `min`/`max`/`step`.

## The control name IS the endpoint key

Each key in `properties` is the exact parameter name forwarded to the completion
(`temperature`, `top_p`, `max_tokens`, `response_format`). The panel emits those
keys byte-for-byte, so name a control after the endpoint field it drives — do not
invent display-only names.

## Worked example — the shared chat default

This is the schema every chat model inherits when it has no override. Author it
on a specific model's row only when that model **diverges** from the default:

```json
{
  "type": "object",
  "properties": {
    "temperature": {
      "type": "number", "title": "Temperature",
      "description": "Higher = more random, lower = more deterministic.",
      "default": 0.7, "min": 0, "max": 2, "step": 0.01,
      "x-control": "slider"
    },
    "top_p": {
      "type": "number", "title": "Top P",
      "description": "Nucleus sampling — consider tokens up to this cumulative probability.",
      "default": 1, "min": 0, "max": 1, "step": 0.01,
      "x-control": "slider"
    },
    "max_tokens": {
      "type": "integer", "title": "Max tokens",
      "description": "Upper bound on tokens generated in the response.",
      "default": 2048, "min": 1, "max": 32768, "step": 1,
      "x-control": "stepper"
    },
    "response_format": {
      "type": "string", "title": "Response format",
      "description": "Force plain text or a JSON object.",
      "default": "text", "enum": ["text", "json_object"],
      "x-control": "segmented"
    }
  }
}
```

Author it via `setModelMeta` (resolve the numeric `id` first with `listModels`):

```
setModelMeta(model_id=<int>, settings_schema={ ...the object above... })
```

## Resolution is two-level (override → provider default → chat default)

When the panel loads a model it resolves the effective schema:

1. **The model's `settings_schema`** (this per-model OVERRIDE), else
2. **the provider default** (a code-side product decision, `PROVIDER_DEFAULT_SETTINGS_SCHEMA`
   in `settings_schema.py` — empty by default), else
3. **the shared chat default** (the example above).

So `NULL` on a row means "inherit the provider default." You only author a
per-model schema when a specific model genuinely needs a different control set
(e.g. it rejects `top_p`, or exposes a reasoning-effort control). **Do not
fabricate capability differences** — an override that just restates the default is
noise.

Provider-wide changes (every model of a provider diverges the same way) are a
**code** change to `PROVIDER_DEFAULT_SETTINGS_SCHEMA`, not a per-row author — a
deliberate split: per-model curation here, provider policy in code.

## It survives the discovery sync

`settings_schema` is absent from BOTH `ON CONFLICT` set-lists of the 6h discovery
sync, so an authored schema is **never overwritten** by a sync tick — the same
durability guarantee as authored `display_name` under `is_curated`. You do not
need to re-author after a sync.

## Rules of the write

- **Whole-schema replace, not merge.** `settings_schema` REPLACES the row's entire
  panel schema. To tweak one control, send the COMPLETE object you want.
- **Empty is a 422.** An empty object, or one whose `properties` is empty/missing,
  is rejected ("settings_schema must contain a non-empty 'properties' object") — it
  will not silently clear the panel.
- **To revert to the provider default**, clear the column directly (a data op, like
  un-curating): `UPDATE gate_model_catalog SET settings_schema = NULL WHERE id = <id>;`
  A curator-PATCH of `{"settings_schema": null}` leaves a JSONB `'null'` residue — use
  the DB `UPDATE` to restore the true inherit-default state.
- **Chat/LLM models only.** This field is on `gate_model_catalog`. Media models
  (image/video/audio) carry their panel schema on `gate_media_models.inputs`,
  authored via a **seed migration**, not this curator surface (`setMediaMeta` has no
  `settings_schema` param). The DIALECT is the same across both.
