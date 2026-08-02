# Referencing a saved prompt — the two forms and the whole error contract

A saved prompt is expanded **server-side**. You put a reference string in the `prompt`
field; the server resolves it, merges the stored bundle underneath your request, and
proceeds. Your explicit values always win.

## The two forms

| Form | Resolves by | `project_id` |
|---|---|---|
| `prompt:<public_id>` | the stable `prompt_…` id, unique within your brand | not needed |
| `prompt.<handle>` | **slug OR exact name**, within one project | **required** |

### How `prompt.<handle>` actually matches

One query matches the stored `name` **exactly** OR its slug:

```
slug = btrim(regexp_replace(lower(btrim(name)), '[^a-z0-9]+', '_', 'g'), '_')
```

So a prompt named `SFTL2 Pin Product Shot` is reachable as **both**
`prompt.sftl2_pin_product_shot` (the slug the dashboard prints) and
`prompt.SFTL2 Pin Product Shot` (the exact name). Exact-name matching is what lets two
prompts whose slugs collide still be addressed individually.

> Earlier builds resolved by exact name only, so the slug handle the UI advertised never
> matched. That is fixed. If you are working from an older note that says
> `prompt.<name>` resolves by `(project_id, name)`, it is describing the pre-fix
> behaviour.

## WRONG / RIGHT

**WRONG — assuming a bad reference is skipped**

```jsonc
// "if the prompt doesn't resolve it'll just generate without it"
generate({ "model": "fal/flux-dev", "prompt": "prompt.hero_shot" })
// → 400 prompt_reference_needs_project. Nothing was generated. Nothing was billed.
```

**RIGHT — supply the project, or use the id form**

```jsonc
generate({ "model": "fal/flux-dev", "prompt": "prompt.hero_shot",
           "project_id": "e2b1…-uuid" })

// or, from an agent with no project context — preferred:
generate({ "model": "fal/flux-dev", "prompt": "prompt:prompt_ab12…" })
```

## The error contract

Every failure is loud and carries a code. None of them silently degrade.

| Code | HTTP | Means | Do |
|---|---|---|---|
| `prompt_reference_needs_project` | 400 | `prompt.<handle>` sent without `project_id` | resend with `project_id`, or switch to `prompt:<public_id>` |
| `prompt_not_found` | 404 | no such prompt in this brand | check with `searchPrompts`; do not retry the same handle |
| `prompt_reference_ambiguous` | 409 | the handle slugifies onto 2+ prompts in that project | the message names each candidate's `prompt:<id>` — pick one and use the id form |

A collision looks like this — two distinct names, one slug:

| name | slug |
|---|---|
| `SFTL2 Pin Product Shot` | `sftl2_pin_product_shot` |
| `SFTL2  Pin-Product Shot` | `sftl2_pin_product_shot` |

The resolver **never picks one arbitrarily**. It errors and names both.

## Override precedence

Live request values win, field by field:

| Stored field | Applies when |
|---|---|
| `system_prompt` | your `prompt` was a **bare reference** — if you typed real text too, yours is kept |
| `settings` | fills only the keys you did **not** pass |
| `reference_media_ids` | fills only if you passed none |
| `model` | fills only if you passed none — **see the media-path caveat below** |

Resolving a prompt bumps its `last_used_at`.

### ⚠ The stored `model` is unreachable on the media path

`generate-media.generate` declares `model` as **required** (`min_length=1`). Omitting it
is a 422 and an empty string is a 422 — so the "fill in only if you did not set one"
branch can never fire there. **On media, the stored model is inert**; the model you pass
is always the model used. The stored `settings`, `system_prompt` and
`reference_media_ids` all apply normally.

On the **chat** path the stored `model` does apply, because `model` is optional there.

This is a known backend limitation, not a documentation shortcut. Plan around it: if a
bundle is meant to pin a model for media, pass that model explicitly at call time.

## Gotchas

- **`query`, not `q`.** `searchPrompts` ignores unknown params silently and returns
  list-all — which reads as a false match. Negative-control with a nonsense query.
- **A literal prompt beginning `prompt:` or `prompt.` is parsed as a reference.** To
  generate that text literally, pass it as `params.prompt`.
- **Names are unique per project, not per brand.** The same name can exist in two
  projects; `public_id` is the stable, project-independent handle.
- **Brand-scoped.** You only see and resolve your own brand's prompts. A super_admin or
  brand-less principal gets **409**, not an empty list.
