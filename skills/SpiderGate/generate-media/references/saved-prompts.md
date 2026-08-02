# Saved prompts — reuse a prompt bundle by reference

A **saved prompt** is a named, reusable bundle of `{system_prompt, model,
settings, reference_media_ids}` that lives inside a **Studio project**. Instead of
re-typing the same generation prompt + params, save it once and reference it — the
server expands it in place, and anything you pass explicitly **overrides** the
stored value.

## The two reference forms

Put one of these in the `prompt` field of `gate_media_generate` (or in a chat
completion body):

| Form | Resolves by | Needs a project? |
|------|-------------|------------------|
| `prompt:<public_id>` | the stable `prompt_…` id (globally unique per brand) | **No** — use this from an agent/CLI |
| `prompt.<name>` | `(project_id, name)` within a Studio project | **Yes** — pass `project_id` |

```jsonc
// Expand a saved prompt, keep its stored model + params, override the seed:
gate_media_generate({
  "model": "fal/flux-dev",        // still required at the schema level
  "prompt": "prompt:prompt_ab12…", // ← the saved-prompt reference
  "params": { "seed": 7 }          // ← your explicit params WIN over the stored ones
})

// Reference by name within a project:
gate_media_generate({
  "model": "fal/flux-dev",
  "prompt": "prompt.hero-shot",
  "project_id": "e2b1…-uuid"       // required to resolve prompt.<name>
})
```

**Override precedence:** live request values always win. A stored `model` fills in
only if you did not set one; stored `settings` fill in only the params you did not
pass; the stored `system_prompt` becomes the generation text only when your
`prompt` is a bare reference (if you typed real prompt text, yours is kept).
Resolving a prompt bumps its `last_used_at`.

## Managing saved prompts (5 tools)

| Tool | Does |
|------|------|
| `gate_prompt_create` | Save a prompt in a project → returns its `public_id`. 409 if the name exists in that project. |
| `gate_prompt_list` | List a project's prompts, newest-touched first. |
| `gate_prompt_search` | Search this brand's prompts by name/description; omit `query` to list all; pass `project_id` to narrow. |
| `gate_prompt_get` | Fetch one by id (uuid) or `prompt_…` public id. |
| `gate_prompt_delete` | Delete one by id or public id. |

```jsonc
// Create once, reference forever:
gate_prompt_create({
  "project_id": "e2b1…-uuid",
  "name": "hero-shot",
  "system_prompt": "A cinematic wide shot of {subject}, golden hour, 35mm",
  "model": "fal/flux-dev",
  "settings": { "guidance_scale": 3.5, "aspect_ratio": "16:9" }
})
// → { "public_id": "prompt_ab12…", … }  then use prompt:prompt_ab12… anywhere.
```

## Gotchas

- A plain string in `prompt` that starts with `prompt:` or `prompt.` is treated as
  a **reference, not literal text**. To generate with literal text that happens to
  start that way, put it in `params.prompt` instead.
- `prompt.<name>` without a `project_id` cannot resolve → the reference is ignored
  (the generation proceeds with your other fields). Use `prompt:<id>` when you have
  no project context.
- Names are unique **per project**, not globally — the same name can exist in two
  projects. The `public_id` is the stable, project-independent handle.
- Saved prompts are **brand-scoped**: you only see and resolve your own brand's.
