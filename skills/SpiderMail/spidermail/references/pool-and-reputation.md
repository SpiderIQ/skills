# The sending pool and its reputation

*Steps 3 and 7 of `references/run-a-broadcast.md`.* Read before promising a
send rate, and before answering "is our sending healthy?".

Four reads, no writes. This surface **reports**; it does not act.

```
  sendListSources                  pacing state + caps + identity, per source
  sendGetDeliverability            the funnel and its rates, for a window
  sendGetDeliverabilityTimeseries  the same rates, day by day
  sendListUndeliverable            the individual bounces/complaints/failures
```

## The pool

```
sendListSources { range: "7d" }
→ sources[]: { mailbox_id, email_address, state, daily_cap, effective_daily_cap,
               sent_today, min_gap_seconds, timezone, warmup_started_on,
               next_earliest_send_at, send_window_start/end, send_days_mask,
               source_uuid, sending_domain, tracking_domain,
               complaint_pct, bounce_pct }
```

**A registered mailbox is not automatically a sending source.** Only mailboxes
with a pacing row appear here. A tenant whose mail you can *read* may have an
empty pool — that is a correct, honest answer, not a failure.

### The seven states

| `state` | Claimable | Means |
|---|---|---|
| `warming` | yes, at the ramp | new source ramping up. `effective_daily_cap` < `daily_cap`. |
| `active` | yes | at full cap |
| `paused` | no | reputation breaker fired |
| `blocked` | no | stopped hard |
| `auth_failed` | no | the provider rejected the credentials |
| `retiring` | no | past its `retire_after` date — takes no new mail while the queue drains |
| `retired` | no | drained; safe to tear down SPF/DKIM |

**Re-entry is operator-gated and has no API here, by design.** Resuming a
reputation pause, clearing `auth_failed`, un-retiring — none of it is offerable
from this surface. If a user asks you to un-pause a source, say it needs an
operator; do not hunt for a method that would do it.

### Reading capacity honestly

`daily_cap` is the nominal ceiling. **`effective_daily_cap` is today's real
one** — below `daily_cap` while warming, computed in SQL by
`send_effective_daily_cap()` so the ramp has exactly one definition. Quote the
effective number.

And `state` is not the only thing that stops a source: a `retire_after` date in
the past excludes it from claims on its own, so an `active`-looking source can
legitimately be sending nothing. `send_window_start`/`end` + `send_days_mask`
(bit 0 = Monday; 31 = Mon–Fri) gate it further — a source outside its window
will not dispatch at all, whatever its cap says.

## Reputation

```
sendGetDeliverability { range: "7d", source_id: "…" }   # source_id optional
→ { range, since, totals{…}, rates{…}, thresholds{…}, ingest{…},
    has_events, opens_are_estimates: true }
```

### WRONG / RIGHT

**WRONG** — scoring engagement on opens:

> "42% open rate — the campaign is performing well."

**RIGHT** — Apple Mail Privacy Protection and proxy preloading fire open pixels
with no human involved. `opens_are_estimates` is **always true**. Use
`clicked` / `unique_clickers`:

> "1,240 delivered, 96 unique clickers (7.7%). Opens are inflated by privacy
> proxies and aren't a reliable signal."

**WRONG** — rendering a null as zero:

> "Bounce rate: 0%. Complaint rate: 0%. Healthy."

**RIGHT** — a `null` rate means a **zero denominator** (nothing dispatched), not
a zero rate. And on a source, a `null` `complaint_pct` has two different causes:
with `metrics_available: true` the source dispatched nothing in the window; with
it `false` the aggregation could not run at all. Neither is "0%".

> "No volume dispatched in the last 7 days, so there are no rates to report yet."

**WRONG** — reading a quiet feedback door as clean delivery:

> "`has_events: false` — no bounces, no complaints. All good."

**RIGHT** — `has_events: false` with `ingest.provider_webhook: "dormant"` means
the **signing key is unset and the feedback door is shut**. You are not seeing
zero problems; you are seeing nothing at all.

### The denominators

Everything in `rates` is a percentage of **`totals.dispatched`**.
`totals.accepted` is a raw provider-event count and is normally `0` — it is an
*input* to `dispatched`, never a denominator. Do not divide by it.

There is **no `replied` event type**. Replies are an IMAP signal, not a
message event — if a user asks for reply rate, that is the mailbox surface
(`getInbox` / `searchMail`), not this one.

### The thresholds are returned, not assumed

`thresholds` comes back on both the summary and the timeseries:
complaint limit **0.30%**, bounce safe **2%**, bounce critical **5%**. Compare
against the returned values rather than hardcoding them — and note
`reputation_paused_value` is a **fraction** (0.00300) while `complaint_pct` is a
**percentage** (0.30). Rendering them side by side needs the conversion.

## Trend vs totals

`sendGetDeliverabilityTimeseries` answers a different question from the summary:
**is this one bad batch, or a domain going bad?**

```
sendGetDeliverabilityTimeseries { range: "30d" }
→ buckets[]: { day, dispatched, accepted, delivered, bounced, complained,
               bounce_pct, complaint_pct }
```

The series is **sparse, not gap-filled** — only days with events or dispatches
appear, and a day with no volume comes back with `null` rates. Plotting a `null`
as `0` invents a good day that never happened.

## The individual failures

```
sendListUndeliverable { range: "7d", kind: "bounce", limit: 25 }
→ items[]: { id, created_at, recipient, event_type, severity, provider,
             source_id, suppress_recipient }, total, next_cursor
```

- `severity: "permanent"` is the hard bounce; `"temporary"` is retryable.
- **This does not suppress anything.** `suppress_recipient` is a flag the
  suppression builder consumes; writing suppression is a different surface.
- `next_cursor` is opaque **and relative to the active filter set** — changing
  `kind` or `range` invalidates it. Page with the same filters or start over.

## Gotchas

- **`?format=yaml|md` does NOT work on the send tier.** That serializer switch is
  implemented per-endpoint on the `/mail/*` routes; no send route declares it, and
  FastAPI **silently ignores** an undeclared query param rather than rejecting it
  — so you get JSON back believing you asked for YAML. These four reads *do*
  support **`?format=llm`**, which is a different feature: it splices a `guidance`
  block (what to read, what to call next, the pitfalls) into the response.
- **`range` on `sendListSources` windows the reputation rates only.** Pacing
  state and caps are always current, whatever range you pass.
- **A NULL `tracking_domain` on a BYO source means link tracking is OFF.** It
  does **not** inherit the platform tracking host — so there are no click or
  open events for that source at all, and its engagement columns are structurally
  empty rather than bad.
- **`ingest.sender` and `ingest.imap_feedback` are different services.**
  One reports the batched sender, one the bounce/DSN poller. Never read one for
  the other.

## Verify

Before telling a user their sending is healthy:

1. `has_events: true` — otherwise you are reporting on an empty event store.
2. `ingest.provider_webhook: "active"` — otherwise the feedback door is shut and
   bounces are not arriving at all.
3. `rates.bounced_pct` < `thresholds.bounce_safe_pct` **and**
   `rates.complained_pct` < `thresholds.complaint_limit_pct`, with both rates
   non-null.
4. No source in the pool sitting at `paused`, `blocked` or `auth_failed`.

If (1) or (2) fails, the honest answer is *"we can't see delivery outcomes yet"*
— not *"no problems found."*
