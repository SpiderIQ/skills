# The Studio workspace — projects, prompts, generations

**SpiderGate Studio** is the shared creative workspace: every image/video/audio model
behind one gateway, with humans working in the dashboard composer and agents working
through this API against the same objects.

## What a project holds

A **Studio project** is the container. Everything below is scoped to one:

| Thing | What it is | Reachable here? |
|---|---|---|
| **saved prompts** | named `{system_prompt, model, settings, reference_media_ids}` bundles | ✅ all 6 methods |
| **generated assets** | the generations gallery — past outputs, click-to-reuse in the UI | ⚠️ see below |
| **sessions** | the composer's conversation history | ❌ dashboard-side |

A prompt cannot exist outside a project — `project_id` is required at creation. Start
with `listProjects`; if the brand has none, `createProject` first.

## Steps — save a prompt an agent can call by name

1. `listProjects` → take a `project_id` (or `createProject`).
2. `createPrompt` with `project_id`, a `name`, and whatever of
   `system_prompt` / `model` / `settings` / `reference_media_ids` applies.
3. **Keep the returned `public_id`** (`prompt_…`). That is the reference form that works
   from anywhere, with no project context and no collision risk.
4. Reference it: `use-the-gateway.chat` or `generate-media.generate` with
   `{"prompt": "prompt:prompt_ab12…"}`.

Verify with `searchPrompts` before relying on it — and negative-control the search, since
an unknown param returns list-all rather than erroring.

## The generations gallery

The dashboard's media canvas shows a per-project grid of past generations, newest first,
with **Reuse** (the exact prompt/model/settings back into the composer) and **Use as next
reference**. It is backed by rows linking assets to the project.

**Two things an agent should know:**

- **Generating through the API does not populate the gallery.** The attach is a
  dashboard-side step. A generation made with `generate-media.generate` produces the
  media, but no gallery tile.
- **The Studio defaults to "Scratch (no project)".** In that mode nothing is saved to a
  project at all, and the failure is soft — a whole session can generate and store
  nothing, with no warning.

So: treat the gallery as a **dashboard view of dashboard-made work**, not as a durable
index of everything an agent generated. If an agent needs its outputs catalogued, it
should keep the returned media URLs itself.

## Folders

There is **no folder API**. The dashboard groups work by project; projects are the only
level of organisation exposed here. If you need finer grouping today, use naming
conventions inside a project — a `name` is up to 255 chars and searchable by substring.

## Gotchas

- **Deleting a project orphans its generated media.** The objects stay in storage with
  no catalog row and no cleanup path. Delete deliberately.
- **Projects are brand-scoped.** A brand-less or super_admin principal gets **409**.
- **`studio_projects` is not the same table as content `projects`.** They are separate
  subsystems that happen to share a word; an id from one will not resolve in the other.
