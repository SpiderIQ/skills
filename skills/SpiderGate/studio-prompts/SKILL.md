---
name: studio-prompts
description: >
  Save a prompt bundle once inside a SpiderGate Studio project — system prompt,
  model, settings and reference media under one name — then reference it by name
  or stable id from any completion or media generation.
  Trigger on: "save this prompt", "save my prompt", "reuse that prompt", "prompt
  template", "my saved prompts", "list my prompts", "find the prompt called …",
  "rename/update a saved prompt", "delete a saved prompt", "what studio projects
  do I have", "create a studio project", "call a prompt by name", "prompt.<name>",
  "prompt:<id>". This skill MANAGES the bundles. It does NOT send a completion
  (that's use-the-gateway) or a generation (that's generate-media) — it gives you
  the reference those two expand.
version: "0.1.0"
category: ai-gateway
---

# SpiderGate Studio — saved prompts

**The agent-native creative studio — every image/video/audio model, one shared
workspace, humans and agents side by side.**

A **saved prompt** is a named bundle of `{system_prompt, model, settings,
reference_media_ids}` that lives inside a **Studio project**. The same object has two
front doors: a human loads it from the composer's gallery, and an agent references it
by handle. The server expands it in place, and **your request values always win**.

## Decision tree → references

| The user wants to… | Read |
|---|---|
| Reference a saved prompt from a completion or generation, or handle a reference error | `references/prompt-references.md` |
| Understand projects, the generations gallery, and how assets accumulate | `references/studio-workspace.md` |
| Know what already works vs what is documented-but-broken | `learnings/` |

## The two reference forms

Put one in the `prompt` field of `use-the-gateway.chat` or `generate-media.generate`:

| Form | Resolves by | Needs `project_id`? |
|---|---|---|
| `prompt:<public_id>` | the stable `prompt_…` id, unique per brand | **No** — prefer this from an agent |
| `prompt.<handle>` | slug **or** exact name, within one project | **Yes** — 400 without it |

**Prefer `prompt:<public_id>`.** It needs no project context and cannot collide.
`prompt.<handle>` is the form the dashboard advertises to humans; it is real and
supported, but it can return 409 when two names slugify to the same handle.

## Three things that will bite you

1. **A missing `project_id` is a 400, not a silent skip.** Every failed reference is
   loud and coded — `prompt_not_found` (404), `prompt_reference_needs_project` (400),
   `prompt_reference_ambiguous` (409). Read the code and act on it; never retry blindly.
2. **A stored `model` does nothing on the media path.** `generate-media.generate`
   requires `model`, so the merge never sees an empty slot to fill. The stored model
   works on the chat path. Everything else in the bundle applies on both.
3. **A literal prompt starting `prompt:` or `prompt.` is read as a reference.** If you
   genuinely want that text generated, pass it via `params.prompt` instead.

## Order of operations

```
listProjects → (createProject if none) → createPrompt → keep the public_id
                                              ↓
              use-the-gateway.chat / generate-media.generate  with  prompt:<public_id>
```

## See also

- `generate-media` — sends the generation this skill's bundles feed.
- `use-the-gateway` — sends the chat completion; the stored `model` applies there.
- `learnings/` — institutional memory. Verify against current code before trusting.
