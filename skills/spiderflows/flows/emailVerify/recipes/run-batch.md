# Recipe: verify a list of emails (batch)

The same SMTP verifier run across a **list** of addresses in one request — up to
**100** per call. Use this for list hygiene before an outbound blast, cleaning a
CRM export, or validating a trade-show / signup list ("verify these 80 emails",
"clean this list before we send", "which of these addresses are real").

This is *batch*, not *campaign*: you hand it an explicit list of emails. There is
no location fan-out — emailVerify is a **single + batch** flow only.

## Steps

1. **Build the list.** `emails` is an array of up to 100 addresses. The per-call
   options (`check_gravatar`, `check_dnsbl`, `smtp_timeout_secs`, …) apply to
   **every** email in the list — see [verification-options.md](verification-options.md).

2. **Submit** `POST /api/v1/jobs/spiderVerify/submit` — same endpoint as single,
   just `emails` instead of `email`:

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderVerify/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "payload": {
         "emails": [
           "ceo@startup.io",
           "contact@enterprise.com",
           "info@company.org"
         ],
         "check_dnsbl": true
       }
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "spiderVerify", "status": "queued", ... }`.
   One `job_id` covers the whole list.

3. **Watch** — poll `GET /jobs/{job_id}/status` (≥3–5s) or the SSE stream.
   Verification is rate-limited to protect deliverability (~3s/email, ~20/min per
   worker), so **a full list of 100 is roughly 5–8 minutes**, not seconds. Size the
   user's expectation accordingly. See
   [run-modes-and-progress.md](../../../references/run-modes-and-progress.md).

4. **Read** the aggregate: `GET /jobs/{job_id}/results?format=yaml` returns the
   `summary` counts plus one entry per email in `results[]`. See
   [read-results.md](read-results.md).

## Key fields (`SpiderVerifyJobPayload`)

| Field | Default | Notes |
|---|---|---|
| `emails` | — (required here) | 1–100 addresses. Provide `emails` OR `email`, not both. |
| `check_gravatar` | `false` | gravatar probe — applies to every email |
| `check_dnsbl` | `false` | DNSBL check — applies to every email |
| `smtp_timeout_secs` | `45` | per-mailbox timeout, 10–120 (shared) |
| `from_email` / `hello_name` | none | SMTP MAIL FROM / EHLO overrides (shared) |
| `fuzziq_enabled` | client setting | skip addresses already verified for this client (saves quota) |
| `fuzziq_unique_only` | client setting | drop duplicate addresses from the response |
| `priority` | `0` | sibling of `payload`, 0–10 |
| `test` | `false` | routes to the test queue (dev only) |

## Gotchas

- **Hard cap of 100 emails per request.** A list of 250 is three submissions
  (100 + 100 + 50). Sending >100 in one `emails` array is a `422`. (Track the
  three `job_id`s yourself and read each.)
- **Cost + time scale with the list.** Every address is a rate-limited SMTP
  handshake — there is no batching shortcut. Budget minutes for a full list, and
  prefer fewer-but-targeted lists over verifying everything speculatively.
- **`fuzziq_enabled` trims quota AND the response.** Already-verified addresses
  are **removed** from `results[]`, counted under `summary.fuzziq_skipped`, and
  not billed (`billable_count` reflects only the freshly-probed ones). If **every**
  address is already known you get `results: []` with `summary.skipped` and
  `reason: all_already_verified` — a complete run, not a failure. This is the
  dedup *flag* on the request — **not** a separate dedupe call.
- **A row can come back as a per-email error.** If one address errors mid-probe,
  its row is `status: "unknown"`, `sub_status: "error: <message>"`, `score: 0`,
  with only two flags. The batch still completes — treat that row like any other
  `unknown` (re-verify).
- **Partial verdicts are normal.** A list will mix `valid` / `invalid` / `risky`
  / `unknown`; `unknown` rows mean the server couldn't be reached, not that the
  email is bad. Read each row's `status`, and re-verify `unknown` later if it
  matters. Trust `summary` for counts — don't recount `results[]` (it omits the
  deduped addresses).

## Verify

- `GET /jobs/{job_id}/results` → `total` equals the list length you sent (minus
  any `fuzziq_skipped`), and `results[]` has one entry per email.
- `summary` sums to `total`: `{valid, invalid, risky, unknown, fuzziq_skipped}`.
