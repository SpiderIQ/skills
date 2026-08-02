# Recipe: find LinkedIn profiles by query (search mode)

You don't have a URL — you have a **description of who you want** ("VP Sales SaaS
Berlin", "CTOs at fintech startups", "5 AI engineers in Israel"). Search mode turns
a natural-language query into a list of matching LinkedIn profiles.

The flow is `flow:linkedinProfiles` (SpiderPeople), `mode: search`. Under the hood
it is a **Bright Data Google-SERP** call: it Googles `site:linkedin.com/in <your
query>`, takes the **organic results from the first page**, and keeps the
`/in/` URLs. No LinkedIn account, no proxy — and that design dictates everything
below.

## The two hard limits — read these before you promise a count

1. **You get the first Google results page only.** The worker requests `start=0`
   and never paginates. After filtering to `/in/` URLs, the realistic yield is
   **often well under 10**, regardless of what you ask for.
2. **`search_limit` is capped at 25 inside the worker.** The API accepts
   `search_limit` up to 50 (Pydantic), but the worker clamps to `max(1, min(n, 25))`
   — and the first-page ceiling usually bites first anyway. **Never tell the user
   you'll return 50 profiles from one search.** See
   [search-is-google-serp](../learnings/2026-05-26-search-is-google-serp/).

If the user needs *many* people from one company, that's [run-company.md](run-company.md)
(the employee roster), not search.

## Steps

1. **Write a natural query.** `search_query` is required (≤256 chars). **Do not add
   `site:linkedin.com/in` yourself** — the worker prepends it. Write it the way you'd
   describe the person: title + domain + place ("Marketing Director SaaS Berlin").
   Optionally set `search_limit` (1–50, effectively ≤25) and `country_code` (ISO
   2-letter — sets Google's `gl` geolocation, e.g. `DE`).

2. **Submit** `POST /api/v1/jobs/spiderPeople/submit` (the `payload`-wrapped body):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderPeople/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "payload": {
         "mode": "search",
         "search_query": "VP Sales SaaS Berlin",
         "search_limit": 10,
         "country_code": "DE"
       }
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "spiderPeople", "status": "queued", "from_cache": false, ... }`.

3. **Watch — this one is fast.** Unlike profile/company (async scrapes), search is a
   **single one-shot** SERP call (60s worker timeout), so it completes in seconds.
   Poll `GET /jobs/{job_id}/status` (≥3–5s) or use SSE. See
   [run-modes-and-progress.md](../../../references/run-modes-and-progress.md).

4. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   The result carries `mode: search`, `status`, `query`, `google_query` (the actual
   `site:`-scoped query that ran), `results_count`, and `profiles[]` (each a shallow
   result) — see [results-shape.md](results-shape.md).

## Key fields (search mode of `SpiderPeopleJobPayload`)

| Field | Default | Notes |
|---|---|---|
| `mode` | `profile` | set it to `search` |
| `search_query` | — (required) | natural-language query, ≤256 chars. Don't add `site:` — the worker does |
| `search_limit` | `10` | API allows 1–50; **worker caps at 25** and the first-page ceiling usually caps lower |
| `country_code` | none | ISO 2-letter → Google `gl` locale (≤2 chars; `DE` not `DEU` → `422`) |
| `test` | `false` | routes to the test queue (dev only) |

## Cost & caching

- **~$0.01 per search** (Bright Data unblocker) — one charge per query regardless of
  how many profiles come back.
- **24-hour dedup is free:** an identical query within 24h returns the cached job
  (`from_cache: true`), no new charge. See
  [dedup-24h-is-free](../learnings/2026-05-26-dedup-24h-is-free/).

## Gotchas

- **Search results are shallow by design.** Each hit is `linkedin_url`, `name`,
  `headline`, `location`, `snippet` — parsed from the Google result, *not* a real
  profile. `name`/`headline` are split from the Google title and can be imperfect;
  `location` is best-effort from the snippet (often null). For the full record, take
  a result's `linkedin_url` and run [run-profile.md](run-profile.md) — that's a
  **separate ~$0.003 job per person**, so enrich only the ones that matter.
- **Coverage = Google's first page.** A niche query can return a handful or zero —
  that's a normal SERP outcome (`results_count: 0`, `status: success`), not a
  failure. Broaden the query or drop the `country_code` constraint.
- **This is not authenticated LinkedIn search.** It reflects what Google indexes
  about LinkedIn. The deeper, account-gated Voyager `search_people` is a **separate
  service** (SpiderPublicLinkedin) and is out of scope here.

## Verify

- Got a `job_id` and `status: queued`/`processing` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- `mode` is `search`, `status` is `success`, and `results_count` = `len(profiles)`
  ≤ 25 (usually fewer). Zero hits on a niche query is valid, not a failure.
