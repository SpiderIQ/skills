# Retry the transient failures; never retry the terminal ones

**Starting point, not ground truth — verify against current code.**

## The surprise

A people job can "not succeed" in two completely different ways, and they call for
**opposite** responses. Retrying the wrong one wastes a paid call (or worse, loops).

## Terminal — do NOT retry (the input or the target won't change)

| Outcome | What it means |
|---|---|
| `status: "unavailable"` (profile mode) | the profile is private/closed. It will stay private. Tell the user; don't retry. |
| profile job fails on a non-`/in/` URL | you passed a company/other URL to profile mode — fix the input (or use company mode), don't resubmit as-is. |
| `employees_count: 0` from a wrong slug | the `company_url` didn't resolve to a real company — fix the URL, then run. |
| `results_count: 0` on a niche search | Google's first page had no `/in/` hits — broaden the query; the same query will return the same nothing. |

These are **completed** results or input errors, not infra failures. A retry of the
identical payload returns the identical outcome (and within 24h, the free cache).

## Transient — a single resubmit usually fixes it

| Outcome | What it means |
|---|---|
| job `failed` (on `/status`) | usually an infra/provider blip. Remote workers occasionally hit **DNS / network errors** reaching Bright Data or Apify; a hard fail at trigger time often clears on a plain resubmit. |
| Apify 5xx / network blip mid-run | the worker already **auto-retries** its poll (fail-open), so most never surface as a failure — but if the run ends `FAILED`/`ABORTED`/`TIMED-OUT`, the job fails and is worth one resubmit. |
| `revoked_by_dispatcher: true` | the scrape ran past its SLA and was reaped. Resubmit — and for company mode, consider a smaller `max_employees` so it finishes inside the budget. |

## Rule of thumb

- `status: unavailable` / empty / bad input → **terminal**, fix or accept; don't retry.
- a `failed` job / `revoked_by_dispatcher` → **transient**, resubmit once (smaller if
  it timed out). If it fails twice the same way, escalate — don't loop billing calls.
