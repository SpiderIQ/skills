# Empty is a normal result — don't report it as a failure

**Starting point, not ground truth — verify against current code.**

## The surprise

A people job can complete perfectly and return **nothing**. Each mode has a real,
expected empty case, and the job still finishes with `status: completed` and an
empty payload. That is "we looked and there was nothing public", not "the run
broke".

## The legitimate empty cases

| Mode | Empty when… | What you see |
|---|---|---|
| `profile` | the profile is **private / closed** | empty `profile`; provider marks it `unavailable` |
| `search` | the query is niche / Google's coverage is thin | `profiles: []`, `results_count: 0` |
| `company` | the page has no **public** employees, or the URL/slug is wrong | `employees: []`, `employees_count: 0` |

## Why it matters

- Don't auto-retry an empty result expecting a different answer — a private profile
  stays private, a thin query stays thin. Retrying burns cost and time for the same
  outcome.
- Don't tell the user "this person doesn't exist" or "the run failed". Tell them
  what's true: the profile is private, the search had no public hits, or the company
  has no public roster.
- **Do** sanity-check the input first: a wrong `company_url` (or a person URL passed
  to company mode) produces an empty roster that *looks* like "no employees". The
  `verify-people-complete.sh` script reports the mode + count so you can tell
  "empty-but-complete" apart from "wrong input".

## Rule of thumb

- `status: completed` + empty payload = success with no data. Report the *reason*
  (private / no hits / no public roster), not "failure".
- Before retrying, check the input matched the mode (profile URL for `profile`,
  company URL for `company`, a real query for `search`).
