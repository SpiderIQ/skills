# Connect a mailbox — and know whether it actually works

Registering a mailbox and having a working mailbox are two different events.
Since 2026-08-04 the API says so out loud: `createMailbox` proves the
credentials before it saves anything, and every mailbox carries a derived
`health` field that is computed from what the poller observed rather than from
what someone asserted at INSERT.

Read this before connecting a mailbox for a user, and before reporting to them
that their mail is set up.

## Steps

1. **`listMailProviders`** — read the presets. Each entry publishes the hosts,
   ports, sent-folder name, whether an app password is required, and the
   username shape each protocol expects. You do not pass anything from here to
   `createMailbox`; the same presets are applied server-side. Read it so you can
   tell the user *what to go and generate* before you ask for a secret.

2. **`createMailbox`** — send `email_address`, `provider`, `imap_password` and
   `smtp_password`. Omit hosts, ports and usernames unless the server is
   genuinely non-standard; the preset fills them, and that is the only way to
   get iCloud's asymmetric username shape right.

3. **Handle the outcome — 201 and 422 are both normal.** A 422 is not an
   exception path here; a wrong app password is the single most likely thing
   that happens, and this endpoint is designed to catch it.

4. **Re-read `health` before you tell the user it works.** A successful create
   returns `health: "connecting"`, never `"active"`. Call `listMailboxes` after
   the poller has had a cycle to confirm it reached `active`.

5. **Say how much history you asked for.** A new mailbox imports its last 500
   messages, not everything. Tell the user that, and see the next section
   before you reach for `sync_scope: "all"`.

## The 422: `MAILBOX_VERIFICATION_FAILED`

Read `error.code`. Everything you need is inside the `error` object — this is
the platform error envelope, the same shape every 4xx on this API uses.

```
POST /mail/mailboxes  →  422
{
  "error": {
    "code": "MAILBOX_VERIFICATION_FAILED",
    "message": "...Nothing was saved.",
    "suggested_action": "Resubmit with skip_verification=true to ...",
    "imap_ok": false,          "imap_error": "<the server's own text>",
    "smtp_ok": true,           "smtp_error": null,
    "verification_unavailable": false
  }
}
```

> ⚠️ **Changed in 0.9.0 (card UI.3).** This block previously documented a flat
> body with a lowercase `error` string and a `retry_hint` key. That shape was
> never actually emitted — the endpoint raised it as a bare dict, which the
> error-envelope middleware stringified, so what really went over the wire was
> a **Python dict repr** inside `error.message`. The endpoint now emits the
> envelope above for real. If you cached the old shape, re-read it: `error` is
> an OBJECT, the slug moved to `error.code` in upper case, and `retry_hint` is
> now `suggested_action`.

**Nothing was saved.** There is no half-created mailbox to clean up, and
re-sending the same request is not a retry of a partial write.

`verification_unavailable` is the field that decides what you do next, and it is
the only one that should change your behaviour:

| `verification_unavailable` | What it means | What to do |
|---|---|---|
| `true` | **We** could not complete the check — the provider was unreachable from our side | Offering `skip_verification=true` is honest. Say plainly that the mailbox will be saved unverified. |
| `false` | The mail server **actively rejected** the credentials | Fix the password. Re-sending with `skip_verification=true` registers a mailbox you have already been told is broken. |

`imap_ok` / `smtp_ok` tell you which protocol to talk about. Both are probed;
one can pass while the other fails, and on the preset providers that usually
means the password is right and a port/TLS override is wrong — not that the
account is half-working.

### WRONG / RIGHT

```
WRONG   422 → immediately resubmit with skip_verification=true
        You have converted a clear error into a mailbox that will sit at
        `connecting` forever and ingest nothing. The user is now worse off
        than before, because it LOOKS registered.

RIGHT   422 → read verification_unavailable.
        false → report which protocol failed and what to fix.
        true  → offer "save it anyway, unverified" and name that trade-off.
```

## What the probe does and does not prove

It proves **authentication** — that these credentials open an IMAP session and
an SMTP session. It does **not** prove the mailbox can deliver mail to a
recipient, and it does not prove a poll has ever run. Do not report "your
mailbox is working and ready to send" on the strength of a 201.

## How much mail comes in: scope and cadence

*Added 0.10.0 (card S.1). Before it, every mailbox ingested its entire history
because that was the only behaviour that existed.*

Two independent settings, on both `createMailbox` and `updateMailbox`:

| Setting | Values | Default |
|---|---|---|
| `sync_scope` | `last_n` · `since_date` · `all` | `last_n`, count **500**, on a NEW mailbox |
| `poll_interval_seconds` | `60`–`86400` | null = the platform 300s tick |

The three scopes are mutually exclusive and the server rejects a mixture:
`last_n` takes `sync_scope_n` and not `sync_since_date`; `since_date` takes
`sync_since_date` and not `sync_scope_n`; `all` takes **neither**.

### WRONG / RIGHT

```jsonc
// WRONG — "be thorough". This asks for the entire mailbox.
{ "email_address": "…", "provider": "gmail", "sync_scope": "all", … }

// RIGHT — the default is already the right answer; say nothing.
{ "email_address": "…", "provider": "gmail", "imap_password": "…", … }

// RIGHT — a deliberate, user-approved wider window.
{ …, "sync_scope": "since_date", "sync_since_date": "2026-01-01" }
```

**What `all` actually costs.** Roughly 100 messages per 5-minute cycle —
~28,800 a day, so about **3.5 days for a 100,000-message mailbox**, stored in
full. On Gmail it is a live rate-limit hazard, not a theoretical one. Ask the
user before choosing it.

**`sync_scope_n` is an upper bound, not an exact count.** The starting UID is
derived from the folder's UIDNEXT and UIDs are sparse wherever mail was
deleted, so you may receive fewer than N — never more. A mailbox holding 480
messages against `last_n: 500` is correct, not broken.

### Re-scoping later

`updateMailbox` changes both settings on a live mailbox. **Any scope change
rewinds it**: the resolved floor is cleared and the read watermarks reset, so
the next cycle re-resolves from scratch under the new scope.

That is deliberate rather than incidental. The poller always walks *forward*
and applies the floor as `max(watermark, floor)`, so once a watermark has
passed the floor, lowering the floor alone changes nothing — "widen the scope
and it backfills" would be a silent no-op that looked like it worked.

- It **re-walks**, so it spends provider bandwidth again (bounded by the same
  100-per-cycle cap).
- It **deletes nothing and duplicates nothing**. Re-ingest is idempotent on a
  global `UNIQUE(message_id)`, and narrowing only stops the poller reaching
  further back — mail already stored stays stored.

🔴 **The defaulting rule inverts between the two calls.** On `createMailbox`,
`sync_scope: "last_n"` with no count means 500. On `updateMailbox` the same
request is a **422** — a PATCH cannot distinguish "use the default" from
"leave it alone", so it refuses to guess. Always send `sync_scope_n`
explicitly when updating.

**To back off a rate-limited provider without re-walking anything**, send
`poll_interval_seconds` *alone*. Cadence-only changes do not rewind. Note it
can only make a mailbox poll *less* often: the global tick is the scheduler's
resolution, so the effective cadence is `max(interval, 300s)` and a value
under 300 buys nothing.

## The five health states

`health` is on the `createMailbox` and `listMailboxes` responses, alongside
`health_detail` — one plain-English sentence you can show a non-technical user
verbatim.

| `health` | Meaning |
|---|---|
| `active` | Polled recently, no error. **The only green state.** |
| `connecting` | Enabled, but no poll has ever completed. New mailboxes and `skip_verification` mailboxes start here. |
| `error` | The last poll failed — read `poll_error_cause` and `poll_error_action`. |
| `stalled` | No poll for over 6 hours (`MAIL_STALE_POLL_HOURS`), and no error was reported. |
| `disabled` | Switched off by the operator. |

## `ever_connected` — read it ALONGSIDE `health`, never instead of it

Every mailbox row also carries **`ever_connected`** (boolean): has this mailbox
ever completed a *successful* poll? It is **orthogonal** to `health` — a fact
the five states cannot carry, and deliberately a boolean rather than a sixth
state so your existing branch table over those five stays correct.

It matters most where `health` is least informative:

| `health` | `ever_connected` | What to do |
|---|---|---|
| `disabled` | `true` | Nothing. A working mailbox someone paused. |
| `disabled` | `false` | **Never commissioned.** Switching it on will not make it connect — fix the credentials first, or delete it. |
| `error` | `false` | It has never once worked. The settings are wrong; this is not a regression. |
| `error` | `true` | A regression — it worked before. Read `health_since` for how long it has been down. |

`false` means *"we hold no evidence this mailbox ever connected"* — a claim
about what we can see, not a claim that it is currently broken. It is derived
from every column that only a successful poll can write, so a mailbox that
worked long ago and was switched off is never falsely reported as never having
connected.

## Gotchas

- **🔴 `is_active` is not health, and reading it is the bug this contract exists
  to remove.** `is_active` is written literally `true` in the INSERT. It means
  "this row is enabled" — the operator's on/off switch, which is a real and
  separate thing. It is `true` for a mailbox that has never connected and for
  one that is timing out on every cycle. **Read `health`.**

- **`error` outranks a fresh `last_poll_at`, deliberately.** The failing path
  stamps the timestamp too, so a mailbox failing every five minutes has a
  perfectly current `last_poll_at`. Ordering freshness first would paint the
  most broken mailbox green.

- **`poll_error IS NULL` is not evidence of health.** The poller *clears* that
  column on a clean run, so a mailbox the loop has silently stopped visiting
  keeps its last successful `NULL` forever. Absence of an error is absence of
  evidence. That is exactly what `stalled` catches — and why `active` requires a
  recent timestamp that only a real poll can write.

- **🔴 The API does not normalise pasted app passwords. It stores the bytes you
  send.** Google presents app passwords in four space-separated groups; Apple
  presents them hyphenated. Nothing in the mail API strips either. **Normalise
  before you send:** remove whitespace from a Google/Workspace app password, and
  do **not** remove hyphens — iCloud's password genuinely contains them. For
  `generic_imap` send the secret byte-for-byte; a password there may legitimately
  contain a space.

  (The dashboard's Add Mailbox form does its own normalisation before it calls
  this API. That is a property of the form, not of the endpoint, and it does
  nothing for you as a direct caller.)

- **One app password, two API fields.** For the preset providers a single app
  password authenticates both protocols, and the dashboard collapses them into
  one input. **The API is unchanged and always takes `imap_password` and
  `smtp_password` separately** — send the same value to both. `generic_imap`
  keeps two genuinely distinct credentials. Do not describe the form's shape as
  the API's shape.

- **`active` does not mean "fully ingested".** Health describes whether the
  *poll cycle* is succeeding, not whether the mailbox's back-catalogue has
  finished importing. **Do not assume every provider syncs cleanly** — a mailbox
  with a large archive can time out on every cycle and ingest nothing, and that
  is a live condition today, not a hypothetical. A mailbox whose poll is failing
  records a `poll_error` and therefore derives as `error`. Report what `health`
  and the message counts actually say; never infer "their mail is imported" from
  a successful registration.

- **`testMailbox` is still the on-demand check.** Registration verifies once, at
  create time. `POST /mail/mailboxes/{email}/test` re-checks IMAP + SMTP later
  without sending anything — use it when a mailbox has drifted to `error` or
  `stalled` and you want a live answer rather than the last poll's verdict.
