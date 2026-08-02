---
name: submit-press-release
description: >
  Distribute a client's press release over the newswire. Use when the user
  wants to submit / send out / distribute / publish / wire / put out a press
  release or announcement — "send this press release", "distribute our launch
  announcement", "put this on the wire", "publish our funding news", "get this
  release out to press". One async submit (title + body, plus optional
  summary / category / tags / press contact), then poll for the live published
  URL and the provider's wire report. This is WIRE distribution, not hosting a
  newsroom page on the client's own site (that's the SpiderPublish
  publish-skills surface) and not email outreach (that's mail-skills).
version: "0.1.0"
category: communication
requires_auth: true
---

# submit-press-release

Wire-distribute a press release the client has already written.

```
 release copy (title+body)          async job                 live wire
 ───────────────────────►  submitPressRelease  ──►  poll  ──►  published_url
      (you confirm)              → job_id        getJobStatus   + wire_report_url
                                                 getJobResults
```

One paid, irreversible submission per release. Submit is **async** — it returns
a `job_id`, never a URL. The `published_url` appears only in `getJobResults`
after the wire goes live (minutes, not seconds).

## Approach

1. **Confirm the copy** — title + body are what the client approved (see the HARD-GATE).
2. **`submitPressRelease`** → `job_id`. Wrap the release under `payload`.
3. **Poll `getJobStatus`** every few seconds until `completed` / `failed`.
4. **`getJobResults`** → `published_url` + `wire_report_url` (or a typed `error`).

<HARD-GATE name="confirm-before-you-wire">
Every `submitPressRelease` is a **paid, irreversible newswire distribution** —
once the wire goes live the release is public and cannot be recalled. Before you
submit: confirm the exact `title` and `body` are the client-approved copy, and
that you are not re-submitting a release that is already in flight or published.
Re-running submit sends (and bills) a SECOND distribution — it does not "retry"
the first. When unsure whether a prior submit is still running, poll its
`job_id` with `getJobStatus` first; do NOT submit again.
</HARD-GATE>

## Rules (Non-Negotiable)

- **ASYNC:** `submitPressRelease` returns a `job_id`, **NEVER** a `published_url`.
  The URL only exists after the wire publishes — read it from `getJobResults`.
  Treating the submit response as "done + here's the link" surfaces a link that
  does not exist yet.
- **WRAP under `payload`:** the body is `{"payload": {"title": ..., "body": ...}, "priority": 5}`.
  A flat `{"title": ..., "body": ...}` **422s** — `title`/`body` live inside `payload`.
- **NEVER re-submit to "retry":** each submit is a separate paid distribution.
  A failed job reports its reason in `getJobResults.error`; fix the copy, then
  submit a NEW release — do not blind-retry.
- **Poll politely:** `getJobStatus` no faster than every 3-5 s. Wire distribution
  takes minutes; hammering the endpoint wins nothing.

## Decision tree — pick a reference

| The user wants to… | Read |
|---|---|
| Send / distribute / wire a press release | `references/submit-release.md` |
| Check whether a release has gone live yet / get the published URL | `references/read-results.md` |

## The submit payload (quick map) → references/submit-release.md

`payload.title` (req) · `payload.body` (req) · `payload.summary` · `payload.category`
· `payload.tags[]` (≤25) · `payload.contact{name,email,phone}` · `payload.provider`
(`prnow`) · `payload.scheduled_release_at` (ISO 8601, omit for ASAP) ·
`payload.test` (route to local test queue). Top-level `priority` (0-10, default 5).

## Auth & base

`https://spideriq.ai/api/v1`, Bearer `client_id:api_key:api_secret` (a PAT;
CLI/MCP load it from `~/.spideriq/credentials.json`). Every GET accepts
`?format=yaml` / `?format=md` for token-efficient reads.

## References (loaded on demand)

- **`references/submit-release.md`** — Steps/Gotchas/Verify for `submitPressRelease`. **Always read before the first submit.**
- **`references/read-results.md`** — polling `getJobStatus` + reading `getJobResults` (the published URL, wire report, and the `error` shape).

## See also

- **publish-skills** (`@spideriq/publish-skills`) — host a **newsroom / press
  page on the client's OWN SpiderPublish site**. Complements this skill: wire the
  release here, host the archive there.
- **mail-skills** (`@spideriq/mail-skills`) — email outreach. A press release is a
  newswire deliverable, not an email blast.
- `learnings/` — institutional memory. **Starting points, not ground truth** —
  verify against current API behaviour before relying on them.
