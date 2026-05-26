# `profile_mode` is a cost dial, not just a detail level (company mode)

**Starting point, not ground truth — verify against current code.**

## The surprise

`profile_mode` looks like a verbosity flag. It's really a **cost tier**: each level
maps to an Apify `harvestapi` scraper mode with an explicit price per 1,000
employees. And it only does anything in **company** mode — `profile` and `search`
ignore it.

## What each level costs and gives you

| `profile_mode` | Apify scraper mode | Cost | Adds per employee |
|---|---|---|---|
| `short` (default) | "Short ($4 per 1k)" | ~$4 / 1K | name + title |
| `full` | "Full ($8 per 1k)" | ~$8 / 1K | + skills, education, experience |
| `full_email` | "Full + email search ($12 per 1k)" | ~$12 / 1K | + a discovered email |

## Why it matters

- **Cost is `max_employees × profile_mode`.** A 2,000-employee `full_email` pull is
  ~6× the unit cost of `short` *and* the largest roster — that's the expensive
  corner. Most sourcing tasks only need name + title to triage, then a targeted
  `full`/`full_email` pass on the shortlist.
- **`email` and the structured arrays don't exist below their tier.** A `short`
  employee record has no `email`, `skills`, `education`, or `experience` — so asking
  for those fields without raising `profile_mode` just returns nothing.

## Rule of thumb

- Default to `short` and cap `max_employees` to what the user actually needs.
- Step up to `full` only when you need skills/education/experience, and to
  `full_email` only when you specifically need emails.
- For a big roster, pull `short` first, pick the people who matter, then enrich the
  short list — far cheaper than `full_email` on the whole company.
