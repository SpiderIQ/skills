# HTTP 200 ≠ "found it" — read the worker's own `data.success`

**Starting point, not ground truth — verify against current code.**

## The surprise

The worker posts **every** outcome — including "not found" and "unsupported
country" — to the job's *completion* callback (`/jobs/{id}/complete`), never the
*failure* callback. So a lookup that found nothing is still `status: completed` and
returns **HTTP 200**. If you treat the HTTP status (or the envelope `success`) as
"it worked", you'll confidently report a company that was never found.

There are **two** `success` flags, and only the inner one is the verdict:

```
envelope.success / status: completed  → the JOB ran (HTTP 200)
data.success                          → whether the LOOKUP actually landed
```

## How to read the verdict, by mode

| Mode | Verdict |
|---|---|
| `search` | `data.success:true` always (even with 0 results) → check `data.total_results` / `data.results.length` |
| `lookup` | `data.success:true` → record in `data.data`; `data.success:false` → `data.error` (`"Company not found"` / `"Unsupported country: XX"`), no `data.data` |
| `vat` | `data.success:true` always → the verdict is `data.data.valid` (and `data.data.error` if it couldn't validate) |

## The `search` ambiguity trap

`search` swallows upstream registry errors: if the UK Companies House or US SEC API
returns a 500 (or times out), the worker logs it and returns
`success:true, results:[], total_results:0` — **identical** to a genuine "no
company by that name". You cannot tell the two apart from the response. So:

- Don't report a hard failure on an empty `search` — say "no match found".
- An empty `search` is worth **one** retry (in case it was a transient upstream
  hiccup); if it's still empty, treat it as "no match / out of coverage".

## What to do

1. **After every job, read `data.success` first** (and `data.error` if false). Never
   conclude from HTTP 200 alone.
2. For `lookup`, a `success:false` with `"Unsupported country"` means you sent a
   non-GB/US country (records are UK/US only) — fix the country, don't retry as-is.
3. For `lookup`, `"Company not found"` on a well-formed UK/US request means the ID
   genuinely doesn't resolve — re-check the `identifier`, or `search` the name first.
4. For `vat`, branch on `data.data.valid`; treat `valid:false`+`error` as "couldn't
   validate" (retryable), not "invalid".

This is *the* accuracy lesson for this flow: requests cost rate-limit budget (and UK
financials cost money), and a confident-but-wrong "found it" off a `success:false`
result is the most expensive mistake an agent can make here.
