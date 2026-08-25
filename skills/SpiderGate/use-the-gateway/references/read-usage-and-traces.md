# Read usage, cost, capacity, and traces

Four scopes of visibility. Pick the smallest one that answers the question.

| Question | Surface |
|---|---|
| "What did **this call** cost?" | `spidergate_metadata.cost_usd` on the completion itself — free, immediate ([cost-aware-completion.md](cost-aware-completion.md)) |
| "What did we **spend / deliver** over a window?" | `GET …/gate/usage` · `gate_usage` · `spideriq gate usage` |
| "Do we **need more keys**?" | `GET …/gate/capacity` · `gate_capacity` · `spideriq gate capacity` |
| "What actually **served** my alias?" | `GET …/gate/flow` · `gate_flow` · `spideriq gate flow` |
| "Show me **one request** end to end" | `GET …/gate/traces/{id}` · `gate_trace_detail` |

Aggregate surfaces live under `/api/v1/brands/{brand_id}/gate/*` and need your **numeric
`brand_id`** — not the `cli_…` workspace slug. `gate_capacity` and `gate_flow` require
`@spideriq/mcp-gate` **≥ 1.10.0** (or the sink `@spideriq/mcp` ≥ 1.89.0) and
`@spideriq/cli` **≥ 1.71.0**. On an older client they do not exist.

---

## 1. Usage — ask for a real window, then read the outcome split

```bash
# THIS MONTH — a calendar range, which a rolling lookback cannot express
curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/usage\
?from=2026-08-01T00:00:00Z&to=2026-09-01T00:00:00Z&bucket=day&compare=true" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

| Param | Meaning |
|---|---|
| `from` / `to` | ISO-8601. `from` inclusive, `to` exclusive (defaults to now). Naive values read as **UTC**. |
| `days` | **DEPRECATED** rolling lookback (1–366). **Ignored when `from`/`to` are supplied.** |
| `bucket` | `day` (default) or `hour` — grain of `by_bucket`. |
| `compare` | Also returns the immediately preceding window of equal length under `comparison`. Doubles query cost. |

`range` echoes what the server resolved: `{from, to, bucket, duration_hours,
is_calendar_month, resolved_from}`. **Read it back** — it is how you confirm you measured the
window you meant. A window longer than 366 days is `422`; `to` at or before `from` is `422`.

### `turn_metrics` — never quote a bare "requests"

```json
"turn_metrics": { "turns": 812, "attempts": 1104, "amplification": 1.359,
                  "attempts_without_trace": 0, "turns_complete": true }
```

A **turn** is one logical request. **Attempts** include retries and provider fallbacks, so
`total_requests` is an *attempt* count and reporting it as user demand overstates it —
here by 36%. If `turns_complete` is `false`, some attempts carry no `trace_id` and could
not be folded into a turn; say so rather than quietly absorbing them.

### `outcome` — FOUR states, and `unknown` is not a success

```json
"outcome": {
  "delivered": 640, "hollow": 118, "failed": 41, "unknown": 13,
  "truncated": 22, "tool_call_turns": 87,
  "total": 812, "scope": "request_kind='chat'",
  "measurable_from": "2026-08-13", "window_predates_measurement": false,
  "delivered_rate": 0.7882, "measured": true
}
```

- `delivered` · `hollow` · `failed` · `unknown` are **mutually exclusive and sum to `total`**.
- 🔴 **`unknown` means "we cannot tell", not "it worked".** These are rows predating the
  `output_chars` column. Folding them into `delivered` is a false all-clear — the exact
  defect this surface exists to remove.
- `measurable_from` is the date the split became trustworthy (**`2026-08-13`** today —
  **read the field, do not hard-code it**). `window_predates_measurement: true` means your
  window reaches back before that, so `delivered_rate` is computed over the classifiable
  rows only and the percentage cannot mean what it appears to say. Report the caveat with
  the number, or do not report the number.
- ⚠️ **`truncated` and `tool_call_turns` are ANNOTATIONS that overlap the four states, not
  extra states.** Summing all six double-counts. A tool-call turn returns zero visible
  characters *by construction* and is **delivered**, not hollow.
- `measured: false` (with `reason`) means zero `chat` rows were in scope. That is **not**
  a pass and **not** a 0% — it is "nothing to classify".

### `cost_avoided` — a counterfactual, never an invoice

```json
"cost_avoided": { "state": "measured", "basis": "counterfactual",
                  "reference_model": "openai/gpt-4o",
                  "at_list_price_usd": 412.77, "spent_usd": 38.4102,
                  "avoided_usd": 374.36, "multiple": 10.75 }
```

What these exact tokens *would* have cost at one reference model's public list price. **No
bill was avoided** — never present `avoided_usd` as billing or savings. `state:
"unmeasurable"` (every money field `null`, plus a `reason`) means the reference price is
missing; there is deliberately no hard-coded fallback price.

### 🔴 `by_provider` is NOT the provider

It carries the **litellm wire prefix**. ~75,000 MiniMax rows are stamped `"openai"`. An
agent that reports it attributes MiniMax traffic to OpenAI and then acts on it. Treat the
field as a wire route, or ignore it — **for the real provider use `gate_flow`**, which
resolves it through the key's integration.

Also present: `by_model`, `by_alias`, `by_agent`, `by_kind`, `by_bucket` (each bucket
carries its own nested `outcome`), `by_day` (alias of `by_bucket`), `latency`
(`p50/p95/p99/avg_ms`), `top_errors`, `cache_hit_rate`, `cached_count`, `streamed_count`,
`error_rate`, `distinct_aliases`. At `bucket=day` each `by_bucket[].date` is a plain
`YYYY-MM-DD`; at `bucket=hour` it is a **full ISO timestamp**.

---

## 2. Capacity — the recommendation that is allowed to say "no"

```bash
curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/capacity?days=7&key_limit=50" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

🔴 **Two blocks, two different scopes. Read the label before quoting a number.**

`key_pressure` carries `traffic_scope: "pool_wide"` — it counts **every** request on a key
regardless of which tenant caused it, because a pooled key serves the whole pool. It is
**not "your usage"**. `subscription_windows` and `gate_flow` are brand-scoped.

Each `key_pressure.providers[]` row carries a **`verdict`**:

| Verdict | What it means for "should I buy keys?" |
|---|---|
| `healthy` | No. Nothing is under pressure. |
| `add_keys` | Yes — and **only here** is `suggested_keys` a number (the recommended *total*). |
| `not_quota` | **No.** Errors are high but they are **not** rate limits. Keys will not fix it. |
| `account_capped` | **No.** The cap is on the ACCOUNT; one more key is refused identically. |
| `over_provisioned` | No — you already hold more than the traffic needs. |
| `unmeasurable` | Cannot tell. Do not infer either way. |

🔴 **`suggested_keys` is `null` for every verdict except `add_keys`.** Rendering a number
on a `not_quota` row turns a refusal into an upsell — a verdict that cannot say "no" is not
a recommendation.

`limit_source` is a **three-way** answer and you must say which one you used:
`published` (a real ceiling) · `partial` · `estimated_from_429` (**an estimate, not a
published ceiling**). `headroom_pct` is only populated when `limit_source == "published"`.

Each row also carries `attempts`, `errors`, `rate_limited`, `error_pct`,
`rate_limited_pct`, `quota_share_of_errors_pct`, `failed_cost_usd`, `serving_keys`,
`pool_eligible_keys`, `registered_keys`, `published_daily_cap`, `peak_day_attempts`,
`ceiling_coverage_pct` and `rpd_unpublished`.

### `subscription_windows` — present-and-**null** is not zero

```json
"subscription_windows": { "scope": "brand_keys", "gauge_available": false,
  "gauge_blocked_reason": "sub_window_count counts tokens; the subscription tier limit counts requests…",
  "keys": [ { "provider": "cerebras", "state": "unmeasurable",
              "window_tokens_counted": 41822, "window_percent": null,
              "weekly_percent": null, "verdict": null, "can_set_plan": true } ] }
```

🔴 **Read `gauge_available` every time — it is live-changing, not a constant**, and flips as
the unit work lands. While it is `false`, `window_percent` / `weekly_percent` are
**present and `null`**, not absent and **not `0`**. Never render a null as an empty gauge;
that is indistinguishable from "you have used nothing". `can_set_plan` says whether
assigning a package is even possible for that key. `window_tokens_counted` is named for
what it counts — **tokens** — because the underlying column name is not.

---

## 3. Flow — what you asked for vs what actually served it

```bash
curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/flow?days=7&limit=100" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Returns `rows[]` of `{requested_model, actual_model, provider, requests, errors, cost_usd}`
plus `truncated`, `limit`, and `provider_source`. This is the fallback and routing picture
behind a task alias — the gap between the alias you sent and the model that answered.

✅ The `provider` here is resolved through `integration_id → api_integrations`, so a MiniMax
model reports **`minimax`** and never `openai`. When this disagrees with `usage.by_provider`,
**this column is the correct one**. If `truncated` is `true` you are seeing a prefix of the
cross-tab, not all of it — raise `limit` before drawing a conclusion about the tail.

---

## 4. Traces — one request, end to end

```bash
# list (filters: agent_id, model, status ∈ success|error, limit, offset)
curl -s "…/gate/traces?status=error&limit=20"       -H "Authorization: Bearer $SPIDERIQ_PAT"
# one trace: span waterfall (auth → route → LLM call → track) + input/output messages
curl -s "…/gate/traces/$TRACE_ID"                   -H "Authorization: Bearer $SPIDERIQ_PAT"
# summary: total traces, success/error counts, p95 latency, total cost
curl -s "…/gate/traces/stats/summary"               -H "Authorization: Bearer $SPIDERIQ_PAT"
```

MCP: `gate_traces` · `gate_trace_detail` · `gate_trace_stats`. Brand overview:
`gate_stats` (`…/gate/stats` — active agents, total requests, spend; unchanged by this
release and already at parity with the page).

---

## Gotchas

- **`client_id` is the identity ground-truth; `brand_id` is the analytics key.** Traces are
  isolated per brand (LangFuse `userId = client_id`). A wrong `brand_id` returns empty or
  403 — never another tenant's data.
- **The tool and the page must agree.** `gate_usage` and `/dashboard/gate/usage` are
  advertised as the same numbers over the same window. If they disagree, that is a bug
  worth reporting, not a rounding difference to explain away.
- **Usage is "my spend", NOT capacity.** The usage rollup is scoped `WHERE brand_id = …`;
  a pooled key serves the whole pool, so a brand-filtered per-key rollup under-counts it by
  ~72%. Never reuse usage numbers as a quota or headroom input — that is what
  `gate_capacity` is for.
- **Traces degrade to metadata-only when LangFuse is down.** The list still returns from
  `gate_request_logs` (model, tokens, cost, latency, status) but **without** message bodies.
  A trace with no messages is the fallback path, not a bug.
- **No message content in `gate_request_logs`.** Prompts/responses live in LangFuse only.
  Don't expect to recover a prompt from the usage rollup.
- **Per-call cost ≠ the rollup, instantly.** For the exact cost of a call you just made,
  read its `spidergate_metadata.cost_usd` — don't poll `/usage` for it.
- **A `500` here is honest.** This endpoint deliberately does **not** fall back to a
  zero-filled payload, because all-zeros is indistinguishable on screen from "you used
  nothing". Retry; do not treat a failure as an empty result.

## Verify

```bash
# Calendar range resolves as a month, and the outcome split is trustworthy for it:
curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/usage\
?from=2026-08-01T00:00:00Z&to=2026-09-01T00:00:00Z" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
| python3 -c '
import json,sys; s=json.load(sys.stdin)["summary"]; o=s["outcome"]; t=s["turn_metrics"]
print("calendar month :", s["range"]["is_calendar_month"])
print("turns/attempts :", t["turns"], "/", t["attempts"], "amp", t["amplification"])
print("outcome sums   :", o["delivered"]+o["hollow"]+o["failed"]+o["unknown"] == o["total"])
print("trustworthy    :", not o["window_predates_measurement"], "(measurable_from", o["measurable_from"]+")")
'

# A verdict that refuses must carry NO key recommendation:
curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/capacity" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
| python3 -c '
import json,sys
for r in json.load(sys.stdin)["key_pressure"]["providers"]:
    print(r["provider"], r["verdict"], "suggested_keys=", r["suggested_keys"], "limit_source=", r["limit_source"])
'
```
