# Read a Social Media Enrichment result

A completed enrichment job returns ONE of two shapes: a **recovery** or a
**skip**. Both are `status: completed` jobs — the difference is in the result
body, not the job status.

## Recovered

```yaml
status: recovered
skipped: false
reason: null
email: cs@katzsdelicatessen.com
phone: (212) 254-2246
website: katzsdelicatessen.com     # a real, non-social site (null if none found)
socials:                           # any social links recovered along the way
  instagram: https://instagram.com/katzsdeli
recovered_fields:                  # exactly what THIS job newly found
  - email
  - phone
  - website
credits_spent: 1
cost_usd: 0.008
```

| Field | Meaning |
|---|---|
| `status` | `recovered` when at least one field was newly found. |
| `email` / `phone` / `website` | the recovered contact fields (any may be null). `website` is a REAL site, never a social URL. |
| `socials` | a map of social links recovered as a side effect. |
| `recovered_fields` | the names of the fields THIS job newly recovered — show these to the user. |
| `credits_spent` / `cost_usd` | what the recovery cost (> 0 only on a recovery). |

Everything is **additive** — a value you passed in (`email`, `phone`) is never
overwritten; recovery only fills gaps.

## Skipped

```yaml
status: skipped
skipped: true
reason: has_email
email: null
phone: null
website: null
socials: {}
recovered_fields: []
credits_spent: 0
cost_usd: 0.0
```

A skip is a **normal, healthy outcome** — not a failure, not something to retry.
The `reason` is the answer:

| reason | meaning | what to do |
|---|---|---|
| `has_email` | the business already had a usable email | nothing — this is the common, healthy case; no credit spent |
| `no_social_handle` | no handle or social website was provided to try | gather a handle first, then resubmit |
| `not_entitled` | the account's plan does not include Social Media Enrichment | the plan needs the capability enabled |
| `over_cap` | the per-campaign / daily usage cap was reached | wait for the window to reset, or raise the cap |
| `sc_unavailable` | recovery is temporarily unavailable (fail-open) | retry later; nothing was charged |

## Where recovered contacts appear elsewhere

- **Standalone job** (this skill's `submitJob`): read the recovered fields from
  `getJobResults` as above.
- **Inside a lead campaign** (via `workflow.social_media_enrichment`): a recovered
  email/phone is merged into that business's lead like any natively-scraped
  contact, so it shows up in the campaign's normalized data (businesses /
  contacts / emails / phones) that `internet-data-access` (IDAP) reads — no
  separate step. See `campaign-toggle.md`.

## Response guidance

- Lead with the outcome in one line: "recovered an email + phone" or "skipped —
  already had an email."
- List `recovered_fields` so the user sees exactly what's new.
- On a skip, translate the `reason` to plain language and the next action.
- Recommend `verify-email-deliverability` on any recovered email before outreach.
