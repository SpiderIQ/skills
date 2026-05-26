# siteScraper emails are extracted, not verified

**Starting point, not ground truth — verify against current code.**

## The surprise

siteScraper returns `emails: ["info@acme.com", "sales@acme.com", ...]`. It's easy
to assume these are deliverable. They are **not checked** — siteScraper is a
single-worker crawl that *extracts* contact data off the page. There is no SMTP
verification stage in this flow, so the emails carry no `status` / `score` /
`is_deliverable` (the flat `SpiderSiteData.emails` is a plain list of strings).

## Why

The flow is just `dispatch_type: spiderSite` — one worker, one crawl. Email
verification is a *separate* worker (SpiderVerify). It only runs as part of the
**lead chain** (`flow:maps-site-verify-vayapin`, where the Verify stage is wired in
after Site) or the standalone `emailVerify` flow. A bare site crawl never touches
it.

## What to do

- **Set the expectation.** Call them "extracted" or "candidate" emails, not
  "verified". A scraped `info@` address may bounce.
- **If the user needs deliverability**, route differently:
  - For "find businesses + verified emails for a place" → the
    [maps-site-verify-vayapin](../../../../maps-site-verify-vayapin/recipes/run-single.md)
    chain (Maps → Site → **Verify**).
  - For "verify these emails I already extracted" → the `emailVerify` flow with the
    addresses siteScraper returned.
- **Don't reach for `/fuzziq/deduplicate`** to "clean" them — that's not a client
  surface for this flow.

## Rule of thumb

Site crawl = *discovery* of contacts. Verification is a deliberate, separate,
rate-limited step. If the word "verified" matters to the user, this flow alone
isn't enough.
