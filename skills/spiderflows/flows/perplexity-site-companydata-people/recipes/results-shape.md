# Reference: the shape of a finished company-intel record

What a single company looks like after the five-stage chain, so you know what you
can read back. This is the per-company record inside `/jobs/{job_id}/results`
(single = one, batch = one per company), assembled from all five stages. The same
data is also reachable, sliced by type, through IDAP (see
[read-results.md](read-results.md)).

## Aggregate envelope

```yaml
job_id: ...
type: single            # or batch
status: completed
company:
  name: Pleo
  domain: pleo.io               # Perplexity-discovered (or your hint)
  final_url: https://www.pleo.io
  description: "Spend management platform for teams"
  industry: "SaaS / Fintech"
  hq: "Copenhagen, Denmark"
registry: { ... }               # SpiderCompanyData — may be empty (see below)
linkedin_company: { ... }       # SpiderPeople — may be empty (no page found)
emails: [ ... ]                 # verified addresses tied to the domain
sub_jobs: { ... }               # per-stage outputs, so you can drill into any layer
```

(Batch wraps a list of these under one job; read each company's record + its
per-stage status.)

## Per-stage outputs

### From Perplexity discovery (always, unless disabled)

| Field | Notes |
|---|---|
| `company.domain` | discovered website domain (protocol/`www.` stripped) |
| `company.description` | one-sentence summary |
| `company.industry` | e.g. "Retail / Grocery", "SaaS / CRM" |
| `company.hq` | headquarters city + country |
| (LinkedIn URL) | discovered company LinkedIn URL, fed to SpiderPeople |

- A hint you supplied (`domain` / `linkedin_url`) replaces the discovered value
  and skips that lookup.

### From SpiderSite (if `spidersite.enabled`)

| Field | Notes |
|---|---|
| `company.final_url` | resolved site URL after redirects |
| `emails_found[]` / `phones_found[]` | raw extraction from the crawl |
| `team_members[]` | if `extract_team` |
| `company_info` | if `extract_company_info` |
| `lead_scoring` | CHAMP grade — only if `product_description` + `icp_description` were set |

### From SpiderCompanyData (if `spidercompanydata.enabled`)

`registry` — the filing from a free public registry (UK Companies House / US SEC
EDGAR / EU VIES). Typical fields: filed `name`, `registration_number`,
`status`, registered `address`, `industry_description`, plus `vat_number` (EU) and
(UK + `include_financials`) financial figures.

- **Empty `registry` is normal** for any company not in those three registries.
- UK small/micro filings (AA01/AA02) omit revenue/P&L — financial fields may be
  null even when the filing resolved.

### From SpiderPeople (if `spiderpeople.enabled`)

`linkedin_company` + `employees[]` — the official LinkedIn company URL, employee
size, industry tags, and up to `max_employees` people. Per-person detail depends
on `profile_mode`: `short` = name + title; `full` adds skills/education/experience;
`full_email` adds a discovered email.

- Empty when no LinkedIn company page was found.

### From SpiderVerify (if `spiderverify.enabled`)

`emails[]` — each extracted email after SMTP verification:

| Field | Notes |
|---|---|
| `email` | the address |
| `status` | `valid` · `invalid` · `risky` · `unknown` |
| `score` | 0–100 (see the scoring note below) |
| `is_deliverable` | SMTP confirmed |
| `is_free_email` / `is_disposable` / `is_role_account` / `is_catch_all` | quality flags |

## Reading the same data via IDAP

| Stage | IDAP read |
|---|---|
| registry | `GET /idap/company_registry` (standalone type) |
| LinkedIn | `GET /idap/linkedin_profiles` (standalone type) |
| people | `GET /idap/contacts` |
| emails | `GET /idap/emails` |
| crawled business | `GET /idap/businesses?include=emails,phones,domains,contacts` |

`company_registry` and `linkedin_profiles` are **NOT** `include=` relations on
businesses — query them as their own types.

## Gotchas

- **Email score can be lower than "valid" suggests.** The 0–100 score penalizes
  catch-all (−15), disposable (−30), and role accounts (−10), so a syntactically
  valid, MX-present address on a catch-all domain scores in the 60s, and a valid
  disposable can score ~30. `status: valid` + a mid score is not a bug — explain
  the score to the user from the quality flags.
- **`final_url` ≠ `domain`.** `domain` is what Perplexity discovered;
  `final_url` is where the crawl actually landed after redirects. They can differ
  (e.g. `acme.com` → `www.acme.io`).
- **Partial briefs are the norm**, not the exception — five independent stages,
  each can be empty. Always check per-stage presence before telling the user a
  field is "missing".
