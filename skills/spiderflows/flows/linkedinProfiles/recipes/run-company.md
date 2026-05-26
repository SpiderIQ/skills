# Recipe: extract a company's employees (company mode)

You have a **company's LinkedIn page** and want its people — the employee roster
with titles, and optionally skills/education/experience and discovered emails. Use
this for a candidate shortlist, mapping a competitor's org, or building an ABM
contact list ("who works at Pleo", "pull the eng team at this competitor").

The flow is `flow:linkedinProfiles` (SpiderPeople), `mode: company` — an **Apify**
`harvestapi/linkedin-company-employees` actor run. No campaign fan-out; one company
per job. **This is the most expensive mode — read Cost before you set
`max_employees` / `profile_mode`.**

## Steps

1. **Provide the company.** `company_url` is required by the API. The worker accepts
   **either** a full `https://www.linkedin.com/company/<slug>` URL **or** a bare slug
   (`pleo`) — it extracts the slug either way. Pass the URL; it's unambiguous.

2. **Pick depth and size — they multiply cost.** `max_employees` (1–2000, default
   100) caps how many people come back. `profile_mode` sets per-person detail **and
   the Apify price tier**:
   - `short` (default) — name, title, location, profile URL, premium/open flags. **~$4 / 1K**.
   - `full` — adds raw skills / education / experience. **~$8 / 1K**.
   - `full_email` — adds a discovered email per person *when one is found*. **~$12 / 1K**.

3. **Submit** `POST /api/v1/jobs/spiderPeople/submit` (the `payload`-wrapped body):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderPeople/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "payload": {
         "mode": "company",
         "company_url": "https://www.linkedin.com/company/pleo",
         "max_employees": 50,
         "profile_mode": "short"
       }
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "spiderPeople", "status": "queued", "from_cache": false, ... }`.

4. **Watch — budget minutes.** This starts an **Apify actor run** and polls it ~1×/2s
   with **no fixed deadline**. Time scales with `max_employees` and `profile_mode`: a
   small `short` roster is a minute or two; a large `full_email` pull is many
   minutes. Poll `GET /jobs/{job_id}/status` (≥3–5s) or use SSE — never tight-loop.
   See [async-scrape-timing](../learnings/2026-05-26-async-scrape-timing/).

5. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   The result carries `mode: company`, `status`, `company_url`, `company_slug`,
   `profile_mode`, `employees_count`, and `employees[]` — see
   [results-shape.md](results-shape.md).

## Key fields (company mode of `SpiderPeopleJobPayload`)

| Field | Default | Notes |
|---|---|---|
| `mode` | `profile` | set it to `company` |
| `company_url` | — (required) | full company URL (or a bare slug), ≤512 chars |
| `max_employees` | `100` | employees to pull; worker clamps to 1–2000 |
| `profile_mode` | `short` | `short` ($4/1K) · `full` ($8/1K) · `full_email` ($12/1K) |
| `test` | `false` | routes to the test queue (dev only) |

## Cost & caching — do the math before you submit

Cost = **`max_employees × per-1K rate`**. Concrete:

| Pull | Rate | Approx cost |
|---|---|---|
| 50 employees, `short` | $4/1K | **~$0.20** |
| 200 employees, `full` | $8/1K | **~$1.60** |
| 500 employees, `full_email` | $12/1K | **~$6.00** |
| 2000 employees, `full_email` | $12/1K | **~$24.00** |

- **Default to `short` and cap `max_employees`** to what the user needs. A common,
  cheap pattern: pull `short` first, pick the people who matter, then enrich that
  short list — far cheaper than `full_email` on the whole company. See
  [profile-mode-cost-tiers](../learnings/2026-05-26-profile-mode-cost-tiers/).
- **24-hour dedup is free:** same `company_url` + `max_employees` + `profile_mode`
  within 24h → cached job (`from_cache: true`), no new charge. Changing any of those
  forces a fresh (billed) run. See
  [dedup-24h-is-free](../learnings/2026-05-26-dedup-24h-is-free/).

## Gotchas

- **`email` appears only in `full_email`, and only when Apify finds one.** Even at
  `full_email`, employees with no discoverable email simply have no `email` field —
  that's normal. `short`/`full` never carry `email`.
- **`experience` / `education` / `skills` (in `full`/`full_email`) are RAW Apify
  shapes** — they pass through unchanged and do **not** match the normalized
  `experience[]`/`education[]` shape that profile mode returns. Don't assume the same
  keys across modes — see [results-shape.md](results-shape.md).
- **Zero employees can be a real result.** A page with no public roster, a brand-new
  / tiny company, or a wrong slug all return `employees_count: 0`,
  `status: success`. Before retrying, re-check the `company_url` matched the company.
  See [empty-is-not-failure](../learnings/2026-05-26-empty-is-not-failure/).
- **`open_profile` and `premium` are outreach signals.** `open_profile: true` means
  the person accepts InMail without a connection — useful for prioritizing outreach.
- **Transient vs terminal:** Apify 5xx / network blips on the poll are auto-retried
  by the worker (fail-open); a run that ends `FAILED`/`ABORTED`/`TIMED-OUT` fails the
  job — usually worth one resubmit. See
  [transient-vs-terminal-failures](../learnings/2026-05-26-transient-vs-terminal-failures/).

## Verify

- Got a `job_id` and `status: queued`/`processing` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- `mode` is `company`, `status` is `success`, `company_slug` matches the page, and
  `employees_count` ≤ `max_employees`. The result echoes the `profile_mode` you ran.
