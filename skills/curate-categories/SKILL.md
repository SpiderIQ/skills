---
name: curate-categories
version: 0.1.0
description: >
  Curate SpiderGate's model-capability CATEGORY TAXONOMY — the DB-backed
  categories (Coding, Design/Frontend, Reasoning, Math, Vision, Research,
  Tool-use, Chat, Translation) and the benchmark→category SIGNALS that define how
  each per-category quality score is computed. Trigger on: "add a model
  category", "retune the coding score", "add a benchmark to a category", "remap a
  category signal", "which benchmarks define the design score", "deactivate a
  category", "edit the category scoring recipe", "add SWE-Bench to coding". This
  is the ADMIN taxonomy surface (super_admin, X-Admin-Key) — it changes the
  categories + scores EVERY tenant sees on the models page. It is NOT how you
  author a model's editorial copy (that's author-catalog / gate_catalog_*) and
  NOT how you change which model an alias routes to (that's manage-routing).
  Every edit recomputes the per-category percentile scores; the taxonomy is
  editable at runtime with no deploy.
client: curate-categories
client_version: "0.1.0"
category: admin
triggers:
  - curate the gate category taxonomy
  - add a model category
  - retune a category score
  - add a benchmark to a category
  - remap a category signal
  - deactivate a category
  - which benchmarks define a category score
  - edit the category scoring recipe
requires_auth: true
requires_brand: false
---

# Curate the SpiderGate Category Taxonomy (categories + scoring signals)

SpiderGate's models page shows use-case **category** chips (Coding, Design,
Reasoning, …) and, for each model, a **per-category quality score** (a
within-category **percentile** 0–100 + rank). Both are **DB-backed and editable
at runtime, no deploy**:

```
gate_categories        ─▶  the LIST  (key, label, emoji, sort_order, is_scored, is_active)
gate_category_signals  ─▶  the RECIPE (category_key, signal_type, signal_value, weight)
                            e.g. coding = benchmark:"SWE-Bench Verified"×1.0 + benchmark:"HumanEval"×1.0
gate_model_category_scores ─▶ the ANSWER (materialised percentile + rank per model×category)
```

You edit the LIST + the RECIPE; the scorer recomputes the ANSWER. This skill is
the privileged surface that lists the taxonomy, adds/renames/(de)activates
categories, and adds/retunes/removes the benchmark→category signals.

```
gate_category_list                          ─▶  every category (incl. inactive) + its full signal recipe + scored_model_count
gate_category_upsert (key, label, …)        ─▶  add / rename / re-sort / (de)activate a category  + recompute
gate_category_signal_set (key, type, value, weight)   ─▶  add or retune ONE signal  + recompute
gate_category_signal_remove (key, type, value)        ─▶  drop ONE signal  + recompute
```

> **AUTH:** every `gate_category_*` call carries the platform admin key
> (`X-Admin-Key`, from `SPIDERIQ_ADMIN_API_KEY`) — **not** a client PAT. There is
> deliberately **no PAT branch** on these endpoints (that IS the owner-lock).
> super_admin-only, platform-wide: an edit changes the categories + scores every
> tenant sees. Never echo the key into logs or chat.

## The one mental model that prevents every mistake

**The displayed score is a within-category PERCENTILE + rank, NOT `raw_mean×100`.**
Raw benchmark means aren't calibrated across benchmarks (a design mean of 0.33
and a math mean of 0.73 are not comparable), so the score a client sees is where
the model sits **within its category** (percent_rank), plus rank/N. That's why:

- **A percentile can't be recomputed incrementally** — `percent_rank()` needs the
  whole per-category partition — so **every mutating call re-runs the FULL scorer**
  (~1.1k rows, sub-second) and returns its summary. Pass `recompute=false` only
  when batching several edits, then recompute on the LAST one.
- **Retuning a weight or adding a signal reshuffles the percentile ordering** for
  that category. Read `gate_category_list` first to see the current recipe.

## Approach

- **List first** — never retune blind. `gate_category_list` returns every category
  (including `is_active=false`, which the client-facing read hides) with its full
  signal recipe + live `scored_model_count`. → [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md)
- **Add / edit a category** — `gate_category_upsert` is idempotent on `key`
  (a lowercase slug). It ADDs, renames/redescribes/re-emojis, re-sorts, or
  activates/deactivates. Omitted fields are preserved. A brand-new category has
  NO scores until you add signals. → [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md)
- **Define / retune the recipe** — `gate_category_signal_set` adds or retunes ONE
  benchmark→category signal (the category must exist first). `signal_value` must
  match the benchmark string EXACTLY. `gate_category_signal_remove` drops one.
  → [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md)

<HARD-GATE name="list-before-you-retune">
Before any `gate_category_signal_set` / `_remove` or an `is_scored`/`is_active`
flip, call **`gate_category_list`** and read the target category's current
recipe + `scored_model_count`. A retune reshuffles the whole category's
percentile ordering — editing against a guessed recipe (wrong benchmark string,
duplicate signal, a weight on a signal that isn't there) silently changes what
every tenant sees. The list is the ground truth; the client-facing
`/catalog/categories` read is NOT (it hides inactive categories and omits the
recipe).
</HARD-GATE>

## Rules (Non-Negotiable)

**LIST BEFORE YOU RETUNE.** See the HARD-GATE. `gate_category_list` is the only
read that shows inactive categories + the full signal recipe.

**THE SCORE IS A PERCENTILE, NOT `raw_mean×100`.** Never surface or reason about
`raw_mean` as the client-visible score — it's stored for audit only (§13-C). The
displayed value is the within-category percentile + rank/N.

**EDIT THE DATA, NOT THE CODE.** The taxonomy + recipe are DB rows — a category
or a signal is DATA. There is no deploy for a taxonomy change; the write
recomputes scores in-request (unless `recompute=false`).

**DEACTIVATE ≠ DELETE.** `is_active=false` retires a category (its scores are
swept on the next recompute) but keeps the row — re-activate to bring it back.
To stop scoring but keep the chip, set `is_scored=false`.

**SIGNALS ARE EXACT-MATCH.** `gate_category_signal_set` needs the category to
exist (404 otherwise) and `signal_value` to match the benchmark name EXACTLY, or
it contributes nothing to the score. `signal_type` ∈ benchmark | eval_task_type
| tag | alias | capability.

**PLATFORM-WIDE + super_admin-ONLY.** No brand scoping. The key is `X-Admin-Key`
(`SPIDERIQ_ADMIN_API_KEY`), never a client PAT — never echo it into logs or chat.

## Decision tree — pick a reference

| The situation… | Read |
|---|---|
| add a new capability category and define what scores it | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |
| retune a category's score (add/remove/reweight its benchmark signals) | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |
| deactivate / re-activate a category, or stop scoring it | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |
| understand why the score is a percentile (and what recompute does) | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |

## Surface (quick map)

All under `/api/v1/admin/gate/categories` on `https://spideriq.ai`, `X-Admin-Key`
auth, super_admin-only. The MCP tools ship in the **mcp-admin** slice
(`@spideriq/mcp-admin`); the CLI is `spideriq gate categories …`.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| List categories + recipe + scored count | `GET /categories` | `gate_category_list` | `spideriq gate categories list` |
| Add / edit a category | `POST /categories` | `gate_category_upsert` | `spideriq gate categories upsert <key> <label>` |
| Add / retune a signal | `POST /categories/{key}/signals` | `gate_category_signal_set` | `spideriq gate categories signal set <key> --type … --value …` |
| Remove a signal | `DELETE /categories/{key}/signals` | `gate_category_signal_remove` | `spideriq gate categories signal remove <key> --type … --value …` |

## Methods (native tool calls — from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `listCategories` | every category (incl. inactive) + signal recipe + scored_model_count | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |
| `upsertCategory` | add / rename / re-sort / (de)activate a category + recompute | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |
| `setCategorySignal` | add or retune one benchmark→category signal + recompute | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |
| `removeCategorySignal` | drop one signal (idempotent) + recompute | [references/curate-the-taxonomy.md](references/curate-the-taxonomy.md) |

The envelope contract (`guidance:` per method — `use`/`next`/`warn`/
`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in
[client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

- **[references/curate-the-taxonomy.md](references/curate-the-taxonomy.md)** — the
  safe curation flow: list → upsert category → set/remove signals → confirm the
  recompute, with WRONG→RIGHT and the recompute/percentile gotchas. **Read before
  your first edit.**

## See also

- **Sibling skills in this package** (`@spideriq/admin-skills`): `author-catalog`
  (author a MODEL's editorial copy — a PAT surface, NOT the taxonomy),
  `manage-routing` (change which model an alias routes to), `enrich-catalog`,
  `manage-vault`.
- **Not this skill:** the client-facing READ of categories / leaderboard / scores
  is `@spideriq/gateway-skills` (`use-the-gateway`); authoring a model's
  description/tags/badges is `author-catalog`. This skill changes the *category
  taxonomy + scoring recipe*, for everyone.
- Design spec: `docs/services/SpiderGate/GATE-CATEGORY-TAXONOMY-PLAN-2026-07-18.md`
  (§7 curator surface, §13-C percentile-not-raw-mean). Starting point, not ground
  truth — verify against current code.
