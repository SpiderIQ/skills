# Live events — the SSE stream (push, instead of polling)

Every flow you run emits **live events** to a single per-account stream. Open it
once and you get a push notification the moment a job is queued, a worker picks
it up, a business is found, a location finishes, and — the one that matters most
— the moment a campaign reaches its **terminal** state. This is the alternative
to polling `GET /jobs/{id}/status` in a loop.

> **SSE is a NUDGE, not the truth.** The stream is best-effort Redis pub/sub with
> **no replay** — an event published while you are not connected is gone. Your
> results are never on the stream; they land durably in IDAP / the results
> endpoints. So treat events as "go look, it's ready" signals. If you miss one or
> the stream drops, just read the durable sink — **a dropped event is never lost
> data.** The recipe that puts this into practice is
> [recipes/watch-a-run.md](../recipes/watch-a-run.md).

## The endpoint

```
GET https://spideriq.ai/api/v1/events/stream?token=<client_id>:<api_key>:<api_secret>
Accept: text/event-stream
```

- **Auth is in the QUERY string, not a header.** Browsers' `EventSource` (and
  most SSE clients) can't set an `Authorization` header, so the PAT goes in
  `?token=client_id:api_key:api_secret` — the same three-part credential you'd
  otherwise send as `Authorization: Bearer …`.
  Because the secret is in the URL, **never log the full stream URL** or echo it
  into chat.
- The stream is **account-wide (client-scoped)** by default — you receive events
  for *every* job and campaign on your account, not just the one you started.
- It stays open indefinitely; a `heartbeat` every 30s keeps it alive through
  proxies and load balancers.
- `GET /api/v1/events/status` reports stream health + active subscription count
  (this one uses a normal `Authorization: Bearer` header).

## Server-side filter — `?campaign_id=` / `?job_id=` (post-A2, 2026-05-27)

You can ask the server to deliver only the events you care about, so you don't
have to filter the firehose client-side:

```
# only this campaign's events (+ connected/heartbeat)
GET /api/v1/events/stream?token=<pat>&campaign_id=camp_abc123

# only this job's events (+ connected/heartbeat)
GET /api/v1/events/stream?token=<pat>&job_id=550e8400-e29b-41d4-a716-446655440000
```

Semantics:

| Filter | You get |
|---|---|
| *(none)* | **Everything** — the full client firehose (default, unchanged, backwards-compatible). |
| `?campaign_id=X` | Only events whose payload carries campaign `X` (`campaign.*`), plus `connected`/`heartbeat`. |
| `?job_id=Y` | Only events whose payload carries job `Y` (`job.*`), plus `connected`/`heartbeat`. |
| both | **Union** — events matching *either* id (no single event carries both). |

Two things to know about the filter:

1. **`connected`, `heartbeat`, and `error` always pass**, regardless of filter —
   dropping them would break the stream handshake / keep-alive.
2. **Per-job events carry no campaign id.** `job.queued/started/completed/failed`
   have only a `job_id` in their payload — they do **not** carry a `campaign_id`.
   So `?campaign_id=X` delivers the campaign-level events
   (`campaign.created/business.found/location.completed/vayapin.exported`, and the
   terminal `campaign.terminal/completed/failed`) but **not** the per-location job
   churn underneath. To watch a single standalone job, filter by `?job_id=`.

## The event vocabulary

These are the events a flow run emits. Connection-control events first, then the
ones that track real work.

### Connection control (always delivered)

| Event | When | `data` payload |
|---|---|---|
| `connected` | On connect — the handshake. | `{ client_id, message }` |
| `heartbeat` | Every 30s keep-alive. | `{ timestamp }` |
| `error` | The stream hit an error (then closes). | `{ message }` |

### Per-job lifecycle (snake_case keys; **no** campaign id)

| Event | When | `data` payload |
|---|---|---|
| `job.queued` | A job was accepted and queued. | `{ job_id, type, created_at }` |
| `job.started` | A worker picked it up. | `{ job_id, worker_id, started_at }` |
| `job.completed` | A job finished successfully. | `{ job_id, processing_time, results_count }` |
| `job.failed` | A job errored. | `{ job_id, error_message }` |

For a **single** (non-campaign) run — `searchLeads`, `scrapeSite`, `verifyEmails`,
`findPeople`, `researchCompany` — `job.completed` for *your* `job_id` is your
terminal signal. Read results with `getJobResults` / `GET /jobs/{job_id}/results`.

### Campaign progress (Live-Theater events; **camelCase** `campaignId` keys)

| Event | When | `data` payload (key fields) |
|---|---|---|
| `campaign.created` | A campaign was created and fanned out. | `{ campaignId, query, countryCode, totalLocations, … }` |
| `campaign.business.found` | One business row was written (one per business). | `{ campaignId, businessName, domain, placeId, lat, lng }` |
| `campaign.location.completed` | One location's pipeline finished. | `{ campaignId, campaignLocationId, locationName, countryCode, businessesFound, sitesCrawled, emailsVerified }` |
| `campaign.email.verified` | A SpiderVerify job within the campaign finished. | `{ jobId, campaignId, domain, emailsTotal, emailsValid, emailsRisky, emailsInvalid }` |
| `campaign.vayapin.exported` | A VayaPin pin was published (if vayapin is enabled). | `{ campaignId, businessName, placeId, vayapinUrl, vayapinStatus, pinName }` |

### Campaign terminal — the definitive "done" signal (**snake_case** `campaign_id` keys)

This is the load-bearing part. A campaign ends with these events:

| Event | Fires when | `data` payload (key fields) |
|---|---|---|
| **`campaign.terminal`** | **ALWAYS**, the moment the campaign reaches a terminal state. **This is the definitive end signal — key on it.** | `{ campaign_id, client_id, terminal, completed, failed, total, success_pct, threshold_pct, … }` |
| `campaign.completed` | Co-emitted **only** when the verdict is *completed* (the run passed the success threshold). | same payload |
| `campaign.failed` | Co-emitted **only** when the verdict is *failed* (below threshold). | same payload |

**Read this carefully — it changes how you interpret "done":**

- `campaign.terminal` is the **single authoritative end-of-campaign signal** and
  it **always** fires. `campaign.completed` and `campaign.failed` are
  *convenience aliases* that piggyback on the same authoritative event for the two
  unambiguous outcomes.
- The verdict lives in the `terminal` field of the payload: `"completed"`,
  `"degraded"`, or `"failed"`.
- **A `degraded` verdict emits `campaign.terminal` ONLY** — neither
  `campaign.completed` nor `campaign.failed`. Degraded means "the campaign passed
  enough to count, but below a clean completion" (partial success). If you only
  listened for `campaign.completed`, you would **wait forever** on a degraded run.
- **"completed" is a success-rate VERDICT, not "all locations ran."** It means the
  run's `success_pct` cleared the per-account `threshold_pct`. Do **not** read
  "the campaign stopped" as "every location succeeded" — inspect `completed` /
  `failed` / `total` / `success_pct` in the payload to know the real shape, then
  read the actual records from the durable sink.

> **The rule:** listen for `campaign.terminal`. Read the co-emitted
> `campaign.completed` / `campaign.failed` to learn the verdict (neither present →
> the verdict is `degraded`). On `campaign.terminal`, do exactly one read from the
> durable sink. See [recipes/watch-a-run.md](../recipes/watch-a-run.md).

### Other flow events you may see

| Event | When | `data` payload (key fields) |
|---|---|---|
| `playbook.company.completed` | A company-intel / playbook company finished. | `{ playbookId, companiesFound, sitesCrawled, emailsFound, emailsVerified }` |
| `resource.flagged` | A flag was added/removed on an IDAP resource (e.g. you marked a lead `qualified`). | `{ resource_type, resource_id, flags_added, flags_removed, flagged_by }` |

## A note on key casing (it is genuinely mixed)

The event families grew independently, so the **same logical id is spelled
differently** depending on the emitter:

| Family | id key spelling |
|---|---|
| `campaign.created/business.found/location.completed/vayapin.exported` | **`campaignId`** (camelCase) |
| `campaign.terminal/completed/failed` | **`campaign_id`** (snake_case) |
| `job.queued/started/completed/failed` | `job_id` (snake) — **and carry no campaign id at all** |

The **server filter handles both spellings** — `?campaign_id=X` matches whichever
key the event happens to use, so you don't worry about casing when *subscribing*.
But when you **read fields out of an event's `data`** yourself, be defensive:
`data.campaignId ?? data.campaign_id`. (This is a known SpiderIQ wire quirk, not a
bug to report.)

## SSE wire framing

Each event is two lines plus a blank line:

```
event: campaign.terminal
data: {"campaign_id":"camp_abc","client_id":"cli_x","terminal":"completed","completed":18,"failed":2,"total":20,"success_pct":90.0,"threshold_pct":70.0}

```

- The `event:` line is the event **type** (use it to route in `EventSource`).
- The `data:` line is the JSON **payload only** — the inner `data` dict described
  in the tables above. (The wrapper's `timestamp` is not sent on the wire.)
- A blank line terminates each event.

## Copy-paste: JavaScript (`EventSource`)

```javascript
const token = `${clientId}:${apiKey}:${apiSecret}`;          // PAT in the query
const url = `https://spideriq.ai/api/v1/events/stream`
          + `?token=${encodeURIComponent(token)}`
          + `&campaign_id=${campaignId}`;                     // server-side filter
const es = new EventSource(url);

es.addEventListener("connected",  () => console.log("stream open"));
es.addEventListener("campaign.location.completed", (e) => {
  const d = JSON.parse(e.data);
  console.log(`location done: ${d.locationName} (+${d.businessesFound})`);
});

// The definitive end signal — ALWAYS fires.
es.addEventListener("campaign.terminal", (e) => {
  const d = JSON.parse(e.data);
  console.log(`campaign ${d.terminal}: ${d.completed}/${d.total} (${d.success_pct}%)`);
  es.close();                       // stop listening
  // → now do EXACTLY ONE read from the durable sink (getCampaignResults / IDAP).
});

es.onerror = () => {                // dropped? don't panic — read the sink instead.
  es.close();
};
```

## Copy-paste: Python (`httpx`, streaming + minimal SSE parse)

`httpx` has no built-in SSE decoder, so parse the `event:` / `data:` lines
yourself (or use the `httpx-sse` package). Filter server-side with the query.

```python
import json, httpx

pat = f"{client_id}:{api_key}:{api_secret}"           # PAT in the query
url = "https://spideriq.ai/api/v1/events/stream"
params = {"token": pat, "campaign_id": campaign_id}    # server-side filter

def watch(url, params):
    event_type = None
    with httpx.stream("GET", url, params=params, timeout=None) as r:
        r.raise_for_status()
        for line in r.iter_lines():
            if line.startswith("event:"):
                event_type = line[len("event:"):].strip()
            elif line.startswith("data:"):
                data = json.loads(line[len("data:"):].strip())
                if event_type == "campaign.terminal":
                    # definitive end — ALWAYS fires (completed | degraded | failed)
                    print(f"{data['terminal']}: "
                          f"{data['completed']}/{data['total']} "
                          f"({data['success_pct']}%)")
                    return data            # stop; then read the durable sink ONCE
                elif event_type == "campaign.location.completed":
                    print(f"location done: {data.get('locationName')}")
            # blank line = end of one event; loop continues

try:
    verdict = watch(url, params)
except httpx.HTTPError:
    verdict = None        # stream dropped — fine; read the sink anyway (it's durable)
```

## See also

- [recipes/watch-a-run.md](../recipes/watch-a-run.md) — the decision rule that uses this stream (open-before-submit, react, one final read, never poll).
- [references/run-modes-and-progress.md](run-modes-and-progress.md) — poll-vs-stream and realistic per-flow timing.
- [references/reading-results.md](reading-results.md) — the durable IDAP read surface you go to on the terminal event.
