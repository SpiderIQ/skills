# Recipe: read and act on what an emailVerify run produced

One read surface: the job aggregate. emailVerify writes its verdicts straight
into the job result — `GET /jobs/{job_id}/results` is the complete read for both
single and batch. This recipe covers reading it, the FuzzIQ outcomes, and the
decision matrix for *acting* on the verdicts.

## One-shot aggregate → `/jobs/{job_id}/results`

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Works for **both** single and batch. The response is the canonical **bulk-of-1**
shape — `summary` counts plus one entry per *verified* email in `results[]`:

```yaml
total: 3                     # verified count (AFTER FuzzIQ dedup)
summary: { valid: 2, invalid: 1, risky: 0, unknown: 0, fuzziq_skipped: 0 }
billable_count: 3            # what you paid for
results:
  - { email: ceo@startup.io,        status: valid,   score: 92, flags: {...}, domain: {...} }
  - { email: contact@enterprise.com, status: valid,   score: 88 }
  - { email: fake@nonexistent.xyz,   status: invalid, score: 0 }
metadata: { total_time_seconds: 9.5 }
```

See [results-shape.md](results-shape.md) for every field on a result.

## Single is bulk-of-1 — read `results[0]`

Even when you submitted a single `email`, the verdict is in `results[0]`, **not**
at the top level. The worker emits a flat single-email object, and the API's
results transform wraps it into the canonical bulk envelope; the legacy top-level
`email`/`status`/`score` fields are no longer populated. So:

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT" \
  | yq '.data.results[0]'      # or .results[0], depending on envelope nesting
```

## FuzzIQ outcomes (when `fuzziq_enabled: true`)

Dedup changes the shape — recognize these so you don't misread a *success* as a
miss:

| Outcome | What you get |
|---|---|
| some addresses already known | they're absent from `results[]` and counted in `summary.fuzziq_skipped`; `total` + `billable_count` reflect only the freshly-probed ones |
| a single email already known | `results[0].status == "skipped"` (`reason: already_verified`) — the cached verdict, not a fresh probe |
| **every** address already known (bulk) | `results: []` (empty) with `summary.skipped` set and `reason: all_already_verified` — a complete run, **not** a failure |

So: empty `results[]` with a `summary.skipped` is "nothing new to verify", and a
`skipped` status is "we already knew this one". Neither is an error.

## The decision matrix — what to DO with each verdict

This is the point of verifying. Map each result to an action:

| Verdict | Action |
|---|---|
| `status: valid`, `score >= 80` | **send** — clean |
| `status: valid`, score 50–79 (usually catch-all / role / disposable) | **send with care** — confirm intent; explain the flag (`is_catch_all` / `is_role_account` / `is_disposable`) to the user |
| `status: risky` | **hold / manual review** — exists but flagged; never bulk-blast |
| `status: invalid` | **suppress** — do not send (check `did_you_mean` first; a typo correction may rescue it) |
| `status: unknown` | **re-verify later** — the *probe* failed, not the address; do NOT fold into "invalid" |
| `status: skipped` | already verified — reuse the prior verdict; no action |
| `flags.is_role_account` | route to a human, not a personal-outreach sequence |
| `flags.is_disposable` | drop for signup/anti-fraud; it's a throwaway |
| `dnsbl.blacklists_hit` non-empty | the domain's mail servers are listed — a deliverability/reputation flag on the *domain*, weigh before sending at volume |

Common client-side filters over `results[]`:

```text
deliverable now      → status == "valid"
safe to bulk-send    → status == "valid" AND score >= 80 AND NOT is_role_account
needs human review   → status == "risky" OR is_role_account OR is_catch_all
suppress             → status == "invalid"
retry queue          → status == "unknown"
```

## Token economy & paging

There is no server-side filter or paging on the verify result — it's one job
aggregate; pull it once and filter client-side. `?format=yaml` saves 40–76% over
JSON on a long list; `?format=md` is for a human reader. Set
`SPIDERIQ_FORMAT=yaml` once (CLI/MCP). See
[surfaces-and-auth.md](../../../references/surfaces-and-auth.md).

## Gotchas

- **Read `results[0]` for a single email** — top-level result fields are empty.
- **Trust `summary`, don't recount `results[]`** — `summary` carries
  `fuzziq_skipped`, and the skipped addresses are NOT in `results[]`. Recounting
  undercounts the work.
- **`billable_count` < list length when dedup ran** — it's the count you actually
  paid for (verified, after dedup), not how many you submitted.
- **Empty `results[]` can be a full success** — all-deduped (see FuzzIQ outcomes),
  not a failure. Check `summary.skipped` / `reason` before alarming.
- **`unknown` is not `invalid`** — bucket and re-verify it (see the
  `unknown-not-invalid` learning).
- **Don't parse the status endpoint for data** — `GET /jobs/{id}/status` reports
  *how far along*; `/results` is the data surface.
- **Tenant isolation** — you only ever see your own `client_id`'s jobs.

## Verify

- `GET /jobs/{job_id}/results` returns `results[]` with one entry per *verified*
  email (single → one; all-deduped → empty + `summary.skipped`).
- `summary` totals reconcile: `total` = sum of valid/invalid/risky/unknown =
  `billable_count`; original list length = `total` + `summary.fuzziq_skipped`.
