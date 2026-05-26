# Recipe: read what a company-intel run produced

Two paths: a quick one-shot aggregate, or queryable IDAP reads. The aggregate is
the right call for company-intel — it returns the assembled account brief per
company in one shot. Use IDAP when you want to page, project, or query the
normalized registry / LinkedIn / contact / email records on their own.

## One-shot aggregate → `/jobs/{job_id}/results`

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Works for **both** single and batch (`job_id` is the one returned by the submit).
Single returns one company's brief; batch returns one record per company. This is
the account brief: discovered `domain`/`final_url`, the registry filing, the
LinkedIn company record, verified `emails[]`, and `sub_jobs` (the per-stage
outputs so you can drill in). See [results-shape.md](results-shape.md) for the
exact fields.

## Queryable reads → IDAP, by type

Company-intel's normalized records are reachable as their own IDAP resource
types. The big difference from the lead chain: the **registry filing and the
LinkedIn record are standalone IDAP types**, not `include=` relations on a
business.

| You want | Call |
|---|---|
| the registry filings produced | `GET /api/v1/idap/company_registry?format=yaml` |
| the LinkedIn profiles/company records | `GET /api/v1/idap/linkedin_profiles?format=yaml` |
| the people (contacts) found | `GET /api/v1/idap/contacts?format=yaml` |
| the verified emails | `GET /api/v1/idap/emails?format=yaml` |
| the crawled businesses + their domains/emails | `GET /api/v1/idap/businesses?include=emails,phones,domains,contacts&format=yaml` |

```bash
# registry filings
curl "https://spideriq.ai/api/v1/idap/company_registry?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"

# LinkedIn records
curl "https://spideriq.ai/api/v1/idap/linkedin_profiles?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

### Paging & projection

`limit` is 1–500 (default 100); follow the `cursor` from each response until it's
empty. `?fields=name,registration_number,status` projects fewer columns — fewer
tokens. `?format=yaml` saves 40–76% over JSON. See the foundation's
[reading-results.md](../../../references/reading-results.md) for the full IDAP
parameter set.

## Gotchas

- **`company_registry` and `linkedin_profiles` are top-level IDAP types — NOT
  `include=` relations on businesses.** `GET /idap/businesses?include=company_registry`
  silently drops the unknown include and returns no registry data. Query
  `GET /idap/company_registry` and `GET /idap/linkedin_profiles` directly.
- **The aggregate `/results` is the most complete single read for company-intel.**
  Because this chain assembles a per-company brief, the aggregate stitches all
  five stages together; IDAP gives you the same data sliced by type for paging /
  filtering.
- **Unknown `include` values are silently dropped** — a typo gives you fewer
  fields, not an error. For `businesses` the valid expansions are
  `emails,phones,domains,contacts,pins`.
- **Don't parse progress endpoints for data.** `GET /jobs/{id}/status` tells you
  *how far along*; `/results` and IDAP are the data surfaces.
- **Tenant isolation**: you only ever see your own `client_id`'s records.
- **Empty stage ≠ failure.** A missing `registry` (company not in a public
  registry) or empty `linkedin_company` (no page found) is a legitimate result.

## Verify

- `GET /jobs/{job_id}/results` returns the company brief(s) with the stages you
  enabled present.
- `GET /idap/company_registry` returns rows carrying `registration_number` /
  `status` for the companies that resolved.
- Verified emails carry a `status` (`valid`/`risky`/`invalid`/`unknown`) and a
  `score` (0–100) — see the email-score note in [results-shape.md](results-shape.md).
