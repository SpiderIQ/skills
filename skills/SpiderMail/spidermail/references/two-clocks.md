# Two clocks: the campaign's and the mailbox's

*Why a campaign that "sends Mon–Fri" can still send nothing on Monday, and why
you cannot fix the send gap from the campaign.* Read before setting
`active_days`, `starts_on` or `new_leads_per_day`.

A message leaves only when **both** clocks allow it. They belong to different
objects, they are edited in different places, and they are stored in different
shapes — so it is easy to set one, verify it, and be wrong.

```
  CAMPAIGN clock                          MAILBOX clock
  (send_campaign — you set this)          (send_source_capacity — you do not)
  ─────────────────────────────           ────────────────────────────────────
  active_days   ISO 1=Mon..7=Sun          send_days_mask   a BITMASK
  timezone      IANA zone                 send window      per-mailbox hours
  starts_on     first enrolment day       min_gap_seconds  spacing between sends
  new_leads_per_day  enrolment throttle   daily_cap        ceiling per day
                                          warm-up state    ramps the effective cap
        │                                        │
        └──────────────  AND  ────────────────────┘
                          │
                    a message leaves
```

## The rule

**The campaign schedules; the mailbox paces.** The campaign clock decides
*whether today is a day this sequence acts at all* and *how many new leads may
enter*. The mailbox clock decides *whether this mailbox will carry a message
right now, and how soon after the last one*.

Neither overrides the other and neither is a default for the other.

## WRONG / RIGHT

```
WRONG   user: "send Mon-Fri, 30 a day"
        sendCreateCampaign { active_days: [1,2,3,4,5], new_leads_per_day: 30 }
        "Done — 30 a day, Monday to Friday."

RIGHT   sendCreateCampaign { active_days: [1,2,3,4,5], new_leads_per_day: 30 }
        sendListSources                    ← what will actually carry it
        "Enrolling 30 new leads a day, Mon-Fri. Note the attached mailbox is
         still warming with an effective cap of 8/day, so real throughput is
         8/day until it ramps."
```

`new_leads_per_day` is an **enrolment** throttle, not a send rate. Thirty leads
entering a five-step sequence is up to 150 messages over the following weeks,
released at whatever the pool's warm-up-aware pacing allows. Reporting the
enrolment number as a send rate is the most common way a campaign's output
surprises the person who asked for it.

## The trap that produces no error at all

`active_days` is **ISO weekday numbers**: `[1,2,3,4,5]` is Mon–Fri.
`send_days_mask` on the mailbox is a **bitmask** — a different encoding of the
same idea, on a different object. They are not interchangeable, and passing one
where the other belongs is accepted by the type system in both directions.

Conflating them lets a campaign schedule a day its mailbox refuses. Nothing
errors: the campaign is "active", the mailbox is healthy, and mail simply does
not go out on the days you promised.

## What you cannot change from here

The **send gap** (`min_gap_seconds`), the **daily cap**, the **send window** and
the **warm-up ramp** are properties of the MAILBOX, deliberately not of the
campaign. That is not a missing feature.

If a campaign could set its own gap, a sequence would be able to opt out of the
pacing that protects the sending domain every other campaign on that mailbox
shares — and reputation damage is not recoverable by turning the setting back
down. `sendListSources` reads the real numbers; changing them is
`references/pool-and-reputation.md`, on the source, on purpose.

## Reading it back

```
sendGetCampaign  → active_days · timezone · starts_on · new_leads_per_day
                                  ↑ the campaign clock
sendListSources  → state · daily_cap · effective cap · min_gap_seconds
                                  ↑ the mailbox clock — the one that paces
sendGetCapacity  → the two combined, as a drain estimate
```

When a user asks "how fast will this go out?", the answer comes from the
MAILBOX side. When they ask "which days does it run?", both — and if the two
disagree, say so, because the intersection is what actually happens.

## See also

- `references/run-a-sequence.md` — the end-to-end authoring recipe.
- `references/pool-and-reputation.md` — source states, caps, and warm-up.
