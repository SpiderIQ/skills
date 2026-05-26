# Recipe: enrich one LinkedIn profile (profile mode)

You have a **LinkedIn profile URL** and want the full record behind it — name,
headline, location, current company, full experience and education history,
languages, follower/connection counts. Use this whenever the user hands you a
profile link ("enrich this person", "what's linkedin.com/in/satyanadella's
background", "pull this candidate's experience").

The flow is `flow:linkedinProfiles` (SpiderPeople), `mode: profile` — a **Bright
Data dataset scrape**. No proxy, no LinkedIn account, no campaign.

> **What this actually does under the hood** (so you set the right expectation):
> it *triggers an asynchronous Bright Data scrape*, gets a `snapshot_id`, then
> polls until the snapshot is ready. It is **not** an instant lookup — see Timing.

## Steps

1. **Have the profile URL.** `linkedin_url` is the only required field for this
   mode. It **must** be a person URL containing `/in/` (e.g.
   `https://www.linkedin.com/in/<handle>`, ≤512 chars). The worker normalizes it
   (strips a trailing `/`) and **rejects anything without `/in/`** — a company URL
   (`/company/...`) makes the job **fail**, not return empty. For a company, use
   [run-company.md](run-company.md).

2. **Submit** `POST /api/v1/jobs/spiderPeople/submit`. The body is **wrapped in a
   `payload` object** (the generic job-submit shape — unlike `/lead-search` or
   `/company-intel`, which take fields at the top level):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderPeople/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "payload": {
         "mode": "profile",
         "linkedin_url": "https://www.linkedin.com/in/satyanadella"
       }
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "spiderPeople", "status": "queued", "created_at": "...", "from_cache": false, "message": "..." }`.
   **`from_cache: true`** means the platform returned an identical job you (or your
   tenant) submitted in the last 24h — **no new charge** (see Cost & caching).

3. **Watch — budget tens of seconds to a few minutes.** Poll
   `GET /jobs/{job_id}/status` **no faster than every 3–5s**, or use the SSE
   stream. Bright Data runs the scrape asynchronously; the worker polls it ~1×/s
   with **no fixed deadline**, so a profile commonly takes 20s–2min, occasionally
   longer for a heavy profile. Tell the user "a few moments", not "instant", and
   never tight-loop. See [run-modes-and-progress.md](../../../references/run-modes-and-progress.md)
   and the [async-scrape-timing](../learnings/2026-05-26-async-scrape-timing/) learning.

4. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   The result carries `mode: profile`, a top-level **`status`** (`success` or
   `unavailable`), and the profile fields. **Always check `status` first** — see
   [results-shape.md](results-shape.md). The person also normalizes into IDAP
   `linkedin_profiles` / `contacts` (asynchronously) — see [read-results.md](read-results.md).

## Key fields (profile mode of `SpiderPeopleJobPayload`)

| Field | Default | Notes |
|---|---|---|
| `mode` | `profile` | set it to `profile` explicitly |
| `linkedin_url` | — (required) | full `/in/` profile URL, ≤512 chars. Missing → `422`; non-`/in/` URL → job **fails** |
| `person_name` | none | optional context label; the worker ignores it |
| `test` | `false` | routes to the test queue (dev only) |
| `priority` | `0` | **top-level** sibling of `payload`, 0–10 |

(`search_*`, `company_url`, `max_employees`, `profile_mode` belong to other modes —
ignored here. Full map in [per-mode-settings.md](per-mode-settings.md).)

## Cost & caching

- **~$0.003 per profile** (Bright Data dataset API) — the cheapest mode.
- **24-hour dedup is free.** An identical `payload` re-submitted within 24h returns
  the prior job (`from_cache: true`) — you are **not** billed again, and the result
  is instant. To force a genuinely fresh scrape, change something in the payload.
  Don't re-submit the same URL in a loop expecting "fresher" data — you'll just get
  the cache. See [dedup-24h-is-free](../learnings/2026-05-26-dedup-24h-is-free/).

## Gotchas

- **A private/closed profile returns `status: "unavailable"`**, not a crash and not
  an error job — the payload is `{ "mode": "profile", "status": "unavailable",
  "error": "...", "linkedin_url": "..." }`. This is **terminal** — the profile stays
  private; **do not retry**, it wastes a call. Tell the user the profile is private.
  See [empty-is-not-failure](../learnings/2026-05-26-empty-is-not-failure/).
- **A failed job is often transient, not terminal.** Remote workers occasionally hit
  DNS / network blips reaching Bright Data; the worker auto-retries its poll, but a
  job that hard-failed at trigger usually **succeeds on a simple resubmit**.
  Distinguish: `status: unavailable` = terminal (private); a `failed` *job* =
  usually transient (resubmit once). See
  [transient-vs-terminal-failures](../learnings/2026-05-26-transient-vs-terminal-failures/).
- **profile mode wants a profile URL, not a company URL.** `/company/...` → job
  fails. Use [run-company.md](run-company.md).
- **Don't tight-loop the status endpoint.** The scrape is async; polling faster than
  3–5s burns your rate limit and tokens without making Bright Data finish sooner.

## Verify

- Got a `job_id` and `status: queued`/`processing` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- The results `mode` is `profile`, the top-level `status` is `success`, and
  `profile`/`linkedin_url` echoes your input. `status: unavailable` = private (a
  valid completed outcome, not a failure).
