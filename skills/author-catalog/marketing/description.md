## author-catalog

SpiderGate's model-catalog **editorial** write surface. 4 tools to author the
copy clients read on the catalog + model leaderboard: a model's description /
tags / badges / sort order / visibility, a task alias's display name + use case,
a media model's editorial, and per-model reference links (reviews, videos,
papers, studies).

super_admin-only (`X-Admin-Key`), platform-wide: the catalog is one shared
catalog — there is no per-brand editorial.

### What this skill does

- **Author model copy** — `setModelMeta` writes description / long_description /
  tags / badges / sort_order / hidden. Stamps `is_curated` so the discovery sync
  stops overwriting the row.
- **Author alias copy** — `setAliasMeta` upserts a task alias's display name,
  use case, and badges (what a client sees for `spideriq/coding`, `opvs/creative`).
- **Author media copy** — `setMediaMeta` writes editorial for image/video models.
- **Manage links** — `setLink` adds/removes reference links (review videos,
  articles, studies, papers), idempotent per (model, url), carrying licensing
  provenance.

### The mental model that prevents every mistake

**Every write is COALESCE-preserve — partial by design.** Send only the fields
you want to change; everything omitted is left exactly as it was. To add one
badge, send `badges` alone — never re-send the whole row. `badges`/`tags` are
wholesale replaces of *that one field*. An empty edit is a `422`.

**Facts vs editorial.** The 6h discovery sync owns facts (context window,
pricing, probe status); you own editorial. Authoring a model flips it to
`is_curated` and the sync stops overwriting it — that's how your copy survives.

### Guardrails

- **Provenance on third-party content** — a link to content we didn't write MUST
  set `is_authored_by_us=false` + `source` + `attribution`. The catalog renders it.
- **Partial means partial** — omitted fields are preserved, not blanked; send
  only what changes.
- **Not routing** — this authors the *copy about a model*, not which model an
  alias serves (that's `manage-routing`).

### Typical workflows

- **A new model needs a card** — `setModelMeta` (description + tags + a badge) →
  `setLink` (attach the vendor's announcement + an independent review).
- **Re-badge for a launch** — `setModelMeta` with the full `badges` list you want.
- **Curate the leaderboard order** — `setModelMeta --sort-order` per model.
- **Clean up a dead link** — `setLink` action=remove by `link_id`.
