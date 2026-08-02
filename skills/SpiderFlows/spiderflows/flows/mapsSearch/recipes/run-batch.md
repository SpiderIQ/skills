# Recipe: scrape Google Maps for many queries (batch)

The same Maps-only search run across a **list** of queries in one logical batch.
Use this for "every plumber in Berlin, Hamburg, and Munich", "scrape these 30
search terms", or any explicit list of independent Maps searches.

This is *batch*, not *campaign*. Each entry is a full, independent search with
its own `search_query` (place embedded). There is **no country/region fan-out**
here — if the user wants "every plumber in all of Germany" (locations generated
from a country + filter), that's the lead chain's campaign mode
([maps-site-verify-vayapin/recipes/run-campaign.md](../../maps-site-verify-vayapin/recipes/run-campaign.md)),
not this flow.

There are two honest ways to run a batch of Maps searches; pick by whether you
want server-side grouping.

## Path A — loop the single endpoint (recommended; correct validation)

The simplest and most accurate batch: submit one single job per query and keep
the `job_id`s. Each job is validated against the real `SpiderMapsJobPayload`
(`max_results ≤ 100`, bogus fields rejected), runs independently, and is read
back on its own.

```bash
for q in "plumbers in Berlin" "plumbers in Hamburg" "plumbers in Munich"; do
  curl -s -X POST "https://spideriq.ai/api/v1/jobs/spiderMaps/submit" \
    -H "Authorization: Bearer $SPIDERIQ_PAT" \
    -H "Content-Type: application/json" \
    -d "{\"payload\": {\"search_query\": \"$q\", \"max_results\": 20}}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["job_id"])'
  sleep 7   # pace it — see "Rate limits & caching" below
done
```

Collect the printed `job_id`s, poll each (≥3–5s; or watch the account-wide SSE
stream and correlate by `job_id`), then read each with
`GET /jobs/{job_id}/results`. See [read-results.md](read-results.md).

## Path B — one grouped batch via the Flows facade

`mapsSearch` is registered as a flow with `supported_modes: [single, batch]`. The
flow facade groups a list into one run-group you can track as a unit:

```bash
curl -X POST "https://spideriq.ai/api/v1/flows/mapsSearch/run" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": [
      { "search_query": "plumbers in Berlin",  "max_results": 20 },
      { "search_query": "plumbers in Hamburg", "max_results": 20 },
      { "search_query": "plumbers in Munich",  "max_results": 20 }
    ]
  }'
```

Response (`201`): `{ "run_group_id": "...", "flow_slug": "mapsSearch", "dispatch_type": "spiderMaps", "mode": "batch", "run_ids": ["...","...","..."] }`.
Each `run_id` **is** a `job_id` — poll/read them exactly like single runs
(`GET /jobs/{run_id}/results`), or pull the group aggregate with
`GET /run-groups/{run_group_id}`.

- **1–500 inputs** per batch (422 outside that range).
- **Caveat — looser validation.** The facade validates each input against the
  flow's marketing schema, not `SpiderMapsJobPayload`. That schema lists
  `location` / `country_code` and allows `max_results` up to 500 — but the Maps
  worker **ignores** `location` / `country_code` and the single-job pipeline is
  built around `max_results ≤ 100`. So keep the place inside `search_query` and
  `max_results ≤ 100` even here, or you'll silently get a query that ignored your
  location. (See [learnings/2026-05-26-location-goes-in-the-query](../learnings/2026-05-26-location-goes-in-the-query/artifacts/what-we-learned.md).)

## Which path?

- **Just need the data** → Path A. Simplest, validated correctly, one `job_id`
  per query.
- **Want a single handle for the whole list** (a dashboard run-group, one id to
  track progress across all queries) → Path B.

Either way, each query is an independent Maps job: one can return zero results or
hit a Google cooldown while the rest succeed. Read each one's results; don't
assume a uniform outcome across the list.

## Rate limits & caching (read before looping)

- **~10 jobs/min per VPS.** A tight submission loop hits the rate limit (429).
  Pace it — ~6–7s between submits keeps you under, or honor the
  `X-RateLimit-Reset` header. See
  [learnings/2026-05-26-rate-limit-and-queue](../learnings/2026-05-26-rate-limit-and-queue/artifacts/what-we-learned.md).
- **Queue cap: 10,000 Maps jobs.**
- **24-hour dedup cache.** Two identical queries in your list (or a re-run within
  24h) collapse to the **same** cached `job_id` (`from_cache: true`) — you won't
  get two fresh scrapes. De-dupe your list first, or set `test: true` to force
  fresh runs. See
  [learnings/2026-05-26-job-dedup-24h-cache](../learnings/2026-05-26-job-dedup-24h-cache/artifacts/what-we-learned.md).
- **Cost:** ~1 credit per query, zero AI tokens — but it's per query, so a
  200-query batch is ~200 credits + 200 browser sessions. Size it.

## Gotchas

- **Each entry must carry its place in `search_query`.** There's no shared
  top-level `location`/`country_code` that applies to the list.
- **Cost/time scale linearly with the list × `max_results`.** A 100-query batch
  at `max_results: 100` is a lot of browser work and real exposure to Google
  rate limiting — size it, and prefer the default `max_results: 20` for wide lists.
- **Partial results per query are normal** — see
  [learnings/2026-05-26-compact-format-dummy-values](../learnings/2026-05-26-compact-format-dummy-values/artifacts/what-we-learned.md)
  and [results-shape.md](results-shape.md).

## Verify

- **Path A:** the number of `job_id`s you collected matches the list length.
- **Path B:** `len(run_ids)` matches the list length; `GET /run-groups/{id}`
  reports `total` equal to it.
- Each job/run reaches `completed`; read each with `GET /jobs/{id}/results`.
