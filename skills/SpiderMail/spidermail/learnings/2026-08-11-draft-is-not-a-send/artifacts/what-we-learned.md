# A draft is not a send — and cancel is not an undo

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

Four calls in the broadcast flow look like they might send mail. **One does.**

```
  sendCreateBroadcast                 → 201  draft.        Sends nothing.
  sendCreateBroadcast + scheduled_at  → 201  draft.        Sends nothing.
  sendUpdateBroadcast                 → 200  draft.        Sends nothing.
  sendQueueBroadcast                  → 202  ON THE WIRE.  ← the only one
```

The one that catches agents is the second. `scheduled_at` is a real field, it
takes an ISO timestamp, and its description says "hold fan-out until this
instant" — so it reads exactly like a scheduler. It is not. It **records intent
on the draft**. Nothing is enqueued, no job exists, and no timer is running. An
agent that composes a broadcast, sets `scheduled_at` to next Monday, and tells
the user *"scheduled — it'll go out Monday morning"* has sent **nothing**, and
the user finds out on Tuesday.

## Why it's built that way

It mirrors the admin composer's draft→publish split, and the split is load-bearing
rather than ceremonial: the draft stores the audience as a **query**, not a
resolved address list. Reopening it re-resolves against current data, so an
audience that grew between composing and sending is not silently under-sent. A
draft that auto-fired on a timestamp would freeze that decision at compose time.

## The mirror image: cancel is not an undo

```
sendCancelBroadcast → 204
```

This abandons a broadcast **that has not been fanned out**. Rows already in the
send queue are *deliberately* not withdrawn — pulling messages out from under
the running send loop is a different, riskier operation than abandoning a draft.

So the honest phrasing is *"stopped it from starting"*, never *"cancelled the
send"*. If a user asks you to stop a broadcast after `sendQueueBroadcast`
returned, tell them plainly what is and is not stoppable. Implying a recall that
did not happen is worse than the bad news, because they will act on it.

## The symmetric error: reading success as failure

Having learned to fear the queue call, the next mistake is treating its **normal**
output as a problem:

| Field | Reads as | Actually |
|---|---|---|
| `already_enqueued: 340` | "it double-sent!" | a **resumed** fan-out. `uq_send_queue_batch_recipient` makes the enqueue idempotent per (broadcast, address), so a retry after an interruption fills only the gaps. |
| `provider_configured: false` | "it broke" | rows are queued and **hold** at `queued` until credentials exist. A deliberate dormant state, reported honestly instead of faked as sent. |

Both are the system working. Reporting either as an error sends a user chasing a
fault that isn't there — and worse, invites a "fix" like re-queueing.

The refusals that **are** real: `422 no_audience` (zero deliverable recipients),
`422 no_sources` (no active sending source), and `503` when the suppression list
cannot be read.

## Do not retry the 503

The suppression check **fails closed**. A 503 means nobody could confirm whether
these addresses had already hard-bounced or complained. A retry that happens to
succeed mails a list nobody checked — which is precisely the send that damages a
domain's reputation. Escalate it; don't loop on it.

## How to apply

1. After `sendCreateBroadcast`, say **"draft saved"** — never "scheduled", never
   "queued", even when `scheduled_at` is set.
2. Before `sendQueueBroadcast`, confirm three numbers with the user: the
   deliverable count (`sendPreviewAudience`), the sending sources, and the drain
   estimate (`sendGetCapacity`). It is the only irreversible call in the flow.
3. After it, read `enqueued` / `already_enqueued` / `provider_configured`
   together before characterising the outcome.
4. Never describe `sendCancelBroadcast` as an undo.

## Related

- `learnings/2026-06-10-queued-is-not-sent/` — the same shape one layer down:
  `sendEmail` returns a queued **job**, not a delivered email. Acceptance is
  never the outcome, at either layer.
- `references/run-a-broadcast.md` — the full flow with the hard gate.
