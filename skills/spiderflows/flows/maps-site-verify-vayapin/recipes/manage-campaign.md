# Recipe: manage a running campaign — stop, resume, retry, delete

All on the Bearer path `/api/v1/jobs/spiderMaps/campaigns/{id}/...`. CLI mirrors
these as `spideriq campaigns <verb>`; MCP as `*_campaign` tools.

## Stop / resume

```bash
# stop — halts dispatch of further locations
curl -X POST ".../campaigns/{id}/stop"     -H "Authorization: Bearer $SPIDERIQ_PAT"
# resume a stopped campaign
curl -X POST ".../campaigns/{id}/continue" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Use `stop` the instant a campaign's `total_locations` comes back larger than
intended (see [cost-check.md](cost-check.md)). In-flight jobs finish; no new
locations dispatch.

## Retry one location

`POST .../campaigns/{id}/locations/{location_id}/retry` with a `retry_mode`:

| `retry_mode` | Re-runs from | Keeps |
|---|---|---|
| `full` (default) | SpiderMaps | nothing — fresh run |
| `site` | SpiderSite | the Maps results |
| `verify` | SpiderVerify | the Maps + Site results |

```bash
curl -X POST ".../campaigns/{id}/locations/{location_id}/retry" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{ "retry_mode": "site" }'
```

Response carries `new_status`, `retry_count`, and (for `full`/`site`) a fresh
`job_id`. Pick the narrowest mode that recovers the failure — `verify` if only
SMTP checks flaked, `site` if a crawl timed out, `full` if Maps itself returned
nothing.

## Retry all failed locations

```bash
curl -X POST ".../campaigns/{id}/retry-failed" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{ "max_locations": 50 }'
```

Re-runs every failed location (up to `max_locations`). Locations that already hit
the **3-retry limit are skipped, not errored** — the response reports
`retried_count`, `retried_locations[]`, and `skipped_count`.

## Delete

```bash
curl -X DELETE ".../campaigns/{id}" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Deletes the campaign and its run/location rows; response reports
`deleted_locations`.

## Gotchas

- **Stop before you delete.** `DELETE` refuses with **`409`** while the campaign has
  active jobs. `stop` it, let in-flight jobs settle, then delete.
- **Delete does not unpublish VayaPin pins.** Pins live on `cs.vayapin.com` and
  survive campaign deletion — see [vayapin-export.md](vayapin-export.md). Deleting
  the campaign only removes *your* campaign/location records.
- **`retry-failed` silently skips exhausted locations** — a `skipped_count > 0`
  isn't an error; those locations failed 3× and need a different fix (or a
  per-location `full` retry).

## Verify

- After `stop`, `stage-progress` shows no new locations dispatching.
- After a retry, the location's status flips to `processing` and `retry_count` ticks up.
- `DELETE` returns `200` with `deleted_locations`; a follow-up
  `GET /idap/businesses?campaign_id={id}` returns nothing for that campaign.
