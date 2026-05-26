# Reference: the exact shape of a finished registry result

Every field below is taken **verbatim from the worker scripts** that produce the
result (`windmill-scripts/spidercompanydata_{search,lookup,vat}.py`) and the
result-format unit tests that pin the contract. Read this so you parse the right
key per mode and never tell the user a field is "missing" when the worker simply
never populates it.

## The job-results envelope (all modes)

`GET /jobs/{job_id}/results` returns the standard envelope; the worker's raw
response is under **`data`** (no transformation for `spiderCompanyData`):

```yaml
success: true            # ENVELOPE success = the JOB ran (HTTP 200). NOT "found something".
job_id: ...
type: spiderCompanyData
status: completed
processing_time_seconds: ...
worker_id: windmill-companydata
data: { ... }            # the worker response — shape differs by mode (below)
error_message: null
```

> ⚠️ **Two different `success` flags.** The envelope `success`/`status` tells you
> the *job* finished. The worker's own `data.success` tells you whether the
> *lookup* worked. A not-found lookup is `status: completed` + HTTP 200 **with
> `data.success: false`**. Always read `data.success` — see
> [read-results.md](read-results.md) and
> [../learnings/2026-05-26-success-flag-not-http-status/](../learnings/2026-05-26-success-flag-not-http-status/artifacts/what-we-learned.md).

## search → `data` carries a list under `data.results`

```yaml
data:
  success: true
  results:                       # the candidate list (may be empty)
    - source: uk_companies_house
      source_id: "00445790"      # UK: company_number · US: 10-digit CIK
      country_code: GB
      name: "TESCO PLC"
      registration_number: "00445790"
      status: active             # UK: real company_status · US: hardcoded "active"
      legal_form: plc            # UK: company_type · US: null
      address:                   # UK: { line_1 (one joined string), country } · US: null
        line_1: "Tesco House, Welwyn Garden City, AL7 1GA"
        country: GB
      incorporation_date: "1947-11-27"   # UK only · US: null
      dissolution_date: null
      industry: { sic_codes: ["47110"], nace_codes: [], description: null }  # UK if sic present, else null
      officers: []               # ALWAYS empty (search never returns officers)
      financials: null           # ALWAYS null in search
      vat_number: null
      tax_id: null
      lei: null
      metadata: { retrieved_at: "...", data_freshness: real-time, confidence_score: 1.0, cached: false, cache_expires_at: null }
  total_results: 1
  query: "Tesco"
  country: GB                    # "all" when you didn't constrain it
  sources_queried: [uk_companies_house]
  query_time_ms: 412
```

- **US search records are thin.** US (SEC EDGAR) returns only `name` + `source_id`
  (CIK) + `status: "active"` (hardcoded — not the real status) + `confidence_score
  0.9`. No address, no legal_form, no dates. UK records are far richer.
- **`address.line_1` in search is one joined string** (line_1 + locality + region +
  postal_code), not structured sub-fields. (Lookup returns structured address.)
- **`officers` is always `[]`** and **`financials` always `null`** in search —
  those come from `lookup`, and even then officers stays empty (see below).

## lookup → `data` carries one record under `data.data`

```yaml
data:
  success: true
  data:                          # the single company record
    source: uk_companies_house   # or us_sec_edgar
    source_id: "00445790"
    country_code: GB
    name: "TESCO PLC"
    registration_number: "00445790"
    status: active               # UK: company_status · US: hardcoded "active"
    legal_form: plc              # UK: type · US: entity_type
    address:                     # STRUCTURED in lookup (unlike search)
      line_1: "Tesco House, Shire Park"
      line_2: null
      city: "Welwyn Garden City"
      region: null
      postal_code: "AL7 1GA"
      country: "United Kingdom"  # US: "US"
    incorporation_date: "1947-11-27"   # UK only · US: null
    dissolution_date: null
    industry: { sic_codes: ["47110"], nace_codes: [], description: null }  # US: description from sic_description
    officers: []                 # ALWAYS empty — the worker never populates officers
    financials: null             # null unless include_financials succeeded (UK only) — see below
    vat_number: null
    tax_id: null
    lei: null
    metadata: { retrieved_at: "...", data_freshness: real-time, confidence_score: 1.0, cached: false, cache_expires_at: null }
  country: GB
  query_time_ms: 318
```

- **Not found** → `data` is `{success: false, error: "Company not found", country, query_time_ms}` — **no `data.data` key**.
- **Unsupported country** (anything but GB/US) → `{success: false, error: "Unsupported country: XX", country, query_time_ms}`.
- **`officers` is always `[]`.** Despite the registry exposing directors, this
  worker hard-codes an empty officers list — **do not promise officers**.
- **US lookup** accepts a CIK *or* a ticker; returns `business_address`
  (street1/street2/city/state/zip), `entity_type`, `sic` + `sic_description`. Still
  no incorporation date, status hardcoded `active`.

### financials (UK lookup, `include_financials: true`)

```yaml
financials:
  revenue: 65578000000           # GBP; null if the filing omits it
  net_income: ...
  total_assets: ...
  total_liabilities: ...
  net_assets: ...
  employees: ...
  fiscal_year_end: "2024-02-24"
  filing_date: "..."
  filing_type: "AA"
  document_url: "https://find-and-update.company-information.service.gov.uk/..."
  extraction_method: mistral_ocr   # or "url_only"
  extraction_confidence: 0.95      # null for url_only
  extraction_skipped: false        # true for url_only
```

- `url_only` mode returns just `{document_url, filing_date, filing_type,
  extraction_method: url_only, extraction_skipped: true}` — no figures, **free**.
- OCR figures can be **null even on success** — small/micro filings (AA01/AA02)
  omit revenue/P&L; only "Full Accounts" carry them.

## vat → `data` carries the validation under `data.data`

```yaml
data:
  success: true                  # the JOB succeeded — validity is data.data.valid
  data:
    vat_number: "DE123456789"    # normalized (prefix + digits, separators stripped)
    valid: false                 # VIES verdict
    country_code: DE
    company_name: null           # VIES entity name when valid — but some member states return null even when valid
    company_address: null
    request_date: "2026-05-26T..."
    error: "Country XX not supported by VIES"   # PRESENT only when validation couldn't run
  query_time_ms: 240
```

- **`valid: false` + an `error` key = couldn't validate** (unsupported country,
  VIES fault, transient). **`valid: false` with no `error` = genuinely invalid.**
  Different things — see
  [../learnings/2026-05-26-vat-validates-not-enriches/](../learnings/2026-05-26-vat-validates-not-enriches/artifacts/what-we-learned.md).
- **`company_name`/`company_address` can be null even when `valid: true`** — several
  EU member states return validity without the entity name.
- VAT has **no `country` key** at the response level (search/lookup do); the
  jurisdiction is `data.data.country_code`, derived from the VAT prefix.

## Normalized read (IDAP `company_registry`) — search & lookup only

`search` and `lookup` records normalize into the `company_registry` IDAP type
(stable columns: `name`, `source`, `source_id`, `registration_number`,
`legal_form`, `status`, `vat_number`, `tax_id`, `lei`, `address_line1/2`, `city`,
`region`, `postal_code`, `country`, `country_code`, `incorporation_date`,
`dissolution_date`, `officers`, `financials`, `industry_description`,
`confidence_score`). **VAT does NOT normalize** — its validation dict has no
`name`/`source_id`, so the normalizer skips it; read VAT only via
`/jobs/{id}/results`. See [read-results.md](read-results.md).

## Gotchas

- **HTTP 200 ≠ found.** Read `data.success` and `data.error` first.
- **`status` is normalized to a fixed set in IDAP** (`active`/`dissolved`/
  `liquidation`/`dormant`/`unknown`); a UK `"closed"` becomes `unknown`. The raw
  `/results` payload carries the registry's own string.
- **`officers` is always empty** from this worker. **`financials`** appears only on
  a successful UK `include_financials` lookup.
- **US results are thin** — name + CIK + hardcoded `active`; don't expect dates or
  rich address parity with UK.
- **`vat` is thin by design** — validity + (sometimes) entity name. For a full
  company picture run `lookup`, or the company-intel chain.
