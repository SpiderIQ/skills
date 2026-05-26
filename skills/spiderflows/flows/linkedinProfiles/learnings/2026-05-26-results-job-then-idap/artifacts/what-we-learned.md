# Read the job aggregate first; IDAP catches up afterward

**Starting point, not ground truth — verify against current code.**

## The surprise

A `linkedinProfiles` job is **not** a campaign — it has no `campaign_id`. So the
"read results by `campaign_id` through IDAP" habit from the lead chain doesn't
apply here. The authoritative, immediate output is the **job aggregate**:

```
GET /jobs/{job_id}/results
```

That's `SpiderPeopleData` — `profile` / `profiles[]` / `employees[]` for the mode
you ran, ready the moment the job completes.

## The two-surface timing

The same people *also* land in IDAP as `linkedin_profiles` and `contacts` — but
not synchronously. On completion the callback dual-writes the result to the
`results` table with `crm_status='pending'`, and the **CRM sync** later writes the
normalized `contacts` + `linkedin_profiles` rows. So:

- `/jobs/{id}/results` — **immediate**, job-scoped, authoritative.
- `/idap/linkedin_profiles`, `/idap/contacts` — **eventually consistent**,
  tenant-scoped (no `campaign_id` filter), populated after the CRM sync runs.

## Why it matters

- If you query IDAP the instant the job completes, the rows may not be there yet —
  that's the lag, not a bug. Read the aggregate first.
- IDAP is the right surface when you want to page, project fields, or query across
  **all** the people you've collected over many jobs — once it's caught up.
- Because there's no `campaign_id`, scope is your whole tenant; use `fields` / paging
  / `since` to narrow.

## Rule of thumb

- One job, one read → `/jobs/{id}/results`.
- Cross-job, paged, or filtered reads → IDAP `linkedin_profiles` / `contacts`, after
  allowing for the CRM-sync lag.
