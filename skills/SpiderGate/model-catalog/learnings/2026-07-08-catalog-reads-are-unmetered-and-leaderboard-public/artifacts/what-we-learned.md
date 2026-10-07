# Catalog reads are free to poll; the leaderboard needs no auth

**What happened.** The GateBoard catalog READ surface (D.1) shipped four endpoints an
agent uses to *pick a model*. Two assumptions bite agents that treat it like a billable
job API:

1. **"Reading the catalog costs credits."** It does not. All four reads are **list-only —
   not metered, not billable**, the same class as `GET /models`. SpiderGate meters fire
   only on a *completion* (`spidergate_callback.emit_llm_meter`), never on a read. At D.1
   test-live, `GET /catalog/leaderboard|models|{id}|{id}/evals` produced **zero**
   `gate_request_logs` rows. Poll freely — but the catalog is large + stable, so cache
   within a session.

2. **"Everything needs the brand PAT."** Not the leaderboard. `GET /catalog/leaderboard`
   is **fully public** — an agent can rank models *before* it authenticates. The other
   three (`/catalog/models`, `/catalog/models/{id}`, `/catalog/models/{id}/evals`) are
   brand-PAT, and identity resolves **server-side** from the Bearer triple via the
   `clients` table — you pass nothing extra.

**The rank-then-filter rule.** The leaderboard ranks by **eval score, not price**. To
answer "best model for `<task>` under `$X`":

```
GET /api/gate/v1/catalog/leaderboard?task_type=coding   →  rank by quality
   then filter the returned rows by the cheapest live blended price (on every row)
```

There is no `max_price` param — the price is on each row so you filter yourself.

**`null` eval ≠ zero.** Eval scores stay null until an OPVS eval contribution lands for
that model×task. A null score means *no prior yet*, not "scored zero" — don't rank a
model last for missing data.

**Calling the pick (corrected 2026-10-07).** This entry first said to pass the
`model_id` straight to `chat` as `model`. That is not true of every row: a Codex
row's `id` and its `model_id` are both refused, and the row is called as
`codex/<model_id>`. Every catalog row and every `getModel` record now carries
`call_as`, the exact `model` string to send for that row right now, or `null`.
Send `call_as`. If it is `null`, the model cannot be called through the gateway
now. Leaderboard rows carry no `call_as`, so read the winner with `getModel(id)`
first. You still do **not** have to wrap it in a task alias.

**Why it matters.** An agent that believes reads are billable throttles itself
needlessly; one that thinks the leaderboard needs auth blocks a pre-auth "which model
should I use" question that the public endpoint answers directly.
