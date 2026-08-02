# Run modes & progress — single vs campaign, and how to watch

## Two run modes

| Mode | What it is | You submit | You get back |
|---|---|---|---|
| **Single** | one search, one location | `POST /lead-search` | a `job_id` |
| **Campaign** | the same search across many locations | `POST /jobs/spiderMaps/campaigns/submit` | a `campaign_id` |

A **single** run is one pipeline for one query — fastest path, always safe on cost.
A **campaign** fans the same query out across a set of locations (a country, a
region, a population band) and runs one pipeline per location. The cost gate in
the `spiderflows` SKILL.md is about campaigns, not single runs — read it before
submitting any country-wide campaign.

Which to use: if the user named **one** place ("dentists in Lisbon"), run single.
If they want **coverage** ("every plumber in Portugal", "all of Bavaria"), run a
campaign — and check the location count first.

## Watching progress — two ways, never a tight loop

**Workers take seconds-to-minutes per location.** Maps is quick; a site crawl with
`mode: full` (50 pages) plus email verification can take a couple of minutes per
business. Set the user's expectation accordingly, and never spin.

### 1. Poll (simple, stateless)

```bash
# single
curl "https://spideriq.ai/api/v1/jobs/{job_id}/status?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
# campaign — includes a velocity-based ETA
curl "https://spideriq.ai/api/v1/jobs/spiderMaps/campaigns/{campaign_id}/stage-progress?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

**Poll no faster than every 3–5 seconds.** A spin loop just burns your tokens and
rate limit; it does not make the workers go faster. The campaign
`stage-progress` endpoint returns a per-stage breakdown with an ETA — prefer it
over re-fetching `status` in a loop.

### 2. Subscribe to the live SSE stream (push)

```
GET /api/v1/events/stream?token=<client_id>:<api_key>:<api_secret>
```

Events are **client-level**, not campaign-scoped — you receive job lifecycle
events for your whole account:

| Event | Meaning |
|---|---|
| `connected` | stream established |
| `job.queued` | a job was accepted |
| `job.started` | a worker picked it up |
| `job.completed` | a job finished |
| `job.failed` | a job errored |
| `heartbeat` | keep-alive, every 30s |

Because the stream is account-wide, correlate by the `job_id` in each event's
`data`. Use SSE when you want to react the moment a job finishes; use polling when
a one-shot check is enough. `GET /events/status` reports stream health.

## When it's done

A finished single run → read `GET /jobs/{job_id}/results`. A finished campaign →
read through IDAP by `campaign_id`, or pull the one-shot aggregate from
`GET /jobs/spiderMaps/campaigns/{id}/workflow-results`. See
[reading-results.md](reading-results.md). **Don't parse the progress endpoints
for data** — they report status, not the records.
