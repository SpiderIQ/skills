# Recipe: research one company (single)

One company name in → a full account brief out. Use this whenever the user
names **one** company ("research Acme Corp", "give me a brief on Stripe",
"who works at Pleo and what's their domain").

The chain is `flow:perplexity-site-companydata-people` (marketed as
**Company Intel**):

```
Perplexity        SpiderSite          SpiderCompanyData   SpiderPeople        SpiderVerify
discover domain → crawl the site →    registry filing →   LinkedIn team →     verify the
+ LinkedIn URL    (emails, team,       (Companies House,   (employees from     extracted emails
+ description     company info)        SEC, EU VIES)        LinkedIn)           (SMTP, score)
```

## Steps

1. **Give it the name — and any hint you already have.** `company_name` is the
   only required field. Every hint you add either *improves discovery* or
   *skips a stage* (cheaper + faster):
   - `city` + `country_code` → sharper Perplexity discovery (disambiguates
     "Acme, Berlin" from "Acme, Texas") and constrains the registry lookup.
   - `domain` → **skips** Perplexity domain discovery; the crawl starts immediately.
   - `linkedin_url` → **skips** Perplexity LinkedIn discovery; SpiderPeople goes
     straight to that company page.

2. **Decide the stages.** All five run by default. Turn off what you don't need
   via `config` — e.g. skip LinkedIn employees (`spiderpeople.enabled=false`) if
   you only want domain + registry, or skip the registry
   (`spidercompanydata.enabled=false`) for a non-EU/US/UK company where it can't
   resolve anyway. See [per-stage-settings.md](per-stage-settings.md).

3. **Submit** `POST /api/v1/company-intel`:

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/company-intel" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "company_name": "Pleo",
       "city": "Copenhagen",
       "country_code": "DK",
       "profile_mode": "short",
       "max_employees": 20
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "single", "flow": "company_intel_full", "status": "processing" }`.

4. **Watch** — poll `GET /jobs/{job_id}/status` no faster than every 3–5s, or use
   the SSE stream. The full chain runs **five** workers in sequence, so a single
   company is minutes, not seconds — set the user's expectation. See the
   foundation's [run-modes-and-progress.md](../../../references/run-modes-and-progress.md).

5. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   Or query the normalized records through IDAP — see [read-results.md](read-results.md).

## Key fields (`CompanyIntelRequest`)

| Field | Default | Notes |
|---|---|---|
| `company_name` | — (required) | 1–255 chars |
| `city` | none | location hint — improves discovery + constrains registry |
| `country_code` | none | ISO 2-letter; UK (`GB`) auto-enables registry financials (~$0.05) |
| `domain` | none | known domain — **skips** Perplexity domain discovery |
| `linkedin_url` | none | known LinkedIn company URL — **skips** LinkedIn discovery |
| `profile_mode` | `short` | employee detail: `short` (name+title) / `full` (+skills/education) / `full_email` (+email discovery). Higher = slower + pricier. |
| `max_employees` | `20` | 1–2000 employees from LinkedIn |
| `config` | all stages on | per-stage toggles — see [per-stage-settings.md](per-stage-settings.md) |
| `test` | `false` | routes to the test queue (dev only) |

## Gotchas

- **The registry only resolves UK / US / EU companies.** SpiderCompanyData reads
  free public registries — UK Companies House, US SEC EDGAR, EU VIES (VAT). A
  company outside those (e.g. a private DACH GmbH with no EU VAT) returns an empty
  `registry`, and that's expected — not a failure. Don't promise a filing for
  every company.
- **Hints skip stages — use them.** If you already know the domain, pass it; you
  pay for one fewer discovery call and the crawl is more accurate. Same for
  `linkedin_url`.
- **`profile_mode` drives both cost and time.** `short` is the cheap default;
  `full`/`full_email` pull skills/education/email per employee and cost more —
  only request them when the user needs that depth.
- **Partial results are normal.** Each stage is independent; one can come back
  empty (no LinkedIn page found, registry miss, site with no emails) while the
  others succeed. Read every stage's status, not just the top-level one — see
  [results-shape.md](results-shape.md).

## Verify

- Got a `job_id` and `status: processing` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- The `flow` field in the response is `company_intel_full` for single (vs
  `company_intel_batch` for batch) — a cheap confirmation you hit the right path.
