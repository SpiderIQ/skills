# Recipe: watch a run with live events (listen, don't poll)

You submitted a flow — a single job or a campaign — and you want to know the
moment it's done so you can read the results. **Do not poll `GET /status` on a
timer.** Open the live event stream, react to events as they arrive, and do
**exactly one** read from the durable sink when the run reaches its terminal
event. The full stream surface (endpoint, auth, vocabulary, snippets) is in
[references/events-stream.md](../references/events-stream.md) — this recipe is the
decision rule for *using* it.

## The rule (memorize this)

1. **Open the stream BEFORE you submit.** The stream has no replay — an event
   published before you subscribe is gone. Subscribe first, then submit, so you
   can't miss the early events.
2. **Filter to your run.** Add `?campaign_id=<id>` (campaign) or `?job_id=<id>`
   (single job) so the server only sends you the events that matter.
3. **React to events** as they arrive — don't re-request status.
4. **On the terminal event, do EXACTLY ONE read from the durable sink** —
   `getCampaignResults` / `readResources` (IDAP) for a campaign,
   `getJobResults` for a single job. One read, not a loop.
5. **NEVER poll on a timer.** A spin loop burns your tokens and rate limit and
   does not make workers finish faster.

## Which event is "terminal"?

| You ran… | Subscribe with | Terminal event | Then read |
|---|---|---|---|
| a **campaign** (`createCampaign`) | `?campaign_id=<id>` | **`campaign.terminal`** (always fires) | `getCampaignResults` / `readResources` (IDAP, by `campaign_id`) |
| a **single job** (`searchLeads`, `scrapeSite`, `verifyEmails`, `findPeople`, `researchCompany`) | `?job_id=<id>` | **`job.completed`** (or `job.failed`) for *your* `job_id` | `getJobResults` / `GET /jobs/{job_id}/results` |

### The campaign terminal nuance (do not get this wrong)

For a campaign, key on **`campaign.terminal`** — it is the **definitive** end
signal and **always** fires. The success verdict rides alongside it:

- `campaign.completed` is co-emitted **only** when the verdict is *completed*.
- `campaign.failed` is co-emitted **only** when the verdict is *failed*.
- A **`degraded`** verdict emits **`campaign.terminal` ONLY** — neither alias.

So: **listen for `campaign.terminal`. Read the co-emitted
`campaign.completed`/`campaign.failed` for the verdict — if neither is present,
the verdict is `degraded`.** The verdict is also in the `terminal` field of the
`campaign.terminal` payload (`"completed" | "degraded" | "failed"`).

> **"completed" is a success-rate verdict, NOT "all locations ran."** It means the
> run's `success_pct` cleared your account's `threshold_pct`. Never treat
> *"the campaign stopped"* as *"the campaign succeeded"* — check
> `completed` / `failed` / `total` / `success_pct` in the payload, then read the
> actual records.

## The durability rule (load-bearing — read this)

**SSE is a best-effort NUDGE, not a source of truth.** It's Redis pub/sub with
**no persistence and no replay**. So:

- If you **miss an event** (subscribed late, network blip, proxy dropped the
  connection) → **just read the durable sink.** Your results always land durably
  in IDAP / the results endpoints regardless of whether you saw the event.
- If the **stream drops** (`error`, `onerror`, connection reset) → **don't retry
  in a panic and don't fall back to a poll loop.** Reconnect once if you like, or
  simply do the one durable read. A run that finished while you were disconnected
  is still fully readable.
- **A dropped or missed event is never lost data.** The event told you *when* to
  look; the sink is *what* you look at. Worst case without the stream: you read
  the sink once after a sensible wait. You never lose a result by missing an event.

This is why "open before submit + one read on terminal" is safe: even the
pathological case (you missed the terminal event entirely) degrades to "read the
sink once" — never to data loss, never to a poll loop.

## Map each event → what you do

| Event | What it means | Your action |
|---|---|---|
| `connected` | Stream is open. | Now submit the flow (if you haven't). |
| `job.queued` | A job was accepted. | Nothing — informational. |
| `job.started` | A worker picked it up. | Nothing — informational. |
| `campaign.business.found` | One business row was written. | Optionally update a live count / UI. Don't fetch results yet. |
| `campaign.location.completed` | One location's pipeline finished. | Optionally show progress (`businessesFound` per location). Don't fetch the whole result set per location. |
| `campaign.email.verified` | A verify job inside the campaign finished. | Informational; the counts (`emailsValid`/`emailsRisky`) preview quality. |
| `campaign.vayapin.exported` | A pin was published. | Informational — the pin is live (and permanent). |
| **`campaign.terminal`** | **Campaign reached terminal state — the definitive end.** | **Stop listening. Do ONE read from the durable sink.** Inspect `terminal`/`success_pct` for the verdict. |
| `campaign.completed` | Verdict = completed (rides on the same terminal moment). | Treat as the verdict flavor of `campaign.terminal`. |
| `campaign.failed` | Verdict = failed (below threshold). | Read the sink to see what *did* land; consider `retryFailedLocations`. |
| **`job.completed`** (single run) | **Your single job finished.** | **Stop listening. `getJobResults` once.** |
| `job.failed` (single run) | Your single job errored. | Read `error_message`; resubmit if appropriate. |
| `heartbeat` | Keep-alive (every 30s). | Nothing — proves the stream is healthy. |
| `error` | Stream error (then closes). | Don't poll-loop. Reconnect once or just read the sink (results are durable). |

## WRONG vs RIGHT

❌ **WRONG — submit, then spin on status:**

```python
job = submit_campaign(...)              # got campaign_id
while True:                             # ← tight loop = burns tokens + rate limit
    s = get_status(job.campaign_id)     # ← re-requesting, never faster
    if s.status in ("completed", "failed"):
        break
    time.sleep(2)                       # ← still polling
results = get_campaign_results(job.campaign_id)
```

✅ **RIGHT — subscribe first, react, one read on terminal:**

```python
stream = open_stream(campaign_id=expected_id)   # 1. subscribe BEFORE submit
job = submit_campaign(...)                       # 2. submit
for event_type, data in stream:                  # 3. react to pushed events
    if event_type == "campaign.terminal":        #    definitive end (always fires)
        verdict = data["terminal"]               #    completed | degraded | failed
        break
results = get_campaign_results(campaign_id)      # 4. EXACTLY ONE durable read
```

(If `stream` dies before the terminal event, the `for` ends → fall straight to
step 4. The read is durable; you lose nothing.)

## Gotchas

- **Subscribe before submit, or accept the firehose.** If you submit first and
  subscribe second you may miss the early `job.queued`/`campaign.created` events
  (no replay). For the *terminal* event this rarely bites — campaigns take long
  enough that you'll be connected — but the safe order is stream-first.
- **`?campaign_id=` does not deliver per-job events.** Campaign filters match
  `campaign.*` only; the underlying `job.*` events carry no campaign id. That's
  fine — you want `campaign.terminal`, not the per-job churn. To watch a single
  standalone job, use `?job_id=`.
- **Don't read results on every `campaign.location.completed`.** That's just a
  poll loop wearing a costume. Show progress from the event payload if you must;
  fetch the full result set **once**, on `campaign.terminal`.
- **Mixed key casing in payloads.** When reading fields yourself, use
  `data.campaignId ?? data.campaign_id` — campaign progress events use camelCase,
  the terminal events use snake_case. (The server filter handles both; only your
  own field reads need the guard.) See
  [references/events-stream.md](../references/events-stream.md).
- **The token is in the URL.** `?token=client_id:api_key:api_secret` — never log
  the full stream URL.

## Verify

- You opened the stream and saw `connected` **before** submitting.
- You did **not** call `GET /status` in a loop.
- You reacted to `campaign.terminal` (campaign) or `job.completed` (single job),
  then read the durable sink **once**.
- On a `degraded` campaign you still terminated (you keyed on `campaign.terminal`,
  not on `campaign.completed`).
