# Recipe: what a bulk run costs, and what stops it

Read this **before** `sourceLeadsBulk`. A bulk submit is a single purchase from a
third-party provider. Unlike a campaign, it cannot be stopped halfway and the
spend is committed by one call.

## How the estimate is computed

The 202 tells you exactly what the guard was evaluated against. It is a
deliberate **upper bound** — the caps the request will actually send the
provider, not an average and not a yield prediction. A guard sized on "what
usually comes back" fails on the one run that comes back full.

```
expanded_queries = distinct "{query}, {geo.label}" strings   (cap: 1000)
per_query        = source.limits.max_records_per_query
                   ↓ omitted?
                   BULK_DEFAULT_RECORDS_PER_QUERY = 500
records          = expanded_queries × per_query
                   ↓ then clamped
                   min(records, source.limits.max_total_records)
cost_usd         = records × provider unit cost      (null if no unit cost set)
```

**Worked example — the trap.** Two queries, three cities, no `limits`:

```
expanded_queries = 2 × 3   = 6
per_query        = 500       ← the DEFAULT, because you omitted the limit
estimated_records = 6 × 500 = 3,000 records
```

Six searches sounds small. It is three thousand records. **Always set
`limits.max_records_per_query`** unless the user genuinely wants the default
depth.

## The two arms that refuse a run

Both are evaluated **before** the manifest is written and before the provider is
contacted, so a denial leaves nothing behind and charges nothing.

| Arm | Refuses when | Reason code | `Retry-After`? |
|---|---|---|---|
| **1 · Record ceiling** | `estimated_records` > the plan's `bulk_records_per_job` (default `BULK_DEFAULT_MAX_RECORDS_PER_JOB` = **25 000**) | `bulk_records_per_job_exceeded` | **No — deliberately.** The run is too big and stays too big; waiting changes nothing. Split it or raise the cap. |
| **2 · Prospective 24h spend** | `already_spent_24h + estimated_cost >= cost_ceiling_usd_per_24h` | `bulk_estimated_spend_exceeded` | Yes — seconds to midnight UTC, because the window rolls |

Both return **429** with `reason_code` and `reason_human`. Only arm 2 carries
`retry_after_seconds` — an absent one is information, not an omission.

**Arm 2 is PROSPECTIVE on purpose.** Every other service checks spend
retrospectively — you submit, and the ceiling notices on the *next* submit. For
bulk that is useless: the money is gone by then. So bulk asks "would this run
cross the cap?" *before* buying.

**Arm 1 always works; arm 2 can be inactive.** If the provider has no configured
unit cost, `estimated_cost_usd` comes back `null` and the spend arm has nothing
to evaluate — the **record ceiling is then the only thing guarding the run**.
`null` cost does not mean free.

## The hard ceiling on breadth

`queries x geo` is a cross product, and it is capped at **1 000 expanded
queries** (`MAX_EXPANDED_QUERIES`). Crossing it is a **422 at submit**, naming the
arithmetic:

```
SourceQuerySpec expands to 12000 queries, above the 1000 ceiling
(40 queries × 300 geo targets). Split the run.
```

This is the guard against a small-looking body becoming a twelve-thousand-search
purchase. If you hit it, split the run by geo — not by lowering per-query limits.

## Before you submit — the checklist

1. **State the estimate to the user in records, not searches.** "6 searches"
   understates it; "up to 3 000 records" is the number they are approving.
2. **Set `limits.max_records_per_query`.** The 500 default is deep.
3. **Set `limits.max_total_records`** as a hard backstop when the user gave you a
   budget in records.
4. **Check `estimated_cost_usd` in the 202.** If it is `null`, say so — the
   record ceiling is the only arm.
5. **Decide `vayapin` explicitly.** It publishes permanent public profiles; that
   is a separate irreversibility from the money.

## Gotchas

- **A 429 here is not a rate limit.** It is a budget refusal with a
  `reason_code`. Do not blind-retry it — either narrow the run or tell the user
  the ceiling was reached.
- **`bulk_records_per_job_exceeded` has no `Retry-After`, and that is the
  answer.** Retrying the identical body will fail identically, forever. Narrow
  the run.
- **Retrying an arm-2 denial unchanged will keep failing** until the 24h window
  rolls; `retry_after_seconds` tells you when.
- **The estimate is an upper bound, so the invoice is usually smaller.** Report
  it as a ceiling ("up to"), never as a quote.
- **`requested_count` vs `delivered_count`.** The manifest stores what you asked
  for and what actually arrived. That pair is what makes "did this run
  under-deliver?" answerable — check both before re-buying.

## Verify

- 202 `estimated_records` matches what you told the user → you approved the right
  number.
- 429 → read `reason_code`; `bulk_records_per_job_exceeded` means narrow the run
  (no waiting will help), `bulk_estimated_spend_exceeded` means wait out the
  window or raise the cap.
- 422 naming an expansion above 1 000 → split by geo and resubmit.
