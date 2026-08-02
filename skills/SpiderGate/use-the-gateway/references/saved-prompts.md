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
- `prompt.<handle>` — resolves by **slug OR exact name** within a project, so a prompt
  named `Support Bot` answers to both `prompt.support_bot` and `prompt.Support Bot`.
  Requires `project_id`; without one it **fails with 400
  `prompt_reference_needs_project`** — the reference is *not* ignored and the
  completion does not proceed.

**Reference errors are loud and coded:** `prompt_reference_needs_project` (400) ·
`prompt_not_found` (404 — unknown handle or id) · `prompt_reference_ambiguous`
(409 — two names slugifying onto one handle; the message names both ids). A failed
reference never degrades into a plain completion.

> Unlike the media path, the stored `model` **does** apply here, because `model` is
> optional on chat completions.

## Manage them

`gate_prompt_create` (→ returns a `prompt_…` public id) · `gate_prompt_list`
(a project's prompts) · `gate_prompt_search` (by name/description, brand-wide) ·
`gate_prompt_get` · `gate_prompt_delete`. On the CLI: `spideriq gate prompt
create|list|search|get|delete`. As declared HTTP methods with their projects, see the
**`studio-prompts`** skill. Saved prompts are brand-scoped and unique by name
**per project** — though two different names in one project can still collide on slug.

The same reference forms work for media generation — see the `generate-media`
skill's `references/saved-prompts.md`.
