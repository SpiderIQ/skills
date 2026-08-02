# Prompt references fail loudly — and the first docs said the opposite

## What happened

Saved prompts shipped in two waves. The first wave resolved `prompt.<handle>` by **exact
name only**, while the dashboard printed a **slugified** handle — so the handle the UI
advertised never matched for any name containing a capital or a space. A live walk
measured it three ways and found the resolvable and unresolvable cases returning an
**identical 404 with no code**: indistinguishable failure.

A follow-up fix changed resolution to match slug **or** exact name and gave every failure
mode its own code. A second live walk verified it with nine probes, using
`last_used_at` as a zero-spend oracle and a deliberately invalid `model` so nothing could
bill.

**The reference documentation was written during the first wave and never revisited.** It
still told agents that an unresolvable `prompt.<handle>` is *"ignored — the generation
proceeds with your other fields."* That has not been true since the fix, and it was
describing a bug rather than a contract even before it.

## What to do differently

**Treat a prompt reference as a call that can fail, not a hint that can be dropped.**

| Code | HTTP | Correct response |
|---|---|---|
| `prompt_reference_needs_project` | 400 | resend with `project_id`, or switch to `prompt:<public_id>` |
| `prompt_not_found` | 404 | search for the real name; do not retry the handle |
| `prompt_reference_ambiguous` | 409 | the message names each candidate id — pick one and use `prompt:<id>` |

**Prefer `prompt:<public_id>` from an agent.** It needs no project context and cannot
collide. `prompt.<handle>` exists because humans type names; an agent holding an id has
no reason to use the fuzzier form.

**Do not rely on a bundle's stored `model` for media.** The media endpoint requires
`model`, so the merge never has an empty slot to fill — the stored value is inert there.
It applies on chat, where `model` is optional. Pass the model explicitly when it matters.

## The transferable lesson

A UI-printed handle and a server-side resolver are **two implementations of one contract**
that drift silently — nothing fails at build time, and the symptom is a no-op rather than
an error. When a skill documents a handle format, the format belongs to the resolver, not
to the label the UI happens to render.

The second-order lesson is about the docs: a reference file authored against wave-one
behaviour survived a wave-two fix that inverted its central claim, because nothing ties a
published skill's prose to the code it describes. Declaring the routes in a schema at
least puts them under the drift gate; prose has no such check.
