## verify-email-deliverability

The "is this email real?" skill. 4 tool calls — submit, status, results, list. Backed by SpiderVerify worker (10 instances).

### What this skill does

- **`submit_email_verify`** — accepts a list of emails, returns `job_id`. Batches up to thousands per call.
- **`get_verify_results`** — per-email verdict: `valid` / `invalid` / `accept_all` / `unknown`, with sub-codes (syntax, MX, SMTP-RCPT-TO).
- **`get_verify_status`** — progress + ETA.
- **`list_verify_jobs`** — history.

### Verification pipeline

Each email goes through 5 checks in order, exiting at the first definitive result:

1. **Syntax** — RFC 5322 compliance
2. **DNS / MX** — does the domain resolve? Does it have MX records?
3. **Disposable / role detection** — known disposable domains, role accounts (info@, sales@) flagged
4. **SMTP-level RCPT-TO** — TCP connect to MX, issue MAIL FROM + RCPT TO, read response without sending DATA
5. **Catch-all detection** — if domain accepts all addresses, mark as `accept_all` (still risky, partial bounce risk)

### Typical workflows

- **Pre-send hygiene** — agent verifies a freshly-scraped email list, drops invalids before sending. Cuts bounce rates from ~30% (raw scrape) to <5%.
- **Re-verify** — list ages out; agent re-verifies before re-using a contact list older than 30 days.
- **Bulk dedup** — agent verifies + dedups in one batch, writing the cleaned list to the campaign.

### Why this matters

ESPs penalize senders with high bounce rates. Verifying before send is much cheaper than getting throttled by your sender reputation system after a bad campaign.
