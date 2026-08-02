# Partial briefs are normal — read each stage, not just the job status

**Starting point, not ground truth — verify against current code.**

## The surprise

The chain is five workers in a row — discover → crawl → registry → LinkedIn →
verify. It's tempting to treat the run as all-or-nothing. It isn't. Each stage is
independently optional (you can disable it) and independently fallible (it can
return nothing while the others succeed). A `status: completed` job can carry an
empty `registry`, an empty `linkedin_company`, or zero emails — and that's a
legitimate result, not an error.

## Why a stage comes back empty

- **Perplexity** found the domain but couldn't confirm a LinkedIn URL → no
  LinkedIn page for SpiderPeople to scrape → empty `linkedin_company`.
- **Registry** miss because the company isn't in UK/US/EU public registries (see
  the registry-coverage learning).
- **Site crawl** found a brochure site with no published emails → empty
  `emails_found`.
- A stage was simply **disabled** via `config.<stage>.enabled=false`.

## What to do

1. Read the **per-stage** presence in the aggregate (`sub_jobs` + each section),
   not just the top-level `status`. Tell the user "found domain + registry, no
   LinkedIn page" — that's accurate and useful.
2. Don't retry the whole job because one section is empty. Empty ≠ broken.
3. If the user *needs* a stage that came back empty, the fix is usually an input
   hint (supply `linkedin_url`, set the right `country_code`), not a retry.

## A read-side trap from the same shape

Because registry and LinkedIn are separate stages, their IDAP records are
**standalone resource types** — `GET /idap/company_registry` and
`GET /idap/linkedin_profiles`. They are **not** `include=` relations on
businesses: `GET /idap/businesses?include=company_registry` silently drops the
unknown include and returns nothing. Query the types directly. (For businesses,
the valid includes are `emails,phones,domains,contacts,pins`.)
