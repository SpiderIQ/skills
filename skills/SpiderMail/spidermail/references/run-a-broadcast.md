# Run a broadcast on your own pool

*The end-to-end recipe: add domain → verify → source joins pool → compose →
paced send → watch reputation.* Read this before driving the whole flow.

`sendEmail` puts **one** message through **one** mailbox. This is the other
thing: a broadcast fanned out across the tenant's **sending pool**, paced by a
warm-up-aware engine, under a domain the tenant owns.

```
  1. add domain      sendCheckDomain      publish SPF/DKIM/CNAME, re-check until verified
  2. enroll          sendEnrollDomain     your provider key, stored encrypted → source bound
  3. read the pool   sendListSources      warm-up state + daily cap + min gap
  4. compose         sendPreviewAudience  who, and what the guards removed
                     sendPreviewBroadcast what it looks like rendered
                     sendCreateBroadcast  ← a DRAFT. Still nothing sent.
  5. size it         sendGetCapacity      audience_size → drain_days
  6. SEND            sendQueueBroadcast   ← 🚨 the only irreversible call
  7. watch           sendGetBroadcast     progress; then sendGetDeliverability
```

Each step is a separate reference where it earns one:
`references/byo-sending-domain.md` (steps 1–2) and
`references/pool-and-reputation.md` (steps 3 + 7). This file is the spine.

## The one rule that matters

**A draft is not a send.** `sendCreateBroadcast` creates a draft.
`scheduled_at` **records intent on the draft — it does not queue it.**
`sendQueueBroadcast` is the only call that puts mail on the wire, and rows it
enqueues are **not withdrawn** by a later `sendCancelBroadcast`.

So the anti-default that bites: composing a broadcast, setting
`scheduled_at: "2026-09-01T09:00:00Z"`, and telling the user "it's scheduled,
it'll go out Monday." **Nothing will go out.** The draft sits there. Conversely,
calling `sendQueueBroadcast` "to see what happens" mails real people.

## Steps

### 1–2. Get a sending domain into the pool

Full detail in `references/byo-sending-domain.md`. The short version:

```
sendCheckDomain  { domain: "mg.example.com" }
  → verified: false, and each failed check's `expected` names the exact record
  → user publishes it, you re-check (up to 20 checks/min/tenant)
  → verified: true
sendEnrollDomain { mailbox_id: 42, domain: "mg.example.com", api_key: "<theirs>" }
  → 201, source bound, state reported UNCHANGED (still `warming`)
```

`sendEnrollDomain` **binds an already-enrolled source; it never creates one.**
A mailbox with no capacity row is refused `409 source_not_enrolled` — that is an
operator-provisioning step, not something this surface does.

### 3. Read the pool before you promise anything

```
sendListSources
```

Read three fields per source and stop: `state`, `effective_daily_cap`,
`min_gap_seconds`. See `references/pool-and-reputation.md` for what each state
means and which of them are un-claimable.

### 3b. 🔴 ARM the source — the step whose absence looks like a broadcast bug

**If every source reads `warming`, stop here.** `warming` is not claimable: the
send loop only ever claims `state = 'active'`, so a perfectly-formed broadcast
queued against a warming pool refuses with **422 `no_sources`** at step 6 —
several steps away from the actual cause.

```
sendPromoteSource { mailbox_id: 42 }
  → promoted: true, state: "active", effective_daily_cap: 8   ← day 1 of the ramp
```

Promotion **re-stamps the ramp to today**, so a freshly-armed source starts at
day 1 (normally 8/day) whatever its history. Size step 5 against
`effective_daily_cap`, never `daily_cap`.

A **409** here is an answer, not an error to retry: `warmup_not_matured` and
`reputation_input_required` mean the ramp or the reputation samples are not there
yet, and calling again cannot change either. Report `detail` and stop. Needs the
`admin` role, and this route cannot waive the reputation gate — that is an
operator act on a different route, by design.

### 4. Compose

**Size the audience first** — it is free and it tells you what the guards took:

```
sendPreviewAudience { mode: "crm", email_status: "valid" }
  → { matched: 5200, suppressed: 180, duplicates: 44, invalid: 12,
      deliverable: 4964, missing_values: { first_name: 310 },
      suppression_checked: true }
```

Report the subtractions, don't hide them: `suppressed` is hard-bounced and
complained addresses being kept out of a new send — that is the deliverability
guard working. `missing_values.first_name: 310` means 310 people would receive
"Hi ," — fix the copy or set `require_first_name: true`, don't ship the gap.

⚠️ `suppression_checked: false` makes the whole count **provisional**. The queue
path refuses outright in that state (503) rather than mailing an unchecked list.

**Check the render** — server-side, with the same renderer fan-out uses:

```
sendPreviewBroadcast { subject_template: "{{first_name}}, …", body_md: "…",
                       sample: { email: "…", first_name: "Dana" } }
  → { subject, body_html, body_text }
```

**Then save the draft:**

```
sendCreateBroadcast { name, subject_template, body_md,
                      audience: { mode: "crm", email_status: "valid" },
                      source_mailbox_ids: [42] }
  → 201 { id: "…", status: "draft" }
```

The draft stores the audience as a **query**, not a resolved address list — so
it re-resolves at fan-out and an audience that grew in the meantime is not
silently under-sent.

### 5. Size the send

```
sendGetCapacity { audience_size: 4964, mailbox_ids: "42" }
  → { sources: 1, daily_capacity: 400, capacity_remaining_today: 400,
      drain_days: 12.4, first_dispatch_at: "…", provider_configured: true }
```

**This is the number the user actually needs.** "4,964 recipients" means nothing
to them; "about 12 days at your current warm-up cap" is a decision they can
make. Tell them before you queue, not after.

`provider_configured: false` ⇒ nothing can leave regardless of capacity.

### 6. Send — the irreversible step

<HARD-GATE name="confirm-before-queueing-a-broadcast">
`sendQueueBroadcast` puts REAL MAIL on the wire to REAL PEOPLE, and rows already
enqueued are NOT withdrawn by `sendCancelBroadcast`. Before calling it, state
back to the user and get explicit confirmation of: (a) the **deliverable count**
from `sendPreviewAudience`, (b) the **sending sources** it will go out from, and
(c) the **drain estimate** from `sendGetCapacity`. Never call it to "test" the
flow — `sendPreviewAudience` and `sendPreviewBroadcast` are the dry-runs, and
they persist nothing.
</HARD-GATE>

```
sendQueueBroadcast { broadcast_id: "…" }
  → 202 { enqueued: 4964, already_enqueued: 0, suppressed: 180,
          duplicates: 44, provider_configured: true, first_dispatch_at: "…" }
```

**Two results that look like failures and are not:**

| Field | Looks like | Actually |
|---|---|---|
| `already_enqueued > 0` | double-send / partial failure | a **resumed** fan-out. The enqueue is idempotent per (broadcast, address), so a retry after an interruption fills only the gaps. |
| `provider_configured: false` | broken | rows are queued and **hold** at `queued` until credentials exist. A deliberate dormant state, reported honestly. |

**Three refusals that are real:**

| Status | Code | Means |
|---|---|---|
| 422 | `no_audience` | the query resolved to zero deliverable recipients |
| 422 | `no_sources` | no **active** sending source. Usually the pool is all `warming` — go back to step 3b and `sendPromoteSource`. Nothing is wrong with the broadcast. |
| 503 | suppression unavailable | the suppression list could not be read — it **fails CLOSED** |

⚠️ **Do not retry the 503.** It means nobody checked the suppression list. A
retry that happens to succeed mails addresses that may have already complained.

### 7. Watch it

```
sendGetBroadcast { broadcast_id }
  → status: "queued",  progress: { queued, sending, sent, failed, skipped, total }
```

`status` is the **authoring** lifecycle — it sits at `queued` for the whole
fan-out. Delivery lives in `progress`, aggregated from the send queue at read
time (never cached, so poll it rather than trusting an earlier copy).

Once volume has landed, move to reputation:
`sendGetDeliverability` → `sendGetDeliverabilityTimeseries` →
`sendListUndeliverable`. See `references/pool-and-reputation.md`.

## Cancelling

`sendCancelBroadcast` abandons a broadcast that has **not** been fanned out. It
is **not an undo**: anything already enqueued still sends. If a user asks you to
"stop the broadcast" after queueing, say plainly what is and is not stoppable —
implying a recall that did not happen is worse than the bad news.

## Gotchas

- **`scheduled_at` does not schedule a send.** It records intent on the draft.
  Only `sendQueueBroadcast` enqueues. (The pace still governs after that.)
- **`email_status: "any"`** mails addresses SpiderVerify never confirmed — the
  single most common cause of a bounce-rate breach. The default `"valid"` is
  deliberate; changing it is a decision to surface, not a default to flip.
- **A queued broadcast can't be edited.** `sendUpdateBroadcast` returns
  `409 not_draft`, because the edit would change what the composer shows without
  changing one already-queued message.
- **Reads take `member`, writes take `admin`.** A read-only token gets 403 on
  enroll / create / update / cancel / queue. That is the boundary working.
- **No method takes a `client_id`,** and none ever will: tenancy resolves
  server-side from your PAT. If you find yourself wanting to pass a tenant id,
  you are on the wrong surface.

## Verify

Before reporting a broadcast as sent:

1. `sendGetBroadcast` → `progress.sent` is rising and `progress.queued` falling.
2. `progress.failed` is not climbing in step with `sent` — if it is, go to
   `sendListUndeliverable` and read the actual reasons before continuing.
3. `sendGetDeliverability` after meaningful volume → `rates.bounced_pct` under
   the `thresholds.bounce_safe_pct` line, `rates.complained_pct` under
   `thresholds.complaint_limit_pct`.

A fan-out that reports `enqueued: N` is **enqueued**, not delivered. Same rule
as `sendEmail`: the acceptance is not the outcome.

## The other surfaces

Every method here is also a CLI verb and an MCP tool. The MCP tool name is the
snake_case of the method name (`sendCheckDomain` → `send_check_domain`), so no
mapping table is needed. On the CLI:

```
spideriq send domain verify <domain>      # sendCheckDomain
spideriq send domain add <domain>         # sendEnrollDomain
spideriq send sources list                # sendListSources
spideriq send broadcast create|update|get|list|cancel
spideriq send broadcast preview           # sendPreviewBroadcast
spideriq send broadcast preview audience  # sendPreviewAudience
spideriq send broadcast capacity          # sendGetCapacity
spideriq send broadcast queue <id>        # sendQueueBroadcast — SENDS MAIL
spideriq send reputation summary|timeseries|undeliverable
```
