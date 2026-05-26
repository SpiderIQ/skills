# Recipe: scrape many websites (batch)

The same single-site crawl run across a **list** of URLs in one request — up to
**500** per batch. Use this for enriching a domain list, snapshotting a set of
competitors, or building compendiums for a corpus ("scrape these 40 sites", "pull
contacts for every domain in this list", "build LLM context from these pages").

This is *batch*, not *campaign*: you hand it an explicit list of URLs, each with
its own settings. siteScraper has **no `campaign` mode** — there's no "every site
in a country" fan-out. (If the user wants every *local business* in a place, that's
the [maps-site-verify-vayapin](../../maps-site-verify-vayapin/recipes/run-campaign.md)
chain instead.)

## Steps

1. **Build the list.** Each entry is a full single-site input — so each URL can
   carry its own `mode` and knobs. Mixed modes are fine (one `contacts`, one
   `leads`, …).

2. **Submit** the batch through the Flows facade — `POST /api/v1/flows/siteScraper/run`
   with an `inputs` array (this is the **only** batch path; the dedicated
   `/jobs/spiderSite/submit` endpoint is single-URL only):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/flows/siteScraper/run" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "priority": 5,
       "inputs": [
         { "url": "https://acme.com",    "mode": "contacts" },
         { "url": "https://globex.com",  "mode": "leads", "extract_team": true },
         { "url": "https://initech.com", "mode": "compendium" }
       ]
     }'
   ```

   Response (`201`):
   ```json
   {
     "run_group_id": "...",
     "flow_slug": "siteScraper",
     "dispatch_type": "spiderSite",
     "mode": "batch",
     "run_ids": ["...", "...", "..."]
   }
   ```
   One `run_group_id` covers the whole batch; each `run_ids[i]` is an individual
   crawl's job id (read each one with `/jobs/{run_id}/results`).

3. **Watch the group** — poll the aggregate, no faster than every 3–5s:
   ```bash
   curl "https://spideriq.ai/api/v1/run-groups/{run_group_id}?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   It reports `total` / `succeeded` / `failed` / `pending` plus each run's status.
   The runs execute in parallel across the worker pool, so a 50-URL batch finishes
   far faster than 50 sequential single calls — but a list of heavy `full` / SPA
   crawls is still many minutes.

4. **Read** each site's data from its `run_id` (`GET /jobs/{run_id}/results`), or
   query all the crawled businesses at once through IDAP — see
   [read-results.md](read-results.md).

## Key fields (`FlowRunRequest`, batch mode)

| Field | Default | Notes |
|---|---|---|
| `inputs` | — (required) | **1–500** entries, each a full single-site input (own `url` + knobs) |
| `priority` | `0` | 0–10, shared across the batch |

There is no top-level "shared settings" object — each `inputs[i]` carries its own
`mode` / `extract_*` / `compendium` / etc. (unlike company-intel's batch, where
`profile_mode` is shared). Repeat the knobs per entry, or vary them per URL.

## Gotchas

- **Hard cap of 500 URLs per batch.** A list of 1,200 is three batches. Submitting
  0 inputs, or >500, is a `422` (`"batch mode requires 1-500 inputs"`).
- **One bad item rejects the whole submission.** Each input is validated against
  the flow schema before any run is created; a malformed entry returns
  `422 "Batch item {i}: ..."` and nothing is queued. Fix the flagged item and
  resubmit.
- **Per-URL settings live on each entry.** There's no shared-defaults block — put
  `mode`/`extract_team`/`compendium` on every `inputs[i]` that needs it.
- **A failed run doesn't fail the batch.** One site can 404, time out, or block
  the crawler while the rest succeed — the group still completes. Check each run's
  status in the `/run-groups/{id}` aggregate; partial batches are normal.
- **Emails are unverified here too** — same as single mode (no SMTP-verify stage).

## Verify

- `run_ids` length matches the number of `inputs` you sent.
- `mode` in the response is `batch`.
- `GET /run-groups/{run_group_id}` shows `total` equal to your list length, and
  `succeeded + failed + pending == total`.
