---
name: author-catalog
version: 0.3.1
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
  WRITE surface (PAT scope `gate:catalog:write` or X-Admin-Key) for CATALOG EDITORIAL — the copy
  clients read. It is NOT how you change which model the gateway routes to
  (that's manage-routing / gate_routing_*) and NOT how you send a completion
  (that's the gateway consumer skill). Every write is COALESCE-preserve (only
  the fields you supply change) and stamps the row as curated so the 6h
  discovery sync stops overwriting it.
client: author-catalog
client_version: "0.3.1"
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
gate_catalog_provider_set_meta (provider_name, …) ─▶  provider editorial: description / free_tier_description / docs_url / signup_url
```

> **AUTH:** every `gate_catalog_*` write authorises with a PAT carrying the
> `gate:catalog:write` capability scope (granted at PAT-approval time), OR the
> platform `X-Admin-Key` (`SPIDERIQ_ADMIN_API_KEY`), OR a super_admin session. A
> normal PAT without the scope gets a `403`. Platform-wide — the catalog is one
> shared catalog; there is no per-brand editorial. Never echo the key into logs or chat.

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

<HARD-GATE name="licensing-facts-our-words-provenance">
Everything a client reads must be **facts + OUR words + provenance** — never
third-party prose, never an unattributed link:
- **Descriptions** (`description` / `long_description`) are composed by YOU from
  STRUCTURED FACTS (developer, modality, release, license, context, price, lineage)
  the enrichment layer already gathered. **NEVER paste a vendor's marketing blurb, a
  model card, or a Wikipedia paragraph** — that's copyright / CC-BY-SA share-alike (a
  copyleft trap for our DB). A sentence built from facts is provably not a copy. If
  you have only prose and no facts, write LESS.
- **Third-party links** (`setLink` on a review / vendor benchmark / paper we did not
  write) MUST set `is_authored_by_us=false` + `source` + `attribution` (+ `source_url`
  where the license needs a link-back).
A copied description and an unattributed link are the **same** licensing defect. Only
set `is_authored_by_us=true` for content SpiderIQ authored.
</HARD-GATE>

> **This skill authors COPY, not FACTS.** It writes the *editorial* — description,
> tags, badges, links, visibility, sort. It does **NOT** fill a model's *factual*
> fields: `context_window`, `max_output`, pricing, `capabilities`, `supports_tools`,
> benchmarks (`gate_catalog_benchmarks`), or per-provider performance
> (`gate_catalog_provider_perf`). Those come from the **enrichment** path
> (OpenRouter / LLM-Stats / Wikidata → the discovery sync or a curator agent), NOT
> from here. Authoring a description does **not** make a model "filled" — if
> `context_window` is 0 and there are no benchmarks, the facts still need the
> enrichment pass. Ground your copy in facts the enrichment already wrote; if they
> aren't there yet, the model isn't ready to author.

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

**SCOPED-PAT OR ADMIN-KEY, PLATFORM-WIDE.** Authorise with a PAT carrying
`gate:catalog:write` (an agent's own capability token), the platform `X-Admin-Key`
(`SPIDERIQ_ADMIN_API_KEY`), or a super_admin session. A PAT without the scope gets
`403`. No brand scoping — one shared catalog. Never echo the key.

**VERIFY WITH THE SCRIPT, NOT BY EYE.** After filling/authoring a provider's models,
run [`scripts/verify-catalog-fill.sh <provider>`](scripts/verify-catalog-fill.sh) and
**paste its output verbatim** into your summary — it asserts the invariants above
(is_curated + real description, facts-present-before-authored, no badge monoculture)
as PASS/FAIL/INFO the model can't fudge. "Looks good" is not a verification.

## Decision tree — pick a reference

| The situation… | Read |
|---|---|
| write/adjust a model's description, tags, badges, sort order, or visibility | [references/author-editorial.md](references/author-editorial.md) |
| set an alias's display name / use case, or a media model's editorial | [references/author-editorial.md](references/author-editorial.md) |
| attach or remove a review video / article / study / paper on a model | [references/manage-links.md](references/manage-links.md) |
| understand why authoring stamps is_curated (the sync-clobber guard) | [learnings/](learnings/) |

## Surface (quick map)

All under `/api/v1/admin/gate` on `https://spideriq.ai`, auth = a PAT scoped
`gate:catalog:write` or `X-Admin-Key`. The MCP tools ship in the **mcp-admin** slice
(`@spideriq/mcp-admin`); the CLI is `spideriq gate catalog …`.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| Author a model's editorial copy | `PATCH /models/{id}/meta` | `gate_catalog_model_set_meta` | `spideriq gate catalog models set-meta <id> …` |
| Author a task alias's editorial | `PATCH /routing/aliases/{alias}/meta` | `gate_catalog_alias_set_meta` | `spideriq gate catalog aliases set-meta <alias> …` |
| Author a media model's editorial | `PATCH /media-models/{id}/meta` | `gate_catalog_media_set_meta` | `spideriq gate catalog media set-meta <id> …` |
| Add a reference link | `POST /models/{id}/links` | `gate_catalog_links_set` (action=add) | `spideriq gate catalog links add <id> --kind … --url …` |
| Remove a reference link | `DELETE /models/{id}/links/{link_id}` | `gate_catalog_links_set` (action=remove) | `spideriq gate catalog links rm <id> <link_id>` |
| Author a **provider's** editorial | `PATCH /providers/{name}/metadata` | `gate_catalog_provider_set_meta` | `spideriq gate catalog providers set-meta <name> …` |

> **5 MCP tools, 6 CLI verbs.** The MCP `gate_catalog_links_set` (one tool,
> `action: add|remove`) is split on the CLI into `links add` + `links rm`. They
> hit the same split REST endpoints (`POST /links` · `DELETE /links/{id}`).
>
> **Provider editorial** (`provider_metadata` — the description, free-tier blurb, and
> docs/signup URLs a client sees on a provider) is authored with
> `gate_catalog_provider_set_meta` / `spideriq gate catalog providers set-meta`. Its
> editable set is `description` / `free_tier_description` / `docs_url` / `signup_url` —
> **`logo_url` is NOT editable here** (it's managed by the provider-logo surface). To
> FILL a provider's models' facts first, see the sibling **`enrich-catalog`** skill.

## Methods (native tool calls — from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `setModelMeta` | author a model's description/tags/badges/sort/hidden (COALESCE-preserve) | [references/author-editorial.md](references/author-editorial.md) |
| `setAliasMeta` | upsert a task alias's display copy | [references/author-editorial.md](references/author-editorial.md) |
| `setMediaMeta` | author a media model's editorial | [references/author-editorial.md](references/author-editorial.md) |
| `setLink` | add / remove a reference link (action=add\|remove) | [references/manage-links.md](references/manage-links.md) |
| `setProviderMeta` | author a provider's editorial (description/free-tier/docs/signup) → `gate_catalog_provider_set_meta` | [references/author-provider.md](references/author-provider.md) |

The envelope contract (`guidance:` per method — `use`/`next`/`warn`/
`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in
[client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

- **[references/author-editorial.md](references/author-editorial.md)** — the
  COALESCE-preserve model + WRONG→RIGHT for partial edits, badges/tags as
  list-replaces, the is_curated guard, the **description-licensing rule** (compose
  from facts, never copy prose), the **badge vocabulary** (house tones/labels), how
  to **find a model's integer id**, and the **un-curate / rollback** runbook.
  **Read before your first set-meta.**
- **[references/manage-links.md](references/manage-links.md)** — add/remove
  reference links, the (model, url) idempotency, and the provenance HARD-GATE.
  Steps / Gotchas / Verify.
- **[references/author-provider.md](references/author-provider.md)** — author a
  provider's editorial (`provider_metadata`) via `gate_catalog_provider_set_meta` /
  `spideriq gate catalog providers set-meta`; the editable field set.
- **[scripts/verify-catalog-fill.sh](scripts/verify-catalog-fill.sh)** — a
  deterministic PASS/FAIL/INFO check the model can't fudge. Run it after a fill and
  paste the output verbatim. Reads the admin catalog (X-Admin-Key) and asserts every
  is_curated row has a real description, flags authored-but-factless stubs, and flags
  badge monoculture. **Enforcement lives in the script, not just this prose.**

## See also

- `learnings/` — `coalesce-preserve-and-curated-guard-2026-07-08` (why a partial
  PATCH + the `is_curated` stamp is what keeps authored copy alive across the 6h
  discovery sync — the A.1 G4 guard) and `df1-fill-judgment-calls-2026-07-10` (the
  OpenAI pilot's judgment calls: a delisted model has no spec source, a source that
  returns nothing, sources that disagree — never fabricate, leave a visible gap or
  fall back per-field). Starting points, not ground truth — verify against current code.
- **The FACTS half is a different job → the `enrich-catalog` skill.** Filling a
  model's specs / benchmarks / pricing (the fields this skill does NOT write — see the
  boundary note above) is the **enrichment** path (OpenRouter / LLM-Stats / Wikidata →
  provenance-stamped facts). Its agent surface is the sibling **`enrich-catalog`** skill
  (`gate_catalog_enrich` / `spideriq gate catalog enrich`). Enrich the facts FIRST, then
  author copy here.
- **Sibling skills in this package** (`@spideriq/admin-skills`): `manage-routing`
  (change WHICH model an alias routes to — different surface, same auth),
  `opvs-admin`, `auth`, `integrations`.
- **Not this skill:** changing the model behind an alias is `manage-routing`
  (`gate_routing_*`); sending completions is `@spideriq/gateway-skills`
  (`use-the-gateway`); the client-facing catalog READ is the gateway read skill;
  filling a model's factual specs/benchmarks is the enrichment path (above). This
  skill authors the *copy clients read about a model*, not routing, not facts.
