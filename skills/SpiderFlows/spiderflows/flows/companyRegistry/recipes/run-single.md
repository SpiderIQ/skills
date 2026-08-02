# Recipe: look up one company in a public registry (single)

One company in → its government-registry filing out. Use this whenever the user
wants a registry record for **one** company — a registration number, a US SEC
record, or an EU VAT validation ("what's Tesco's company number", "look up CIK
0000320193", "is DE123456789 a valid VAT number", "find the SEC filing for Apple").

This is the **standalone** registry lookup — a single worker
(`spiderCompanyData`), no enrichment chain. If the user wants the *full* picture
(domain + crawl + LinkedIn + verified emails around the registry record), that's
the company-intel chain instead — see
[../../perplexity-site-companydata-people/recipes/run-single.md](../../perplexity-site-companydata-people/recipes/run-single.md).

```
SpiderCompanyData (one worker, three modes — and three different registries)
search → companies matching a name      (UK Companies House + US SEC EDGAR)
lookup → one record by its registry ID  (UK Companies House OR US SEC EDGAR)
vat    → validate an EU VAT number      (EU VIES — 28 member states)
```

## Pick the mode AND the right country first

The mode decides the required fields **and** which registry is reached. Getting the
country wrong wastes the run (an empty result or `success:false`), so decide up
front:

- **`search`** — find companies **by name**. Needs `name`. `country` routes it:
  `GB` → UK only, `US` → US only, **omitted → BOTH UK+US**. Any other country code
  matches nothing (empty list, not an error). US only finds public/SEC-filing
  companies.
- **`lookup`** — fetch **one** record by its registry ID. Needs `identifier` **and**
  `country`, and **only `GB` or `US` resolve** — any other country returns
  `success:false, "Unsupported country: XX"`. The ID is registry-specific: a UK
  company number, or a US CIK/ticker.
- **`vat`** — **validate** an EU VAT number against VIES. Needs `vat_number` with its
  country prefix. The EU is reachable **only** this way — there is no EU
  company-record lookup.

Full detail (coverage, financials, the VIES country list, cost):
[modes-and-options.md](modes-and-options.md).

## Submit — `POST /api/v1/jobs/spiderCompanyData/submit`

The body wraps the lookup in a `payload` object:

```bash
# search by name (UK only)
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderCompanyData/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"payload": {"mode": "search", "name": "Tesco", "country": "GB", "limit": 10}}'

# lookup one UK record by company number
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderCompanyData/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"payload": {"mode": "lookup", "identifier": "00445790", "country": "GB"}}'

# lookup a US company by CIK (ticker also works) + financials are UK-only, so omit them here
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderCompanyData/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"payload": {"mode": "lookup", "identifier": "0000320193", "country": "US"}}'

# UK lookup WITH financials (~$0.05, Mistral OCR of the filed accounts)
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderCompanyData/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"payload": {"mode": "lookup", "identifier": "00445790", "country": "GB", "include_financials": true, "financials_mode": "auto"}}'

# validate an EU VAT number
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderCompanyData/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"payload": {"mode": "vat", "vat_number": "DE123456789"}}'
```

Response (`201`): `{ "job_id": "...", "status": "processing" }`.

## Watch — poll `/jobs/{job_id}/results` (not a tight loop)

Poll no faster than every 3–5s, or use the SSE stream. Timing by mode:

- **`search` / UK `lookup` / `vat`** — seconds (one HTTP/SOAP call each).
- **US `lookup`** — slower (~6–7s); it fetches the full SEC company object via
  edgartools.
- **UK `lookup` + `include_financials`** — up to a minute or two (downloads the
  accounts PDF and runs Mistral OCR over ~50 pages).

The poll endpoint's HTTP status is the job state: `202` = still running, `200` =
completed, `410` = failed. See [read-results.md](read-results.md).

## Read — and check `data.success`, not just the HTTP status

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

A missed lookup still returns **HTTP 200 / `status: completed`** — the verdict is
the worker's own `data.success`:
- `search` → `data.results[]` (list; `data.total_results`).
- `lookup` → `data.data{}` (one record) when `data.success: true`; else `data.error`
  (`"Company not found"` / `"Unsupported country: XX"`).
- `vat` → `data.data.valid` (the job is always `success: true`; validity is inside).

search + lookup also normalize into IDAP `company_registry`
(`GET /idap/company_registry`); vat does not. Field-by-field:
[results-shape.md](results-shape.md).

## Key fields (`SpiderCompanyDataJobPayload`)

| Field | Default | Notes |
|---|---|---|
| `mode` | `search` | `search` (by name) · `lookup` (by registry ID) · `vat` (validate VAT) |
| `name` | — | **required for `search`**; 1–500 chars |
| `identifier` | — | **required for `lookup`**; UK company number or US CIK/ticker |
| `country` | — (`lookup` defaults `GB`) | ISO-2; **required for `lookup`** (GB/US only); routes `search` (GB/US/both) |
| `vat_number` | — | **required for `vat`**; full VAT incl. country prefix (`DE123456789`) |
| `limit` | `10` | `search` only; 1–100 |
| `include_financials` | `false` | **UK `lookup` only**; OCR of filed accounts (~$0.05) — ignored for US |
| `financials_mode` | `auto` | `url_only` (free, URL only) · `auto`/`ocr` (~$0.05). `ixbrl`/`regex` are accepted but coerced to `auto` |
| `test` | `false` | routes to the test queue (dev only) |
| `priority` (top level, beside `payload`) | `5` | 1–10 job priority |

## Gotchas

- **The country decides the registry — pick it deliberately.** `search`/`lookup`
  reach **UK + US only**; the **EU is `vat`-only**. A `lookup` with any non-GB/US
  country returns `success:false "Unsupported country"`; a `search` with a non-GB/US
  country returns an empty list. There is no DE/FR/NL/ES/IL company-record lookup,
  despite the flow card. See
  [../learnings/2026-05-26-registry-coverage-limits/](../learnings/2026-05-26-registry-coverage-limits/artifacts/what-we-learned.md).
- **A mismatched mode/field is a `422` at submit** (search without `name`, lookup
  without `identifier`+`country`, vat without `vat_number`) — different from a
  `success:false` *result*. See
  [../learnings/2026-05-26-mode-required-fields/](../learnings/2026-05-26-mode-required-fields/artifacts/what-we-learned.md).
- **HTTP 200 ≠ found.** Always read `data.success`/`data.error`. An empty `search`
  is also ambiguous (no match vs. swallowed upstream API error). See
  [../learnings/2026-05-26-success-flag-not-http-status/](../learnings/2026-05-26-success-flag-not-http-status/artifacts/what-we-learned.md).
- **`lookup` needs the registry ID — `search` first.** From a name, `search` →
  take the candidate's `source_id` → `lookup` it by `id`+`country`.
- **`officers` is always empty; US records are thin; `vat` validates, doesn't
  enrich.** Don't promise directors, rich US address parity, or a full profile from
  a VAT check. See [results-shape.md](results-shape.md) and
  [../learnings/2026-05-26-vat-validates-not-enriches/](../learnings/2026-05-26-vat-validates-not-enriches/artifacts/what-we-learned.md).
- **Only UK financials cost money** (~$0.05, OCR). Everything else is free. Don't set
  `include_financials` unless the user needs figures; it's ignored on US anyway.

## Verify

- Got a `job_id` and `status: processing` → submitted.
- `GET /jobs/{job_id}/results` → `200` with `data.success: true` and records in the
  mode's key.
- `scripts/verify-companydata-complete.sh <job_id>` audits the finished run (reads
  `data.success`; empty out-of-coverage result = note, not failure).
