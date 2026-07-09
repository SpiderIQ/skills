---
name: author-catalog
version: 0.1.0
description: >
  Author the SpiderGate model-catalog editorial — the human-written copy the
  client-facing catalog and model leaderboard show: a model's description /
  tags / badges / sort order / visibility, a task alias's display name + use
  case, a media model's editorial, and per-model reference links (reviews,
  videos, papers, studies). Trigger on: "write a description for a gateway
  model", "add a badge to spideriq/coding", "tag this model as PII-safe", "hide
  a model from the catalog", "set the display name for an alias", "attach a
  review link / a paper to a model", "curate the model catalog", "reorder the
  models on the leaderboard", "author the catalog copy". This is the ADMIN
  WRITE surface (super_admin, X-Admin-Key) for CATALOG EDITORIAL — the copy
  clients read. It is NOT how you change which model the gateway routes to
  (that's manage-routing / gate_routing_*) and NOT how you send a completion
  (that's the gateway consumer skill). Every write is COALESCE-preserve (only
  the fields you supply change) and stamps the row as curated so the 6h
  discovery sync stops overwriting it.
client: author-catalog
client_version: "0.1.0"
category: admin
triggers:
  - author the model catalog
  - write a model description
  - add a badge to a model
  - tag a gateway model
  - hide a model from the catalog
  - set an alias display name
  - attach a reference link to a model
  - reorder the model leaderboard
requires_auth: true
requires_brand: false
---

# Author the SpiderGate Catalog (editorial copy + badges + links)

SpiderGate's model catalog has two layers: **facts** the 6h discovery sync
refreshes automatically (context window, pricing, provider, probe status) and
**editorial** a human authors — the description, tags, badges, sort order,
visibility, alias display copy, and reference links that the client-facing
catalog + model leaderboard render. This skill is the privileged WRITE surface
for that editorial. The read surface (what clients see) is a separate skill.

```
gate_catalog_model_set_meta (model_id, …)  ─▶  description / long_desc / tags / badges / sort_order / hidden  (stamps is_curated)
gate_catalog_alias_set_meta (alias, …)      ─▶  display_name / description / use_case / badges / sort_order / hidden  (upsert)
gate_catalog_media_set_meta (media_id, …)   ─▶  media-model editorial (display_name real; rest → metadata.editorial)
gate_catalog_links_set (action, model_id, …) ─▶  add / remove a reference link (youtube | article | study | paper)
```

> **AUTH:** every `gate_catalog_*` call carries the platform admin key
> (`X-Admin-Key`, from `SPIDERIQ_ADMIN_API_KEY`) — **not** a client PAT. These
> are **super_admin-only** and apply **platform-wide** (the catalog is one shared
> catalog; there is no per-brand editorial). Never echo the key into logs or chat.

## The two mental models that prevent every mistake

1. **Every write is COALESCE-preserve — partial by design.** You send only the
   fields you want to change; everything you omit is left exactly as it was. So
   to add one badge you send `badges` alone — you do NOT re-send the description.
   An **empty** edit (no fields) is a `422` ("No editorial fields supplied.").
   `badges` and `tags` are **wholesale replaces** of that one field (send the
   full list you want), not merges.

2. **Facts vs editorial — you author editorial, the sync owns facts.** The moment
   you author a model's copy, the row is stamped `is_curated=TRUE` and the 6h
   discovery sync stops overwriting its `display_name`. That is the guard that
   keeps your copy from being clobbered by the next sync tick. You never fight the
   sync; authoring flips the row to human-owned. (See `learnings/`.)

## Approach

- **Author model / alias / media copy** — set any subset of description, tags,
  badges, sort_order, hidden. Partial, COALESCE-preserve, wholesale-per-field for
  list fields. → [references/author-editorial.md](references/author-editorial.md)
- **Attach provenance-carrying links** — a reference link (review video, article,
  study, paper) is idempotent per (model, url) and carries licensing provenance
  (`source` / `attribution` / `is_authored_by_us`). Fill provenance for anything
  not authored by us. → [references/manage-links.md](references/manage-links.md)

<HARD-GATE name="provenance-on-third-party-links">
When you `gate_catalog_links_set` (action=add) a link to content **we did not
write** (a third-party review, a vendor benchmark, an academic paper), you MUST
set `is_authored_by_us=false` and fill `source` + `attribution` (and
`source_url` where the license requires a link-back). The catalog renders that
attribution; shipping a third-party link with no provenance is a licensing
defect. Only set `is_authored_by_us=true` for content SpiderIQ authored.
</HARD-GATE>

## Rules (Non-Negotiable)

**PARTIAL MEANS PARTIAL.** Send only the fields you intend to change — omitted
fields are preserved. To edit one field, send that one field. Do NOT re-send the
whole row; that risks blanking a field you passed as empty. `badges`/`tags` are
**replace-the-list**, so send the complete list you want for that field.

**AUTHORING IS STICKY (is_curated).** `gate_catalog_model_set_meta` flips the row
to `is_curated=TRUE` and the discovery sync stops managing its `display_name`.
That is intended — it is how your copy survives the next sync. Don't try to
"un-curate" by editing; if a model must return to sync-managed, that's a data
operation, not an editorial one.

**LINKS ARE IDEMPOTENT PER (MODEL, URL).** Re-adding the same URL updates that
link row rather than duplicating. Removing is by `link_id` and scoped to the
model (a `link_id` can only be removed through the model it belongs to).

**PROVENANCE ON THIRD-PARTY CONTENT.** See the HARD-GATE.

**super_admin-ONLY, PLATFORM-WIDE.** `X-Admin-Key` (`SPIDERIQ_ADMIN_API_KEY`),
never a client PAT, no brand scoping — one shared catalog. Never echo the key.

## Decision tree — pick a reference

| The situation… | Read |
|---|---|
| write/adjust a model's description, tags, badges, sort order, or visibility | [references/author-editorial.md](references/author-editorial.md) |
| set an alias's display name / use case, or a media model's editorial | [references/author-editorial.md](references/author-editorial.md) |
| attach or remove a review video / article / study / paper on a model | [references/manage-links.md](references/manage-links.md) |
| understand why authoring stamps is_curated (the sync-clobber guard) | [learnings/](learnings/) |

## Surface (quick map)

All under `/api/v1/admin/gate` on `https://spideriq.ai`, `X-Admin-Key` auth,
super_admin-only. The MCP tools ship in the **mcp-admin** slice
(`@spideriq/mcp-admin`); the CLI is `spideriq gate catalog …`.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| Author a model's editorial copy | `PATCH /models/{id}/meta` | `gate_catalog_model_set_meta` | `spideriq gate catalog models set-meta <id> …` |
| Author a task alias's editorial | `PATCH /routing/aliases/{alias}/meta` | `gate_catalog_alias_set_meta` | `spideriq gate catalog aliases set-meta <alias> …` |
| Author a media model's editorial | `PATCH /media-models/{id}/meta` | `gate_catalog_media_set_meta` | `spideriq gate catalog media set-meta <id> …` |
| Add a reference link | `POST /models/{id}/links` | `gate_catalog_links_set` (action=add) | `spideriq gate catalog links add <id> --kind … --url …` |
| Remove a reference link | `DELETE /models/{id}/links/{link_id}` | `gate_catalog_links_set` (action=remove) | `spideriq gate catalog links rm <id> <link_id>` |

> **4 MCP tools, 5 CLI verbs.** The MCP `gate_catalog_links_set` (one tool,
> `action: add|remove`) is split on the CLI into `links add` + `links rm`. They
> hit the same split REST endpoints (`POST /links` · `DELETE /links/{id}`).

## Methods (native tool calls — from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `setModelMeta` | author a model's description/tags/badges/sort/hidden (COALESCE-preserve) | [references/author-editorial.md](references/author-editorial.md) |
| `setAliasMeta` | upsert a task alias's display copy | [references/author-editorial.md](references/author-editorial.md) |
| `setMediaMeta` | author a media model's editorial | [references/author-editorial.md](references/author-editorial.md) |
| `setLink` | add / remove a reference link (action=add\|remove) | [references/manage-links.md](references/manage-links.md) |

The envelope contract (`guidance:` per method — `use`/`next`/`warn`/
`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in
[client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

- **[references/author-editorial.md](references/author-editorial.md)** — the
  COALESCE-preserve model + WRONG→RIGHT for partial edits, badges/tags as
  list-replaces, and the is_curated guard. **Read before your first set-meta.**
- **[references/manage-links.md](references/manage-links.md)** — add/remove
  reference links, the (model, url) idempotency, and the provenance HARD-GATE.
  Steps / Gotchas / Verify.

## See also

- `learnings/` — `coalesce-preserve-and-curated-guard-2026-07-08` (why a partial
  PATCH + the `is_curated` stamp is what keeps authored copy alive across the 6h
  discovery sync — the A.1 G4 guard). Starting points, not ground truth — verify
  against current code.
- **Sibling skills in this package** (`@spideriq/admin-skills`): `manage-routing`
  (change WHICH model an alias routes to — different surface, same auth),
  `opvs-admin`, `auth`, `integrations`.
- **Not this skill:** changing the model behind an alias is `manage-routing`
  (`gate_routing_*`); sending completions is `@spideriq/gateway-skills`
  (`use-the-gateway`); the client-facing catalog READ is the gateway read skill.
  This skill authors the *copy clients read about a model*, not routing.
