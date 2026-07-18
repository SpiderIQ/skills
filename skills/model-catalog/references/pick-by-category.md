# Pick a model by capability category (per-category quality scores)

The catalog carries a **model-capability category taxonomy** — 9 DB-backed
categories, each with a benchmark-derived **within-category percentile** score per
model. This is a *different axis* from the `task_type` eval leaderboard: use it to
answer "best model for **coding / vision / reasoning**" — a capability question —
where the ranking comes from published benchmarks, not from an eval contribution.

The 9 categories: **Coding · Design/Frontend · Reasoning · Math · Vision ·
Research · Tool-use · Chat · Translation**.

## Steps

1. **Discover the categories** — `listCategories()` → each category's `key`,
   `label`, `emoji`, and `scored_model_count` (the **N** behind "rank/N"). This is
   how you get the valid `category` keys and how many models each scores.

2. **Rank for a capability** — `leaderboard(category=<key>, sort=score)`. Returns
   models ordered by their within-category **percentile**, each row carrying
   `score` (0–100 percentile), `rank`, and the response `total` (so "rank/N" =
   `rank ÷ total`) plus the contributing `components`. `category` takes precedence
   over `task_type`; you must pass `sort=score`.

3. **Read one model's own scores** — `listCatalog(fields=category_scores)` for a
   set, or `getModel(model_id)` with `category_scores` in the projection, for one.
   Each element: `{category_key, label, emoji, score, rank, n_signals,
   confidence, components, computed_at}`, best-first. `components[]` is the WHY —
   the contributing benchmarks (each normalized, `self_reported` flagged).

4. **Pin the winner** — pass its `model_id` to `use-the-gateway`'s `chat` as
   `model` (D7 direct-model). Then optionally filter by the blended price for a
   budget (the leaderboard ranks by score, not price).

## Gotchas

- **`score` is a PERCENTILE, not a raw benchmark mean** (§13-C: raw means aren't
  calibrated across benchmarks). Higher = better *relative to the models scored in
  that category*. Do not read it as an absolute quality number.
- **Coverage is ~19%** — only ≈219 of 1126 catalog models carry any category
  score (a model needs published benchmarks). An empty `category_scores[]` means
  **unscored**, NOT worst — render "no score" gracefully and never rank it last.
- **`model_ref` is a soft-string, not an FK** (§13-E): a score's model reference
  can match more than one catalog row; the read layer already resolves each to one
  non-hidden model, so you never see a fan-out — just be aware a score is keyed on
  the served model, not a hard catalog id.
- **`confidence`** (`high`/`med`/`low`/`none`) reflects how many signals fed the
  score — a `low`/`none` score is thin evidence, weight it accordingly.
- **Two leaderboard axes** — `category=` (benchmark percentile) vs `task_type=`
  (eval success rate). Don't mix them; `category` wins if both are passed.

## Surfaces

- **This skill / HTTP:** `GET /catalog/categories`,
  `GET /catalog/leaderboard?category=<key>&sort=score`, `category_scores` via
  `fields=` on `/catalog/models[/{id}]`.
- **Dashboard:** the same data powers the category chips + per-category score bar /
  rank / "why" tooltip on `/dashboard/gate/models`.
- **Not yet on client MCP/CLI** — the category read reaches agents through this
  skill (HTTP proxy); the `gate_leaderboard` MCP tool + `gate catalog leaderboard`
  CLI are `task_type`-only today.
- **Editing** the categories or the scoring recipe is admin-only — the
  `@spideriq/admin-skills` **curate-categories** skill (super_admin, X-Admin-Key).
