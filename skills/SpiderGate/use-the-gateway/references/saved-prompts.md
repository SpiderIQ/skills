# Saved prompts — reuse a system prompt + model + settings by reference

A **saved prompt** is a named bundle of `{system_prompt, model, settings}` (plus
optional reference media) stored inside a **Studio project**. Reference one in a
chat completion body's `prompt` field and the server expands it before the call —
your explicit body values **override** the stored ones.

## Reference it in a completion

```jsonc
// The `prompt` field carries the reference; the server prepends the stored
// system prompt, applies the stored model + settings, then your body wins:
{
  "prompt": "prompt:prompt_ab12…",   // stable id (no project needed) …
  // or "prompt": "prompt.support-bot", + "project_id": "<uuid>"  (by name)
  "messages": [{ "role": "user", "content": "Refund policy?" }]
  // any "model" / "temperature" / a "system" message you set here OVERRIDES the prompt's
}
```

Precedence: a `model` you set wins over the stored model; a `system` message you
supply suppresses the stored `system_prompt`; stored `settings` fill only the
sampling keys you left unset. Resolving bumps the prompt's `last_used_at`.

- `prompt:<public_id>` — resolves globally within your brand; use from agents/CLI.
- `prompt.<name>` — resolves by name **within a project**; requires `project_id`.
  Without one the reference is ignored.

## Manage them

`gate_prompt_create` (→ returns a `prompt_…` public id) · `gate_prompt_list`
(a project's prompts) · `gate_prompt_search` (by name/description, brand-wide) ·
`gate_prompt_get` · `gate_prompt_delete`. On the CLI: `spideriq gate prompt
create|list|search|get|delete`. Saved prompts are brand-scoped and unique by name
**per project**.

The same reference forms work for media generation — see the `generate-media`
skill's `references/saved-prompts.md`.
