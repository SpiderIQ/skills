# A skip is a healthy outcome — read the reason, don't retry

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

An agent runs Social Media Enrichment on a business and gets back:

```yaml
status: skipped
skipped: true
reason: has_email
```

The instinct is to treat "skipped" like a failure — log an error, or retry it.
Both are wrong. A skip is a **completed job with a definite answer**. The job did
exactly the right thing.

## The reasons, and what each means

| reason | meaning | what to do |
|---|---|---|
| `has_email` | the business already had a usable email | nothing — the healthy, common case; no credit was spent |
| `no_social_handle` | you provided no handle and no social website to try | gather a handle first, then resubmit |
| `not_entitled` | the account's plan does not include Social Media Enrichment | the plan needs the capability enabled |
| `over_cap` | the per-campaign / daily usage cap was reached | wait for the window to reset, or raise the cap |
| `sc_unavailable` | recovery is temporarily unavailable (fail-open) | retry later — nothing was charged |

`has_email` is the single most common outcome on a healthy lead list, because the
whole point is to spend recovery **only** on businesses that actually need it.

## Why it matters

- **A skip costs nothing.** `credits_spent` is 0 on every skip. Retrying a
  `has_email` skip in a loop just burns time; retrying a `no_social_handle` skip
  without adding a handle does the same thing forever.
- **The status is not the story.** Both a recovery and a skip are
  `status: completed` jobs — the recovered-vs-skipped distinction is in the
  result body (`status: recovered | skipped` + `reason`), not the job's
  lifecycle status.
- **Don't confuse the submit with the result.** `POST /jobs/spiderSocial/submit`
  returns `{job_id, status: queued}` — that is NOT the recovered contact. The
  recovery runs in a worker seconds later. Poll `get_job_results` until terminal,
  then read `status` + `reason`.

## The rule

1. submit → `job_id`
2. poll `get_job_results` (≥3–5s apart) until terminal
3. if `status: recovered` → use `recovered_fields`; if `status: skipped` →
   surface the `reason` in plain language and take the matching action above
4. never auto-retry a skip — the reason already told you why
