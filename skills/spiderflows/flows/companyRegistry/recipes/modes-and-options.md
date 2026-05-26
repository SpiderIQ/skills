# Reference: modes & options (the `payload` object)

The standalone registry lookup is **one worker with three modes**. There are no
stages to toggle (that's the company-intel chain); the `mode` field picks *what*
the lookup does, and a handful of options tune it. **Read this before composing a
non-trivial `payload`** — the right mode + the right country is the difference
between a real filing and an empty/`success:false` result on a paid run.

```json
{
  "payload": {
    "mode": "lookup",
    "identifier": "00445790",
    "country": "GB",
    "include_financials": true,
    "financials_mode": "auto"
  },
  "priority": 5
}
```

## The three modes — and exactly which registries each reaches

| `mode` | Does | Required fields | Registries it actually queries |
|---|---|---|---|
| `search` (default) | find companies **by name** → candidate list | `name` | **UK Companies House + US SEC EDGAR only.** `country=GB`→UK; `country=US`→US; **omitted/empty → BOTH**; any other value → queries nothing (empty result). |
| `lookup` | fetch **one** record by its registry ID | `identifier` **and** `country` | **UK or US only.** `country=GB`→Companies House; `country=US`→SEC EDGAR; **any other country → `success:false`, `error:"Unsupported country: XX"`.** |
| `vat` | **validate** an EU VAT number | `vat_number` | **EU VIES only** (28 member-state codes — see below). Jurisdiction is read from the VAT prefix, not a `country` field. |

> **Coverage in one sentence:** company *records* (search/lookup) come from **UK +
> US only**; the **EU is reachable only through `vat`** (VIES validation), which
> returns validity + (sometimes) the entity name, not a full filing. There is no
> DE/FR/NL/ES/IL company-record lookup in this worker, despite what the flow card
> declares — see [../learnings/2026-05-26-registry-coverage-limits/](../learnings/2026-05-26-registry-coverage-limits/artifacts/what-we-learned.md).

The Pydantic payload validator enforces the *required fields* (missing → `422`
before the job runs). It does **not** validate the country *value* — so
`lookup` with `country:"DE"` passes validation, then the worker returns
`success:false, "Unsupported country: DE"` (HTTP 200). Two different failure
layers; see [../learnings/2026-05-26-mode-required-fields/](../learnings/2026-05-26-mode-required-fields/artifacts/what-we-learned.md).

### search — by name (UK + US)

| Setting | Default | Notes |
|---|---|---|
| `name` | — (required) | 1–500 chars. |
| `country` | none | `GB` → UK only · `US` → US only · **omitted → searches BOTH** · anything else → nothing matches (empty result, not an error). |
| `limit` | `10` | clamped 1–100 candidate records. |

- Returns a **list** (`data.results`) of candidates, each with its `source_id` —
  the ID you then feed to `lookup`. UK records are rich; **US records are thin**
  (name + CIK + hardcoded `status:"active"`, no address/dates).
- **US search only finds companies with recent SEC filings** (it queries 10-K/10-Q
  full-text from 2020; falls back to the edgartools name index). A private US
  company won't appear — SEC EDGAR is essentially public-company coverage.
- **An empty `data.results` can mean "no match" OR "the upstream registry API
  failed"** — the worker swallows UK/US API errors and returns
  `success:true, total_results:0` either way. See
  [../learnings/2026-05-26-success-flag-not-http-status/](../learnings/2026-05-26-success-flag-not-http-status/artifacts/what-we-learned.md).

### lookup — by registry ID (UK or US)

| Setting | Default | Notes |
|---|---|---|
| `identifier` | — (required) | UK company number (`00445790`) **or** US CIK/ticker (`0000320193`, `AAPL`). |
| `country` | `GB` (default) | **required by the schema**; only `GB`/`US` resolve — anything else → `success:false "Unsupported country"`. |
| `include_financials` | `false` | **UK only**; OCR of filed accounts (~$0.05). Ignored for US. |
| `financials_mode` | none → `auto` | see below. |

- `lookup` is the detailed single-record fetch — you need the ID first; if you only
  have a name, run `search` and take the candidate's `source_id`.
- **Not found** → `success:false, error:"Company not found"` (HTTP 200, status
  completed). **`officers` is always empty** even here — the worker never populates
  it; don't promise directors.
- US `lookup` takes a CIK **or a ticker** (edgartools resolves both).

### vat — validate an EU VAT number (VIES)

| Setting | Default | Notes |
|---|---|---|
| `vat_number` | — (required) | Full VAT incl. country prefix; spaces/dashes/dots are stripped (`DE 123 456 789` is fine). `identifier` accepted as a fallback. |

- VIES-supported country codes (the prefix must be one of these, else
  `valid:false, error:"Country XX not supported by VIES"`):
  **AT BE BG CY CZ DE DK EE EL ES FI FR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK XI**.
  Note: **`EL`** is Greece (not `GR`), **`XI`** is Northern Ireland; **`GB` is not
  VIES** (post-Brexit — UK VAT isn't validated here).
- `vat` is a *validation*, not enrichment — returns `valid` + (when the member state
  provides it) `company_name`/`company_address`. VIES is intermittently flaky; a
  transient failure surfaces as `valid:false` **with** an `error` key. See
  [../learnings/2026-05-26-vat-validates-not-enriches/](../learnings/2026-05-26-vat-validates-not-enriches/artifacts/what-we-learned.md).

## UK financials (`include_financials` / `financials_mode`)

Financials apply only to a **UK `lookup`** (`country=GB` + `include_financials:true`).
The worker finds the latest annual-accounts (`AA*`) filing, gets the PDF URL, and
either returns the URL or OCR-extracts figures.

| `financials_mode` you send | What the **live worker** actually does | Cost |
|---|---|---|
| `url_only` | returns just the accounts-PDF URL, no extraction | **free** |
| `ocr` or `auto` | Mistral OCR + LLM extraction of the figures | **~$0.05** |
| `ixbrl` or `regex` | **accepted but coerced to `auto`** (no separate free-parse tier in this native worker) | ~$0.05 |
| omitted | defaults to `auto` | ~$0.05 |

- So in practice there are **two** outcomes: `url_only` (free, URL only) or
  OCR (`auto`/`ocr`/`ixbrl`/`regex` all → OCR, ~$0.05). The legacy iXBRL/regex
  free tiers are **not** in the live WindMill worker — don't promise free figure
  extraction.
- Figures (`revenue`, `net_income`, `total_assets`, `total_liabilities`,
  `net_assets`, `employees`, `fiscal_year_end`) are **GBP** and can be **null even
  on success**: small/micro filings (AA01/AA02) omit revenue/P&L — only "Full
  Accounts" carry them.
- Extraction needs the server-side Mistral key (it's configured); if a filing has
  no `AA*` accounts document, `financials` comes back null.

## Cost model (requests cost money — be precise)

| Mode / option | Cost |
|---|---|
| `search` (UK + US) | **free** (public registry APIs) |
| `lookup` without financials | **free** |
| `lookup` + `include_financials` `url_only` | **free** (URL only) |
| `lookup` + `include_financials` `auto`/`ocr` (UK) | **~$0.05 per company** (Mistral OCR) |
| `vat` (VIES) | **free** |

Only UK financials OCR costs money. Don't set `include_financials` unless the user
needs the figures, and never on a US lookup (ignored) or a long batch unless every
UK entry needs accounts.

## Other request fields

| Field | Default | Notes |
|---|---|---|
| `priority` (top level, beside `payload`) | `5` | 1–10 job priority |
| `test` | `false` | route to the test queue (dev only) |
