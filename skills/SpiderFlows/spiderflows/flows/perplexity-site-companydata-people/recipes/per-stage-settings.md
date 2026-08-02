# Reference: per-stage settings (the `config` block)

Every stage past discovery is configurable through the `config` object on a
single or batch request. All five stages run by default; set `enabled: false` to
skip one. **Read this before composing a non-trivial `config`** — the wrong
toggle silently produces an empty section instead of an error.

```json
{
  "company_name": "Pleo",
  "country_code": "DK",
  "config": {
    "discovery":         { "enabled": true },
    "spidersite":        { "enabled": true, "mode": "leads", "max_pages": 25,
                           "extract_team": true, "extract_company_info": true,
                           "product_description": null, "icp_description": null },
    "spidercompanydata": { "enabled": true, "country": "auto", "include_financials": false },
    "spiderverify":      { "enabled": true, "max_emails": 50 },
    "spiderpeople":      { "enabled": true, "max_employees": 20, "profile_mode": "short" }
  }
}
```

## discovery — Perplexity (`config.discovery`)

| Setting | Default | Notes |
|---|---|---|
| `enabled` | `true` | Use Perplexity to discover the domain + LinkedIn URL + description + industry. |

- Discovery uses the company name + `city`/`country_code` hints. Passing `domain`
  or `linkedin_url` at the top level **skips** that part of discovery (cheaper,
  more accurate). Disabling discovery entirely only makes sense if you supply
  `domain` yourself.

## spidersite — crawl the company website (`config.spidersite`)

| Setting | Default | Notes |
|---|---|---|
| `enabled` | `true` | Crawl the discovered/supplied domain for contacts, team, company info. |
| `mode` | `leads` | `contacts` (≈5 pages, quick emails/phones) · `leads` (≈50 pages, team + scoring) · `full` (≈100 pages, maximum extraction). |
| `max_pages` | `25` | 1–100 cap on pages crawled. |
| `extract_team` | `true` | AI team-member extraction (contact/about/team pages). |
| `extract_company_info` | `true` | AI company-info extraction. |
| `product_description` | none | Your product — enables CHAMP lead scoring (needs `icp_description` too). |
| `icp_description` | none | Your ideal-customer profile — the other half of CHAMP scoring. |

- `full` mode and high `max_pages` are slower. For a quick domain-and-emails brief,
  `contacts` is enough.
- CHAMP lead scoring only appears in results when **both** `product_description`
  and `icp_description` are set.

## spidercompanydata — registry filing (`config.spidercompanydata`)

| Setting | Default | Notes |
|---|---|---|
| `enabled` | `true` | Look up the company in free public registries. |
| `country` | `auto` | `auto` detects from the company; or pass an ISO-2 code to force one. |
| `include_financials` | `false` | UK only; pulls accounts via OCR (~$0.05/company). Auto-enabled when `country_code` is `GB`. |

- **Registries covered: UK (Companies House), US (SEC EDGAR), EU (VIES VAT).**
  A company outside those returns an empty registry — expected, not a failure.
- Financials are **UK-only** and cost money. Small/micro UK filings (AA01/AA02)
  omit revenue/P&L — only "Full Accounts" carry it, so some financial fields may
  be null even when extraction succeeds.

## spiderverify — verify the emails (`config.spiderverify`)

| Setting | Default | Notes |
|---|---|---|
| `enabled` | `true` | SMTP-verify the emails the crawl extracted. |
| `max_emails` | `50` | 1–200 emails to verify. |

- Verification is **deliberately slow** (a few seconds per email — rate-limited to
  protect deliverability). A company with many emails adds real time. Cap
  `max_emails` if you only need the top few.
- Each verified email gets a `status` and a 0–100 `score` — see the scoring note
  in [results-shape.md](results-shape.md) (a valid email on a catch-all or
  disposable domain can legitimately score low).

## spiderpeople — LinkedIn employees (`config.spiderpeople`)

| Setting | Default | Notes |
|---|---|---|
| `enabled` | `true` | Extract employees from the company's LinkedIn page. |
| `max_employees` | `20` | 1–200 employees to pull. |
| `profile_mode` | `short` | `short` (name+title) · `full` (+skills/education/experience) · `full_email` (+email discovery). |

- Needs a LinkedIn company page — supply `linkedin_url` to skip discovery and
  target it directly. If no page is found, this section comes back empty.
- `profile_mode` and `max_employees` drive cost + time: `short` is cheap;
  `full`/`full_email` pull far more per person. The top-level `profile_mode` /
  `max_employees` on the request are merged into `spiderpeople` for convenience.

## Stage independence

The five stages run in sequence but are **independently optional and
independently fallible**. Disabling one (or it coming back empty) does not fail
the run — you get a brief with that section empty. Pick the stages the user's
question actually needs; don't pay for LinkedIn + verification when they only
asked for "what's their domain and registry number".
