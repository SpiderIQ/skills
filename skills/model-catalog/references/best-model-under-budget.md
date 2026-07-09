# "Best model for `<task>` under `$X`"

The headline job of this skill. The leaderboard ranks by **eval score**, not price —
so the pattern is **rank on the task, then filter the rows by price yourself**.

## Steps

1. **Rank for the task** (public — no PAT needed):

   ```
   spideriq gate catalog leaderboard --task-type coding --limit 100
   # or: GET /api/gate/v1/catalog/leaderboard?task_type=coding&limit=100
   ```

   Each row carries the model's rank, the headline benchmark, and the **cheapest
   live blended price across providers** (`blended$` / `in$` / `out$`).

2. **Filter by your budget** on the returned rows — the endpoint does NOT take a
   `max_price`. Keep rows whose blended price ≤ your cap, then take the top-ranked
   survivor.

3. **Confirm the pick** with the full record (optional):

   ```
   spideriq gate catalog get <model_id>
   ```

4. **Pin it** by passing the `model_id` straight to a completion (D7 direct-model)
   — you do NOT have to route through a task alias:

   ```
   spideriq gate chat -m <model_id> -p "…"
   ```

## Gotchas

- **WRONG:** expecting the leaderboard to return only affordable models. It ranks
  by quality; a $60/1M frontier model sits at the top regardless of your budget.
- **RIGHT:** rank first, filter by `blended$` second. The price is on every row
  for exactly this.
- A model with a **null eval score** for the task has **no contribution yet** — it
  may still be a fine pick; don't discard it as "scored zero".
- Reads are **not metered** — poll the leaderboard freely, but it's large + stable,
  so cache within a session.

## Verify

`leaderboard(task_type=coding)` returns `count`>0 with `rank` ascending and a
non-null `blended$` (or per-provider price) on each row; the top row after your
price filter is the answer.
