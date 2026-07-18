# Curate the category taxonomy (list → upsert → signals → recompute)

The safe flow for editing SpiderGate's model-capability categories + the
benchmark→category signals that score them. Everything here is **X-Admin-Key,
super_admin-only, platform-wide** — an edit changes what every tenant sees. Every
mutating call recomputes `gate_model_category_scores` (a full sweep — the score
is a within-category percentile, which needs the whole partition) and returns the
scorer summary.

## The three tables (what you edit vs what the scorer writes)

```
gate_categories        ── the LIST    ← upsertCategory writes this
gate_category_signals  ── the RECIPE  ← setCategorySignal / removeCategorySignal write this
gate_model_category_scores ── the ANSWER ← the SCORER writes this (you never write it directly)
```

You edit the LIST + the RECIPE. The scorer reads the benchmarks a model has,
buckets them by the category signals, averages per bucket (`raw_mean`, audit-only),
ranks + percentiles within the category, and materialises the ANSWER. The
displayed score = the **percentile** (§13-C), NOT `raw_mean×100`.

## Steps

```
# 1. ALWAYS list first — see the current taxonomy + each category's recipe.
gate_category_list
#    → items[]: { key, label, emoji, is_active, is_scored, sort_order,
#                 signals:[{signal_type, signal_value, weight}], scored_model_count }
#    (includes is_active=false categories the client read hides)

# 2. Add or edit a category (idempotent on key — a lowercase slug).
gate_category_upsert { key:"coding", label:"Coding", emoji:"💻", sort_order:10 }
#    → { category:{…}, created:true|false, recompute:{scored_rows, upserted, …} }

# 3. Define / retune the recipe — one signal at a time. The category must EXIST.
gate_category_signal_set { key:"coding", signal_type:"benchmark",
                           signal_value:"SWE-Bench Verified", weight:1.0 }
gate_category_signal_set { key:"coding", signal_type:"benchmark",
                           signal_value:"HumanEval", weight:1.0 }
#    → { signal:{id, …}, created:true|false, recompute:{…} }

# 4. Drop a signal that shouldn't count (idempotent).
gate_category_signal_remove { key:"coding", signal_type:"benchmark",
                              signal_value:"HumanEval" }
#    → { removed:true|false, recompute:{…}|null }

# 5. Confirm — list again and read scored_model_count + the recipe.
gate_category_list
```

### Batching many edits — recompute on the LAST one only

The recompute is a full sweep. When you're adding 5 signals to one category, pass
`recompute:false` on the first 4 and let the last one (or a final
`gate_category_upsert`) recompute:

```
gate_category_signal_set { key:"coding", …, signal_value:"SWE-Bench Pro", recompute:false }
gate_category_signal_set { key:"coding", …, signal_value:"LiveCodeBench",  recompute:false }
gate_category_signal_set { key:"coding", …, signal_value:"Terminal-Bench 2.0" }   # recompute:true (default) — one sweep for all 3
```

## Gotchas

- **WRONG:** reason about a model's `raw_mean×100` as its score. **RIGHT:** the
  client-visible score is the within-category **percentile** + rank/N. `raw_mean`
  is stored for audit only and is NOT comparable across benchmarks (§13-C —
  Sonnet 4.5 raw math 87 > coding 77, but percentile coding 85th > math 79th).
- **WRONG:** `gate_category_signal_set` with a benchmark name that's slightly off
  ("SWE-Bench" vs the real "SWE-Bench Verified"). It upserts a signal that matches
  ZERO benchmark rows → contributes nothing, `scored_model_count` doesn't move.
  **RIGHT:** copy the exact benchmark string (the enrichment tables use the vendor's
  literal name); confirm `scored_model_count` rose after the recompute.
- **WRONG:** set a signal on a category that doesn't exist yet → **404**. **RIGHT:**
  `gate_category_upsert` the category first, then add its signals.
- **WRONG:** delete a category to "turn it off" — a hard delete cascades and drops
  its scores. **RIGHT:** `gate_category_upsert { key, label, is_active:false }` —
  the row stays, scores are swept on recompute, and you can re-activate later.
  (There is no delete-category endpoint by design.)
- **`recompute` reported `skipped_locked`:** the nightly scorer holds the advisory
  lock. Your edit is SAVED, but scores land on the next sweep (05:00 UTC) — or
  re-issue any write with `recompute:true` once the lock frees.
- **`is_scored=false` vs `is_active=false`:** `is_scored=false` keeps the chip but
  stops the scorer materialising rows for it; `is_active=false` retires the whole
  category (hidden from clients + scores swept). Pick deliberately.

## Verify

```
# After a recipe edit, the recompute summary in the response tells you the effect:
#   recompute: { source_benchmarks, scored_rows, upserted, deleted_stale, categories, skipped_locked }
# - scored_rows / upserted rose after adding a real benchmark signal → it matched models.
# - deleted_stale > 0 after deactivating a category or removing its last signal → stale scores swept.
# - skipped_locked=true → the nightly scorer held the lock; re-run later.

# Cross-check the client-facing read reflects the change (active categories only):
#   GET /api/gate/v1/catalog/categories                 (brand-PAT)
#   GET /api/gate/v1/catalog/leaderboard?category=coding&sort=score
# and the admin list shows the full recipe incl. inactive:
gate_category_list
```
