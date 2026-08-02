# Recipe: verify one email (single)

One address in → one verdict out. Use this whenever the user hands you **one**
email to check ("is jane@acme.com real?", "verify this address before I send",
"does this mailbox exist?").

This is the **emailVerify** flow — the standalone verifier for emails you
*already have*. (If you want emails *discovered* from a website or company, that
verification is already a stage inside the
[maps-site-verify-vayapin](../../maps-site-verify-vayapin/recipes/run-single.md)
and [company-intel](../../perplexity-site-companydata-people/recipes/run-single.md)
chains — you don't run this flow for those.)

```
SpiderVerify
SMTP handshake → MX + catch-all + disposable + role + (optional) DNSBL + gravatar
(never sends a real email — simulates the handshake, then QUITs)
```

## Steps

1. **Hand it the address.** `email` is the only required field. Everything else
   is an optional probe toggle — see [verification-options.md](verification-options.md).

2. **Submit** `POST /api/v1/jobs/spiderVerify/submit`. The body wraps the verify
   fields in `payload` (this is a `/jobs/{type}/submit` endpoint, not a flat flow
   endpoint):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderVerify/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "payload": {
         "email": "jane@acme.com",
         "check_gravatar": true
       }
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "spiderVerify", "status": "queued", "created_at": "...", "from_cache": false, "message": "..." }`.

3. **Watch** — poll `GET /jobs/{job_id}/status` no faster than every 3–5s, or use
   the SSE stream. A single email is **3–10 seconds** (one rate-limited SMTP
   handshake), not instant — set the user's expectation. See the foundation's
   [run-modes-and-progress.md](../../../references/run-modes-and-progress.md).

4. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   **The result is bulk-of-1 — your one email is in `results[0]`, not at the top
   level.** See [read-results.md](read-results.md) and [results-shape.md](results-shape.md).

## Key fields (`SpiderVerifyJobPayload`)

| Field | Default | Notes |
|---|---|---|
| `email` | — (required here) | the single address to verify, 3–320 chars |
| `check_gravatar` | `false` | also probe gravatar.com for the email hash |
| `check_dnsbl` | `false` | also check the sending domain against major DNSBLs |
| `smtp_timeout_secs` | `45` | per-mailbox SMTP timeout, 10–120. Lower = faster, more `unknown` |
| `from_email` | none | override MAIL FROM (empty = worker's rotated identity) |
| `hello_name` | none | override EHLO/HELO hostname (empty = worker's domain) |
| `fuzziq_enabled` | client setting | skip re-verifying addresses already in your canonical DB (saves quota) |
| `fuzziq_unique_only` | client setting | return only unique records |
| `priority` | `0` | sibling of `payload`, 0–10 — higher is processed first |
| `test` | `false` | routes to the test queue (dev only) |

> `email` and `emails` are mutually exclusive — provide exactly one. For a list,
> use [run-batch.md](run-batch.md).

## Gotchas

- **Read `results[0]`, not the top level.** Single-email mode is a bulk job of
  one; the verdict lives in `results[0]`. Top-level `email`/`status`/`score` are
  not populated.
- **`status: valid` can carry a mid-range `score`.** The 0–100 score penalizes
  catch-all (−15), disposable (−30), and role accounts (−10), so a real address on
  a catch-all domain can score in the 60s. That's not a contradiction — explain it
  from the quality flags. See [results-shape.md](results-shape.md).
- **`unknown` ≠ invalid.** It usually means the mail server was unreachable,
  rate-limited, or timed out — the address may be fine. Treat `unknown` as "try
  again later", not "bad". See the learnings.
- **Opt in to the extra probes.** Via this API, `check_gravatar` and `check_dnsbl`
  default to **off** — pass `true` if you want them.
- **With `fuzziq_enabled: true`, a known address comes back `status: skipped`**
  (`reason: already_verified`) — the cached verdict, not a fresh probe. Not an
  error; reuse the prior result.
- **`unknown` ≠ invalid** — it means the probe couldn't reach a verdict (server
  blocked / timed out). Re-verify later; don't tell the user the address is bad.

## Verify

- Got a `job_id` and `status: queued` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- `GET /jobs/{job_id}/results` → `total: 1` and one entry in `results[]`.
