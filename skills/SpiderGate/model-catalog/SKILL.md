---
name: model-catalog
description: >
  Read the enriched SpiderGate model catalog to PICK a concrete model for a task
  under a budget — the rich, cited profile behind each model plus a public
  leaderboard and the per-model eval prior.
  Trigger on: "which model is best for <task>", "best model for coding under $X",
  "cheapest model that can do vision / function calling", "compare model
  benchmarks", "model leaderboard", "rank models for planning", "read the evals
  for <model>", "what's the eval score for gpt-4o on coding", "pick a concrete
  model", "enriched model catalog", "per-provider pricing for a model", "how much
  does <model> cost across providers", "provenance / source for a benchmark",
  "best model for coding / vision / reasoning", "which capability categories are
  there", "rank models by category score", "per-category quality score".
  This skill teaches the READ surface — choosing a model. It does NOT send
  completions (that's use-the-gateway) and does NOT author catalog copy or edit
  the category taxonomy (that's admin-only). Read it before you pin a model.
version: "0.2.0"
category: ai-gateway
---

# Model Catalog (pick a model for a task, under a budget)

SpiderGate's catalog turns bare model specs into a **rich, cited profile**: spec +
authored editorial + benchmarks + a **live per-provider price/latency** snapshot +
reference links + an **evals aggregate**, every sourced field carrying provenance.
On top of it sits a **public model×task leaderboard** and a per-model **#7 evals
aggregate** — the shared prior a planner blends against its own experience.

```
    ┌── GET /catalog/leaderboard?task_type=coding   (PUBLIC — no PAT)
    │       models ranked by auto-eval score, each row: headline benchmark
    │       + cheapest live blended $ across providers
    │
your ──Bearer PAT──▶ GET /catalog/models?fields=capabilities,pricing,per_provider,evals
agent               │       enriched rows, narrowed to the sections you need
    │               ├── GET /catalog/models/{id}          full record for one
    │               └── GET /catalog/models/{id}/evals    the #7 prior (per task)
    │
    ▼  pick a model_id  ──▶  pin it via use-the-gateway  chat(model: <model_id>)   (D7)
```

All reads are **LIST-ONLY — not metered, not billable** (same class as `listModels`).

## Approach

- **"Best model for `<task>` under `$X`"** — the headline job. Rank on the
  leaderboard for the task, then filter the returned rows by the blended price.
  → [references/best-model-under-budget.md](references/best-model-under-budget.md).
- **Compare a shortlist in depth** — pull the enriched catalog with `fields=` to
  narrow, or `getModel` one record: spec, capabilities, per-provider pricing,
  benchmarks, evals side by side. → [references/enriched-catalog.md](references/enriched-catalog.md).
- **Trust the eval prior** — read the per-model #7 aggregate (auto rollups +
  human ratings) for a task before you rely on a model for it; a `null` score
  means "no contribution yet", not zero. → [references/evals-as-prior.md](references/evals-as-prior.md).
- **"Best model for a *capability*" (coding, vision, reasoning…)** — a different
  axis from the eval prior: rank by the **benchmark-derived per-category
  percentile**. `listCategories()` to see the 9 categories + how many models each
  scores, then `leaderboard(category=<key>, sort=score)` to rank; read a specific
  model's own scores with `listCatalog(fields=category_scores)` /
  `getModel(fields=category_scores)`. Only ~19% of models are scored — an empty
  `category_scores[]` means "unscored", not "bad".
  → [references/pick-by-category.md](references/pick-by-category.md).
- **Pin the winner** — pass the chosen `model_id` straight to
  `use-the-gateway`'s `chat` as `model` (D7 direct-model) — you don't have to
  route through a task alias.

## Decision tree

| You want to… | Method | Auth |
|---|---|---|
| Rank models for a task (+ budget) | `leaderboard(task_type=…)` | **public** |
| Rank models for a **capability category** | `leaderboard(category=…, sort=score)` | **public** |
| See the capability categories (+ scored counts) | `listCategories()` | brand PAT |
| Compare a set on spec/price/evals/category scores | `listCatalog(fields=…)` | brand PAT |
| Inspect one model fully | `getModel(model_id)` | brand PAT |
| Read the eval prior for a model×task | `modelEvals(model_id, task_type=…)` | brand PAT |

## The rules that trip agents up

<HARD-GATE name="rank-then-filter-by-price">
The leaderboard ranks by **eval score** (or category percentile), NOT price. To
answer a budget question ("best coding model under $2/1M"), rank first and then
**filter the returned rows by the blended price yourself** — do not expect a
`max_price` param. The cheapest live blended price is on every row for exactly
this. (See [references/best-model-under-budget.md](references/best-model-under-budget.md).)
</HARD-GATE>

<HARD-GATE name="task-type-vs-category-are-different-axes">
`leaderboard` has **two ranking axes** — pick the right one:
- **`task_type=…`** ranks by the **#7 EVAL success rate** (needs an eval
  contribution; a model with no eval prior for that task ranks by missing data).
- **`category=…, sort=score`** ranks by the **benchmark-derived within-category
  PERCENTILE** (needs published benchmarks). Use this for "best model for
  *coding / vision / reasoning*" — a capability question.

They are NOT interchangeable. A category `score` is a **percentile (0–100)**, not
a raw benchmark mean; read `rank ÷ total` for "rank/N", and a score's
`components[]` is the WHY. Only ~19% of models are scored — treat an empty
`category_scores[]` as "unscored", never "worst". Call `listCategories()` to get
the valid `category` keys before ranking.
</HARD-GATE>

## Surfaces

- **HTTP (this skill wraps it):** `GET /api/gate/v1/catalog/{models,models/{id},models/{id}/evals,leaderboard,categories}`. Per-category ranking = `GET /catalog/leaderboard?category=<key>&sort=score`; each model's own scores = `category_scores` in the `fields=` child section on `/catalog/models[/{id}]`. The skill methods (`listCategories`, `leaderboard` with `category`) call these directly through the OPVS proxy — no client tool needed.
- **CLI:** `spideriq gate catalog list|get|leaderboard|evals` (client PAT; leaderboard public). ⚠ **The CLI leaderboard is `--task-type` only — the per-category mode + `/catalog/categories` are NOT yet exposed as CLI commands** (HTTP + this skill only, today).
- **MCP:** `gate_catalog_list`, `gate_catalog_get`, `gate_leaderboard` (**`task_type` only**), `gate_catalog_model_evals` (the `@spideriq/mcp-gate` slice). ⚠ **There is no client MCP tool for the category read or the per-category leaderboard yet** — the category surface reaches agents via THIS skill (HTTP proxy). A follow-up may add `gate_catalog_categories` + a `category` arg on `gate_leaderboard`.
- **Admin (NOT this skill):** editing the categories / scoring recipe is the `@spideriq/admin-skills` **curate-categories** skill (super_admin, X-Admin-Key).
