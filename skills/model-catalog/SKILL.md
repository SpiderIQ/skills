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
  does <model> cost across providers", "provenance / source for a benchmark".
  This skill teaches the READ surface — choosing a model. It does NOT send
  completions (that's use-the-gateway) and does NOT author catalog copy (that's
  admin-only). Read it before you pin a model.
version: "0.1.0"
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
- **Pin the winner** — pass the chosen `model_id` straight to
  `use-the-gateway`'s `chat` as `model` (D7 direct-model) — you don't have to
  route through a task alias.

## Decision tree

| You want to… | Method | Auth |
|---|---|---|
| Rank models for a task (+ budget) | `leaderboard(task_type=…)` | **public** |
| Compare a set on spec/price/evals | `listCatalog(fields=…)` | brand PAT |
| Inspect one model fully | `getModel(model_id)` | brand PAT |
| Read the eval prior for a model×task | `modelEvals(model_id, task_type=…)` | brand PAT |

## The one rule that trips agents up

<HARD-GATE name="rank-then-filter-by-price">
The leaderboard ranks by **eval score**, NOT price. To answer a budget question
("best coding model under $2/1M"), call `leaderboard(task_type=coding)` and then
**filter the returned rows by the blended price yourself** — do not expect a
`max_price` param. The cheapest live blended price is on every row for exactly
this. (See [references/best-model-under-budget.md](references/best-model-under-budget.md).)
</HARD-GATE>

## Surfaces

- **CLI:** `spideriq gate catalog list|get|leaderboard|evals` (client PAT; `leaderboard` is public).
- **MCP:** `gate_catalog_list`, `gate_catalog_get`, `gate_leaderboard`, `gate_catalog_model_evals` (the `@spideriq/mcp-gate` slice).
- **HTTP:** `GET /api/gate/v1/catalog/{models,models/{id},models/{id}/evals,leaderboard}`.
