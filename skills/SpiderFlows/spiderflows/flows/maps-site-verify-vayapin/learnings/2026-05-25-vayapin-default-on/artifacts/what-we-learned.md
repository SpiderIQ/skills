# VayaPin publishes permanent pins, and its default is path-dependent

**Starting point, not ground truth — verify against current code.**

## The irreversible side effect

The `vayapin` stage publishes a **real, public page on `cs.vayapin.com`** for every
business with a website. There is no API to unpublish, and **deleting the campaign
does not remove the pages** — `DELETE /campaigns/{id}` only clears your campaign/
location records. So running VayaPin is effectively a one-way decision.

## The default is genuinely confusing — here's the truth

Three different code points disagree on first read:

- `WorkflowVayaPinConfig.enabled` — schema default **`false`** (opt-in, set by
  flowstest-1.2-r2 precisely so a bare config wouldn't silently publish).
- `LeadSearchRequest.workflow` — its `default_factory` explicitly constructs
  `WorkflowVayaPinConfig(enabled=True)`. So **`/lead-search` with no `workflow`
  block publishes.**
- `select_workflow_flow()` — reads `vayapin.get("enabled", True)`, i.e. treats a
  *missing* `enabled` key as `true` when picking the WindMill flow.

Net effect:
- `/lead-search`, omitted `workflow` → **publishes**.
- campaign submit → follows the `vayapin.enabled` you send.
- a hand-built bare `WorkflowConfig()` → schema gives `false`.

## What to do

**Never rely on the default. Always send `workflow.vayapin.enabled` as the value
you intend.** If the user asked for a *lead list / emails / prospects* (data), send
`false`. Only send `true` when they explicitly asked for published map profiles or
local-SEO pages. When unsure, ask — you cannot undo a published pin.

`vayapin` also requires `spidersite.enabled=true` (it needs site data); otherwise 422.
