---
name: scrape-website-extract-leads
version: 1.1.0
client: scrape-website-extract-leads
client_version: "1.0.0"
description: Crawl websites to extract content, emails, phones, and social links via SpiderIQ async jobs.
category: data-collection
triggers:
  - scrape website
  - crawl site
  - extract emails from
  - get contact info from website
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F578"
    primaryEnv: OPVS_PAT
---

# Scrape Website & Extract Leads

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## When to Use This Skill

Use **scrape-website-extract-leads** when the user has a specific website URL and wants to extract contact information (emails, phone numbers), social media links, or page content from it. Best for lead enrichment, competitor website analysis, and building contact lists from company websites.

**Do NOT use this skill for:**
- Taking screenshots or archiving a page's visual design -- use `capture-landing-page` instead
- Finding businesses in a geographic area -- use `scrape-google-maps` instead
- Looking up official company registration data -- use `lookup-company-data` instead
- Researching a specific person -- use `find-people-extract-linkedin-profile` instead

## Job Type

| Type | What It Does |
|------|--------------|
| `spiderSites` | Crawls a website starting from the given URL, following internal links up to `max_pages`, and extracts emails, phone numbers, social media links, and page content from each page crawled |

## Expected Processing Times

- **Simple sites (1-5 pages):** 15-30 seconds
- **Larger crawls (10+ pages):** 30-60 seconds
- Processing time scales with `max_pages` (default: 10)

## What Results Contain

Results include: page title, meta description, extracted text content (as markdown), an array of discovered email addresses, an array of phone numbers, social media profile links grouped by platform (Facebook, Twitter, LinkedIn, etc.), and the number of pages actually crawled.

## Anti-Patterns

- Do NOT set `max_pages` above 20 unless the user explicitly needs a deep crawl -- it slows processing significantly and rarely finds more contact info than the first 10 pages
- Do NOT use this skill to capture landing page screenshots or HTML bundles -- use `capture-landing-page` for that
- Do NOT submit multiple scrape jobs for different pages on the same domain -- one job with a higher `max_pages` is more efficient
- Do NOT scrape the same site repeatedly in short succession -- results are cached

## Response Guidelines

- List discovered emails and phones prominently -- these are the primary value
- If emails are found, proactively offer to verify them with `verify-email-deliverability`
- Show social links grouped by platform
- If no contact info was found, suggest the user try a different starting URL (e.g., /contact, /about, /team)

## Available Methods

- `submitJob` -- Submit a website scraping job
- `getJobStatus` -- Check the current status of a submitted job
- `getJobResults` -- Retrieve the results of a completed job
- `cancelJob` -- Cancel a running or queued job
