# Send, reply, forward — the async write path

Sending is the one place SpiderMail differs from every email API you know
(Resend, Postmark, SendGrid all return a message id synchronously). Here a send
is a **job**: you submit, get a `job_id`, and the SMTP send happens in a worker
seconds later. Get this wrong and you'll report "sent" when it only queued — or
double-send on a retry.

## Steps

1. **Confirm the recipient with the user** (the HARD-GATE). Email is irreversible.
2. **Write `body_text` in markdown** — SpiderMail converts it to professional
   HTML. Don't hand-write HTML unless you must override.
3. **Submit** `POST /jobs/spiderMail/submit` with a `payload`. You get a `job_id`
   and status `queued`.
4. **Poll** `get_job_status` (≥3–5 s apart) until `completed` or `failed`. ONLY
   then tell the user it was delivered.
5. **Develop with `test: true`** — routes to the test queue, exercises the whole
   flow, delivers nothing.

## WRONG

```bash
# WRONG: reporting success off the submit response
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/jobs/spiderMail/submit" -H "Content-Type: application/json" \
  -d '{"payload":{"action":"send","from_email":"alice@acme.com","to":["bob@lead.com"],
       "subject":"Quick question","body_text":"Hi Bob…"}}'
# → { "job_id": "...", "status": "queued" }   ← QUEUED, not sent. Do NOT say "email sent".

# WRONG: replying with the RFC Message-ID header string
-d '{"payload":{"action":"reply","from_email":"alice@acme.com",
      "reply_to_message_id":"<orig-789@lead.com>","body_text":"Thanks!"}}'
# → does not thread. reply_to_message_id must be the NUMERIC message id.

# WRONG: pasting a credential into the body
-d '{"payload":{"action":"send", ... ,"body_text":"Here is the key: sk_live_abc123…"}}'
# → BLOCKED by the outbound credential scanner; the job fails. Never put secrets in a body.
```

## RIGHT

```bash
# RIGHT: send, then poll to confirm
JOB=$(curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/jobs/spiderMail/submit" -H "Content-Type: application/json" \
  -d '{"payload":{"action":"send","from_email":"alice@acme.com","to":["bob@lead.com"],
       "subject":"Quick question","body_text":"Hi **Bob**,\n\nNoticed your team is hiring —\nworth a quick chat?\n\n— Alice"}}' \
  | jq -r .job_id)
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/jobs/$JOB/status?format=yaml"   # poll until status: completed

# RIGHT: reply in-thread with the numeric id (auto-threads via In-Reply-To/References)
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/jobs/spiderMail/submit" -H "Content-Type: application/json" \
  -d '{"payload":{"action":"reply","from_email":"alice@acme.com",
       "reply_to_message_id":84213,"body_text":"Thanks Bob — Tuesday 2pm works."}}'

# RIGHT: forward to a new recipient (needs both `to` and the numeric source id)
-d '{"payload":{"action":"forward","from_email":"alice@acme.com","to":["carol@acme.com"],
      "reply_to_message_id":84213,"body_text":"Carol — can you take this one?"}}'

# RIGHT: dry-run during development
-d '{"payload":{"action":"send","from_email":"alice@acme.com","to":["bob@lead.com"],
      "subject":"Test","body_text":"hello","test":true}}'   # routes to the test queue, delivers nothing
```

## Field rules per action

| action | requires | notes |
|---|---|---|
| `send` | `from_email`, `to`, `subject`, `body_text` | new email |
| `reply` | `from_email`, `reply_to_message_id`, `body_text` | subject + threading inherited; `reply_all` optional |
| `forward` | `from_email`, `to`, `reply_to_message_id`, `body_text` | passes the original along with your note |

- `from_email` MUST be a registered mailbox (`listMailboxes`).
- `body_text` is required for all three (it's the markdown source + the plain-text
  fallback). `body_html` is an optional override.
- `cc` is an array. `reply_all` only applies to `reply`.

## Drafting first (composeAssist)

`composeAssist` drafts/improves copy but **does not send**:

```bash
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/compose/assist" -H "Content-Type: application/json" \
  -d '{"action":"write","subject":"Intro to Acme","context":"cold outreach to a hiring manager","tone":"friendly"}'
# → suggested text. Show it, get user approval, THEN sendEmail with it.
```

`action`: `write` (new, from `context` as the brief) · `rewrite`/`expand`/`shorten`/`formal`/`casual`/`fix_grammar` (transform the text in `context`).

## Verify

```bash
# Full round-trip on the test queue: submit → job completes, nothing delivered
JOB=$(curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/jobs/spiderMail/submit" -H "Content-Type: application/json" \
  -d '{"payload":{"action":"send","from_email":"alice@acme.com","to":["bob@lead.com"],
       "subject":"smoke","body_text":"hi","test":true}}' | jq -r .job_id)
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" "https://spideriq.ai/api/v1/jobs/$JOB/status?format=yaml"
```

## Gotchas

- **201 = queued, not sent.** Always poll the job. (`learnings/2026-06-10-queued-is-not-sent/`)
- **No idempotency key.** A retried submit double-sends (Postmark has the same
  limitation — they recommend app-side dedup). Submit once; if unsure whether the
  first submit landed, check `list_jobs` before re-submitting.
- **reply_to_message_id is numeric**, not the RFC Message-ID header.
- **Secrets in the body fail the send** (outbound credential scanner).
- Markdown in `body_text` → HTML automatically; set `body_html` only to override.
