# Run a sequence (Class-B campaign)

*Author a multi-step campaign, attach a source, preview every step — then hand
activation to a human.* Read this before touching any `sendCreateCampaign` /
`sendAddStep` / `sendAddVariant` call.

A **broadcast** is one message fanned out to a resolved audience, once. A
**campaign** is an ordered SEQUENCE of messages sent 1:1 to leads who enrol
continuously over days, each lead carrying its own cursor. Different objects,
different tables, different lifecycles. `references/run-a-broadcast.md` is the
other one; do not mix them.

```
  1. shell        sendCreateCampaign    ← a DRAFT. Holds NO copy.
  2. touches      sendAddStep           wait_days = the gap BEFORE this step
                  sendAddVariant        the copy. A/B arms live here.
  3. capacity     sendAttachSource      which mailboxes MAY carry it
  4. check        sendPreviewStep       EVERY step. Read unresolved_merge_tags.
  5. hand over    ⛔ you stop here      a human arms it in the dashboard
  6. if wrong     sendPauseCampaign     you may always stop mail
```

## The one rule that matters

**A draft is not a send, and an active campaign is not one you armed.**

You can build every part of a campaign and read every part back. You cannot
activate one — there is no method, no MCP tool and no working CLI verb, because
the route is cookie-only server-side. Arming a sequence means mailing real
people unattended for as long as leads keep enrolling, and that is a decision a
human takes in a session.

So the anti-default that bites: composing a beautiful five-touch sequence,
attaching a source, and telling the user *"the campaign is live."* It is not.
It is a draft, and it will stay one until a person clicks Activate. Say
**"ready to activate"**, never "running", and name what is still missing.

The mirror image is also true and less obvious: `sendPauseCampaign` and
`sendStopCampaign` **are** yours to call. You may always stop mail and never
start it. A safety verb an agent cannot reach is a safety verb nobody uses at
3am.

## WRONG / RIGHT

### Filling in a subject on a follow-up step

```
WRONG
  sendAddStep { campaign_id, wait_days: 3, variant: {
      subject_template: "Following up on my last email",   ← starts a NEW thread
      body_md: "Just circling back…" } }

RIGHT
  sendAddStep { campaign_id, wait_days: 3, variant: {
      subject_template: "",                                 ← stays in the thread
      body_md: "Just circling back…" } }
```

An empty subject is **load-bearing**, not unfinished. It means *omit the Subject
header and reply into this lead's existing thread*, letting the sender prefix
`Re:`. A non-empty subject starts a new thread — so a "helpful" subject on every
follow-up turns one conversation into five unrelated cold emails, and nothing
anywhere reports a problem. `sendPreviewStep` returns `continues_thread: true`
with `subject: null` for the correct version. That null is the right answer, not
a missing value to fill in.

### Reporting a campaign ready without previewing it

```
WRONG
  sendCreateCampaign → sendAddStep ×4 → sendAttachSource
  "Your 4-step sequence is ready to activate."

RIGHT
  sendCreateCampaign → sendAddStep ×4 → sendAttachSource
  sendPreviewStep {step_index: 0} … {step_index: 3}        ← every step
  read unresolved_merge_tags and postal_address on each
  "Ready to activate, with two things to fix first: …"
```

`sendPreviewStep` is the only place two silent failures are visible:

| Field | What it means | Why nothing else catches it |
|---|---|---|
| `unresolved_merge_tags: ["first_name"]` | that tag renders **empty** on a live send | the placeholder is emitted, the row is well formed, the provider accepts it — the only symptom is *"Hi ,"* in mail already sent |
| `postal_address: ""` | the workspace has recorded no physical address | with `include_postal_address` on (the default) the send is **refused** at queue time, days after you said it was ready |

⚠️ **Today, every CRM merge tag except `email` resolves to empty on a real
send.** The send tier stores one contact field. Until enrolment carries the
rest, `{{first_name}}` in a live campaign ships as nothing. Either write copy
that does not depend on it, or tell your human explicitly.

### Editing a running sequence

```
WRONG
  sendUpdateVariant on an ACTIVE campaign        → 409 not_editable
  …then deleting the campaign to "start clean"   → 409 not_draft, and you would
                                                    have destroyed its history

RIGHT
  sendPauseCampaign  →  edit  →  ask a human to reactivate
```

The 409 names the fix. A campaign's *settings* (name, schedule, stop condition,
compliance toggles) **can** be patched while active — changing a send day does
not re-aim anyone's cursor. Its *sequence* cannot: leads hold a `step_index`, so
inserting or removing a step re-aims a live cursor at copy that lead was never
on its way to.

### Trying to close a gap in step_index

Don't. After `sendDeleteStep` the later steps keep their indices — `0, 2, 3`
is correct and healthy. The sequence reads in order, so a gap is invisible to
the send path, and renumbering is exactly the cursor-shift the editing gate
exists to prevent.

## Gotchas

- **`wait_days` is the gap BEFORE the step.** Step 0 is normally 0 (the first
  touch). "3 days later" is `wait_days: 3` on the NEXT step, not on this one.
  `sendGetCampaign` returns the cumulative `day_offset` per step (D+0 · D+3 ·
  D+10) — read that back rather than adding it up yourself.
- **`active_days` is the CAMPAIGN clock, not the mailbox's.** ISO weekdays,
  1=Mon..7=Sun. The mailbox has its own independent send window and days, and
  **both** must allow a day. See `references/two-clocks.md`.
- **A step with no variant cannot be armed.** Pass `variant` on `sendAddStep`
  and you never hit it.
- **A campaign with no attached source cannot be armed** — and neither can one
  whose every attached source is still `warming`. Those are two different
  refusals (`no_sources` and `no_active_sources`) because they need two
  different fixes. ⚠️ `sendAttachSource` **succeeds** on a warming mailbox: the
  attach is legitimate, the campaign just cannot be armed yet. The send loop
  claims `active` sources only, so this is the state that looks healthiest and
  sends nothing — the campaign says active, the mailbox says warming, and both
  are telling the truth. `sendListSources` shows the state; `sendPromoteSource`
  arms it (see `references/pool-and-reputation.md`).
- **`stop_condition` has no `'open'`.** Deliberately. Apple MPP fires open
  pixels with no human involved, so a sequence that stops on an open stops on
  noise. Use `reply` (default) or `click`.
- **`sendStopCampaign` is terminal for everyone**, including the human. Reach
  for `sendPauseCampaign` unless the user has said the sequence is finished.
- **Deleting is draft-only.** Anything that has run must be stopped; deleting
  would strip its leads' sessions of the sequence that explains what they were
  sent.

## Verify

Before you report anything back:

```
sendGetCampaign {campaign_id}
  → status: "draft"           ← if you built it, it is a draft. Say so.
  → steps[]: every step has ≥1 variant
  → sources[]: NOT empty
  → span_days: matches what the user asked for

sendListSources
  → at least one ATTACHED mailbox is state "active"
    (all "warming" = the campaign arms and sends nothing)

sendPreviewStep on EVERY step
  → unresolved_merge_tags: []  (or reported to the user by name)
  → postal_address: non-empty  (or reported as a blocker)
  → follow-up steps: continues_thread == true
```

Then say: *"Ready to activate — someone with dashboard access needs to open
Mail → Campaigns → <name> → Activate."* Plus anything from the checks above
that is still outstanding.

## See also

- `references/two-clocks.md` — the campaign clock vs the mailbox clock, and why
  the send gap is not campaign-editable.
- `references/pool-and-reputation.md` — source states, and why `warming` is not
  claimable.
- `references/branches.md` — stopping or re-aiming ONE lead when they reply,
  bounce or go quiet. ⚠️ Authoring only — nothing executes a branch yet.
- `references/run-a-broadcast.md` — the OTHER object: one message, many people,
  once.
- `learnings/2026-08-18-activation-is-not-in-the-agent-surface/` — why no
  activate method exists, with provenance.
