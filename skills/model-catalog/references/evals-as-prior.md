# The #7 evals aggregate — a prior, not a verdict

`modelEvals` returns the **shared prior** for a model on a task: machine-eval
(`auto`) rollups plus human star ratings, keyed on the **served** model. A planner
blends this prior against its own posterior (its private experience) — it does not
replace judgement.

## Read it

```
spideriq gate catalog evals claude-3-5-sonnet --task-type coding
# GET /api/gate/v1/catalog/models/claude-3-5-sonnet/evals?task_type=coding
```

Shape:

```jsonc
{
  "auto":   [ /* machine-eval rollups per task_type */ ],
  "human":  [ /* human star ratings */ ],
  "summary": { "auto_count": N, "human_count": M, "avg_stars": X }
}
```

- Omit `--task-type` to get every task type **plus** the global (`task_type=null`)
  row.
- Scores are **keyed on the served model (G1)** — if you pinned a concrete model
  and a fallback served a different one, the eval belongs to what actually ran.

## Gotchas

- **`null` ≠ zero.** An empty `auto`/`human` or a null score means *no eval
  contribution has landed yet* for that model×task — common while enrichment is
  young. Treat it as "no prior", not "ranked last".
- **The aggregate is brand-stripped.** Only the cross-brand aggregate crosses into
  the catalog; no brand identity, prompts, or raw rows. You cannot see who
  contributed — by design.
- **This is a prior.** For a high-stakes pick, confirm with your own small eval;
  the aggregate biases the search, it doesn't end it.

## Verify

`modelEvals(model_id, task_type=coding)` returns 200 with the `{auto[], human[],
summary{...}}` shape (possibly empty while enrichment is dark); an unknown
`model_id` returns 404.
