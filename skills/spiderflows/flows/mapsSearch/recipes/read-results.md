# Recipe: read what a Maps Search run produced

For `mapsSearch`, the read surface is **`GET /jobs/{job_id}/results`** — full
stop. This is a Maps-only, single-stage flow, so the one-shot job results carry
everything. **IDAP is not the read surface for standalone Maps runs** (that's a
common wrong turn — see the gotcha below).

## The read → `/jobs/{job_id}/results`

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

The response is the flat job envelope:

```yaml
success: true
job_id: ...
type: spiderMaps
status: completed
data:
  query: "plumbers in Berlin"
  results_count: 18
  businesses: [ ... ]      # the listings — see results-shape.md
  metadata: { ... }        # search settings + post-processing stats
```

- **Status codes:** `200` completed (data ready) · `202` still queued/processing
  (poll again, ≥3–5s) · `410` failed/cancelled (read `error_message`) · `404`
  unknown/not yours.
- `?format=yaml` (or `md`) saves 40–76% of tokens over JSON on large lists — use
  it. See [surfaces-and-auth.md](../../../references/surfaces-and-auth.md).
- The businesses are at `data.businesses[]`; `data.results_count` is the count.

## Batch reads

- **Path A (loop of singles):** read each `job_id` with `GET /jobs/{job_id}/results`.
- **Path B (flow facade group):** `GET /run-groups/{run_group_id}` gives the
  group's per-run status; then read each `run_id` (= a `job_id`) with
  `GET /jobs/{run_id}/results`. `GET /runs/{run_id}` also returns the stored
  run + its `output`.

See [run-batch.md](run-batch.md).

## Gotchas

- **IDAP `/idap/businesses` is NOT populated by a standalone Maps Search run.**
  IDAP's normalized `businesses` records are written by the **campaign /
  lead-chain** path (`campaign_service` / `workflow_orchestrator`), not by a
  standalone `spiderMaps` job. A standalone run lands in `jobs.results` (read via
  `/jobs/{job_id}/results`) — querying `GET /idap/businesses?campaign_id=…` for a
  Maps Search `job_id` returns nothing. Read the job results.
  (See [learnings/2026-05-26-standalone-maps-not-in-idap](../learnings/2026-05-26-standalone-maps-not-in-idap/artifacts/what-we-learned.md).)
- **`202` is not "done with no results"** — it means the worker is still going.
  Poll until `200`. Don't report an empty list off a `202`.
- **Don't parse `/jobs/{id}/status` for data.** `status` reports progress;
  `/results` carries the businesses.
- **`results_count` can be lower than `max_results`** legitimately — the area
  may simply have fewer matching businesses, or Google served a reduced
  (compact) format under anti-bot pressure. Empty/short ≠ failure; see
  [results-shape.md](results-shape.md).
- **Tenant isolation:** you only ever read your own `client_id`'s jobs.

## Verify

- `GET /jobs/{job_id}/results` returns `status: completed` with a
  `data.businesses[]` array.
- `data.results_count == len(data.businesses)`.
- Run [scripts/verify-maps-complete.sh](../scripts/verify-maps-complete.sh)
  `<job_id>` for a one-shot audit of how many listings carry a website / phone /
  coordinates, with a clear "still processing" vs "zero results" vs "complete"
  verdict.
