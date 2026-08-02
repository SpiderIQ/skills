# Reference: per-mode settings, cost, timing & limits (the `payload` block)

`flow:linkedinProfiles` is **one endpoint, three modes** — not a multi-stage
pipeline. `mode` selects which provider runs, which field is required, the cost, and
the timing profile. Every request is a `payload` object on
`POST /jobs/spiderPeople/submit`; the fields below live inside that `payload`.
**Read this before composing a non-trivial request** — the wrong field for the mode
is silently ignored, a missing required field is a `422`, and the wrong expectation
wastes money.

```json
{
  "payload": {
    "mode": "company",
    "company_url": "https://www.linkedin.com/company/pleo",
    "max_employees": 50,
    "profile_mode": "short"
  },
  "priority": 0
}
```

## At a glance — the three modes

| | `profile` | `search` | `company` |
|---|---|---|---|
| Provider | Bright Data datasets | Bright Data Google SERP | Apify harvestapi |
| Required field | `linkedin_url` (`/in/`) | `search_query` | `company_url` (or slug) |
| Returns | one full profile | shallow profile list | employee roster |
| **Cost** | **~$0.003** | **~$0.01** | **$4 / $8 / $12 per 1K** (by `profile_mode`) |
| **Timing** | async poll → **tens of s – minutes** | one-shot → **seconds** | async poll → **minutes** (scales) |
| Empty case | `status: unavailable` (private) | `results_count: 0` | `employees_count: 0` |

`source` in the result confirms the engine: `brightdata` / `brightdata_google` / `apify`.

## `mode` (required)

The `@model_validator` enforces the per-mode required field — omit it and the
request is rejected with `422` before any work (or cost) runs.

## profile mode fields

| Field | Default | Notes |
|---|---|---|
| `linkedin_url` | — (required) | full `/in/` URL, ≤512 chars. A `/company/...` URL **fails** the job (use company mode) |

No tuning knobs — a single dataset scrape. Private profile → `status: unavailable`.

## search mode fields

| Field | Default | Notes |
|---|---|---|
| `search_query` | — (required) | natural-language query, ≤256 chars. **Don't add `site:`** — the worker prepends `site:linkedin.com/in` |
| `search_limit` | `10` | **API accepts 1–50, but the worker caps at 25** (`min(n, 25)`) and only reads Google's **first results page** — realistic yield is often <10. Don't promise 50. |
| `country_code` | none | ISO 2-letter → Google `gl` locale (≤2 chars) |

Results are shallow (URL + name + headline + snippet). Re-run a `linkedin_url`
through profile mode for depth.

## company mode fields

| Field | Default | Notes |
|---|---|---|
| `company_url` | — (required) | full company URL **or** a bare slug; worker extracts the slug. ≤512 chars |
| `max_employees` | `100` | worker clamps to **1–2000** |
| `profile_mode` | `short` | per-employee detail **and price tier** (below) |

### `profile_mode` — depth vs cost (company mode only; ignored elsewhere)

| `profile_mode` | Rate | Adds per employee |
|---|---|---|
| `short` (default) | ~$4 / 1K | name + title + location + premium/open flags |
| `full` | ~$8 / 1K | + raw skills / education / experience |
| `full_email` | ~$12 / 1K | + a discovered email **when one is found** |

**Cost = `max_employees × rate`** — e.g. 50 `short` ≈ $0.20; 2000 `full_email` ≈ $24.
Default to `short`; pull cheap, then enrich the shortlist. See
[profile-mode-cost-tiers](../learnings/2026-05-26-profile-mode-cost-tiers/).

## Shared fields (all modes)

| Field | Default | Notes |
|---|---|---|
| `person_name` | none | optional context label; the worker ignores it |
| `test` | `false` | routes to the test queue (dev workers only) |
| `priority` | `0` | **top-level** sibling of `payload`, 0–10 (higher = sooner) |

## Cost-control rules every agent should apply

- **24-hour dedup is free.** An identical `payload` within 24h returns the cached job
  (`from_cache: true`) — no new charge, instant. To force a fresh run, change a
  field. Don't re-submit in a loop expecting fresher data. See
  [dedup-24h-is-free](../learnings/2026-05-26-dedup-24h-is-free/).
- **Size before you submit.** `max_employees × profile_mode` is real money; a
  whole-company `full_email` pull can be tens of dollars.
- **Right mode for the job.** One person → `profile`. A few candidates from a
  description → `search` (then enrich the keepers). A whole company's roster →
  `company`. Using `search` to "find everyone at Acme" wastes calls — that's
  `company`.

## Mode independence

The three modes are mutually exclusive — one request runs exactly one mode. There is
**no batch submission** for this flow (one job = one call). To enrich a person you
searched: a `search` job, then a `profile` job on the URL. To get full detail on a
roster: one `company` job at `full`/`full_email`.
