# Read usage, cost, capacity, and traces

Four scopes of visibility. Pick the smallest one that answers the question.

| Question | Surface |
|---|---|
| "What did **this call** cost?" | Its row in the trace list (`gate_traces`, newest first) carries `cost_usd`. The completion response itself carries no cost ([cost-aware-completion.md](cost-aware-completion.md)) |
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
**not "your usage"**. Only keys in the shared pool are counted: no brand's private key is in
these numbers, and a provider whose only traffic is on private keys has no row.
`subscription_windows` and `gate_flow` are brand-scoped.

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

Your brand's own keys as they stand now. `days` does not apply to this block.

```json
"subscription_windows": {
  "scope": "brand_keys", "gauge_available": true, "gauge_blocked_reason": null,
  "keys": [
    { "integration_id": 672, "provider": "qwen", "cost_type": "subscription",
      "subscription_tier": "qwen_coding_pro",
      "package_label": "Alibaba Coding Plan — Pro · $50/mo (6,000 requests/5h · 45,000/week)",
      "window_tokens_counted": 9001, "window_requests_counted": 412,
      "window_limit": 6000, "window_hours": 5, "window_reset_at": null,
      "state": "measured", "reason": null, "detail": null,
      "window_percent": 6.87, "weekly_percent": null, "verdict": null,
      "packages_available": 9, "can_set_plan": false },
    { "integration_id": 671, "provider": "codex", "cost_type": "subscription",
      "subscription_tier": "codex_pro", "package_label": "ChatGPT Pro 200 · $200/mo",
      "window_tokens_counted": null, "window_requests_counted": null,
      "window_limit": null, "window_hours": null, "window_reset_at": null,
      "state": "unmeasurable", "reason": "plan_has_no_published_cap",
      "detail": "Plan: ChatGPT Pro 200 · $200/mo. No request limit is published for this plan, so there is nothing to measure this window against.",
      "window_percent": null, "weekly_percent": null, "verdict": null,
      "packages_available": 5, "can_set_plan": false } ] }
```

Both rows are the service's own test fixtures run through the live handler. The values are
synthetic; the shape is exact.

🔴 **A field that is present and `null` is not zero and not missing.** Test for `null`
(`is None`, `=== null`), never for a falsy value. A truthiness check turns a real `0` into
"unknown", and lets a `null` render as an empty gauge, which reads "you have used nothing".

**Read each row's `state`, not the block flag.**

- `measured`: `window_percent` is a number from `0` to `100`. **`0` is a reading**: the
  window is open and has made no requests yet.
- `unmeasurable`: `window_percent` is `null`, and `reason` says why.

**The counts follow the same rule.** `window_tokens_counted` and `window_requests_counted`
are `null` on a key with no window width (`window_hours` is `null` or `0`). Nothing resets a
count on such a key, so no per-window figure exists. They are also `null` on every lease-only
key, with or without a width: SpiderGate sends no request on that login, so nothing is
counted here. On any other key with a width, `0` means nothing has been counted in this
window yet. A `null` count is a normal answer, not a broken response. The
first field counts **tokens** and the second counts **requests**; only requests are compared
with `window_limit`. Use `window_percent` as given. Do not recompute it from the counts.

**`gauge_available` is derived on every response.** It is `true` when at least one key in
`keys` is `measured`. It answers "can any gauge be drawn on this panel", not "is this row a
number": with it `true`, other rows can still be `unmeasurable`, as the second row above is.
`gauge_blocked_reason` is `null` whenever it is `true`. When it is `false`, that field is one
sentence, written from the rows, saying why nothing can be drawn. Show the sentence to a
person. Do not branch on its wording; branch on each row's `reason`.

An `unmeasurable` row carries exactly one `reason`:

| `reason` | It means | Suggest setting a plan? | Tell the user |
|---|---|---|---|
| `no_plan_assigned` | The key holds no limit to measure against, and its provider offers packages. Normally no package is assigned. | **Yes.** This is the only reason with `can_set_plan: true`. | A package can be picked for this key. Relay `detail`: it gives how many are on offer and who can pick one. Do not promise a percentage, because a package with no published limit reads `plan_has_no_published_cap` afterwards. |
| `no_packages_for_provider` | The provider offers no packages. | No. There is nothing to pick. | This key's window cannot be measured, and nothing needs doing. |
| `counter_incomparable` | A limit is set, and the request count is more than 10 times that limit. | No. A limit is already set, and another package would not help. | The count and the limit do not describe the same window, so no percentage is shown in place of a false 100%. |
| `plan_has_no_published_cap` | A package is assigned, and it publishes no request limit. | No. The key already has its plan. | The key is on the plan named in `package_label`. That plan has no published request limit, so no percentage exists for it. This is a normal reading, not a fault. Many plans publish no limit. |
| `lease_only_not_counted` | The key is lease-only and holds a request limit. SpiderGate lends that login to the owner's own CLI and sends no request on it, so it has no count to set against the limit. | No. No package changes this. | The limit in `window_limit` is real, and the provider counts the use against it where SpiderGate cannot see it. Relay `detail`. Do not say `0%` or "unused": no reading was taken. |

Offer "set a plan" from `can_set_plan`, never from your own reading of the other fields.

**A lease-only key is never `measured`.** Its `window_percent` and both counts are `null`
whatever plan it is on. Where it holds no request limit it reads the same reason as any
other key (`no_plan_assigned`, `no_packages_for_provider` or `plan_has_no_published_cap`).

Every row carries all 18 fields on every response:

| Field | Type | `null` when |
|---|---|---|
| `integration_id` · `provider` · `cost_type` | integer · string · string | never |
| `subscription_tier` | string | no tier is set. It can also be an empty string; neither is a plan |
| `package_label` | string | no tier is set, or the tier matches no package |
| `window_tokens_counted` · `window_requests_counted` | integer | the key has no window width, or the key is lease-only |
| `window_limit` | integer | the key holds no limit |
| `window_hours` | integer | the key has no window width (`0` means the same) |
| `window_reset_at` | ISO-8601 string | the key has no window width, or no reset time is recorded |
| `state` | `measured` or `unmeasurable` | never |
| `reason` · `detail` | string | `state` is `measured` |
| `window_percent` | number, `0` to `100` | `state` is `unmeasurable` (always, on a lease-only key) |
| `weekly_percent` · `verdict` | `null` | **always.** No weekly count is collected, and a window row carries no verdict |
| `packages_available` | integer | never. The number of packages the key's provider offers |
| `can_set_plan` | boolean | never. `true` only on `no_plan_assigned` |

**Which keys are listed.** A key appears when it has counted tokens, has a tier set, holds a
limit, or is an active subscription key whose provider offers packages. So a new
subscription key is listed before its first request, as `no_plan_assigned` with `null`
counts. Free and paid keys with a running count appear too. `keys` holds at most `key_limit`
rows (default 50, maximum 200), keys that hold a limit first, and carries no truncation
flag. If you receive exactly `key_limit` rows, raise it before saying you saw every key.

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
# list, newest first (filters: agent_id, model, status ∈ success|error; pages: page from 1, limit 1-100, default 50)
curl -s "…/gate/traces?status=error&limit=20"       -H "Authorization: Bearer $SPIDERIQ_PAT"
# one trace: span waterfall (auth → route → LLM call → track) + input/output messages
curl -s "…/gate/traces/$TRACE_ID"                   -H "Authorization: Bearer $SPIDERIQ_PAT"
# summary: total traces, success/error counts, p95 latency, total cost
curl -s "…/gate/traces/stats/summary"               -H "Authorization: Bearer $SPIDERIQ_PAT"
```

The list answers `traces`, `total`, `page` and `has_more`. Ask for `page + 1` while `has_more`
is `true`. The route has **no `offset`**: one sent to it is dropped without an error and
page 1 comes back, so a loop over `offset` reads the same rows every time. The `gate_traces`
tool pages by `page` from `@spideriq/mcp-gate` 1.12.0 (sink `@spideriq/mcp` 1.96.0); older
releases sent `offset` and always returned page 1.

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
- **The list never carries message bodies, and one trace can lose them.** The list is always
  read from `gate_request_logs` (model, tokens, cost, latency, status). One trace's messages
  and spans come from LangFuse; when LangFuse cannot be reached, or does not hold the trace
  under your brand, the detail read answers from the same row with `input` and `output`
  `null`, `spans` empty and `source: "database"`. That is the fallback, not a bug.
- **No message content in `gate_request_logs`.** Prompts/responses live in LangFuse only.
  Don't expect to recover a prompt from the usage rollup.
- **Per-call cost is on the trace row, not in the response.** For the cost of a call you just
  made, read its row in the trace list (`cost_usd`). The completion response has no
  `spidergate_metadata` block.
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
