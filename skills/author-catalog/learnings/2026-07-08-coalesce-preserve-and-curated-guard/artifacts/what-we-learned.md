# COALESCE-preserve + is_curated: how authored catalog copy survives the sync

**Date:** 2026-07-08 · **Context:** GateBoard A.1 (#2323, mig 406) + C.1 (#2328)

## The problem

One `gate_model_catalog` row carries two kinds of data with two different owners:

| Layer | Owner | Examples |
|---|---|---|
| **Facts** | the 6h discovery sync (automated) | context window, pricing, provider, probe status, `display_name` (default) |
| **Editorial** | a human/agent (this skill) | description, tags, badges, sort_order, hidden, alias display copy, links |

If you author editorial into the same columns the sync writes, the **next sync
tick overwrites your edit**. A catalog that loses its curation every 6 hours is
useless.

## The fix (two mechanisms, inherited by every tool in this skill)

1. **Partial, COALESCE-preserve writes.** Each authoring endpoint writes ONLY the
   fields present in the request. An agent can set one badge without reading and
   re-sending the whole row — and can never accidentally blank a field it didn't
   mention. `badges`/`tags` are wholesale replaces of *that one field*. An empty
   edit is a `422` (nothing to author).

2. **The `is_curated` stamp + a sync that respects it.** Authoring a model flips
   `is_curated=TRUE` (+ `curated_by` + `curated_at`). The discovery sync's
   `ON CONFLICT DO UPDATE` set-lists **omit the authored columns entirely** AND
   branch on `is_curated` (`CASE WHEN is_curated THEN <keep> ELSE <sync value>`)
   for `display_name`. So a curated row's copy is never clobbered.

## Proof (C.1 test-live, 2026-07-08)

`PATCH /admin/gate/models/1/meta` set `description` + `tags` → `is_curated=TRUE`.
Then the **actual** discovery-sync `ON CONFLICT` set-list (`model_catalog.py`
Site A) ran against that row with a fresh `display_name`:
`is_curated` / `description` / `tags` **all preserved** and `display_name`
**NOT** overwritten — the `CASE WHEN is_curated` keep-branch fired.

## The lesson for anyone extending the catalog

- **Authoring is sticky by design** — that's the feature, not a bug. Don't build
  an "un-curate via edit" path; returning a row to sync-managed is a data op.
- **Never add an authored column to a discovery-sync `ON CONFLICT` set-list.**
  That silently re-introduces the clobber this design removed.
- **Keep writes partial.** Agents should never have to read-modify-write a whole
  row to change one field — that's how stale reads blank live data.

Starting point, not ground truth — verify against `catalog_meta.py` +
`model_catalog.py` before relying on line numbers.
