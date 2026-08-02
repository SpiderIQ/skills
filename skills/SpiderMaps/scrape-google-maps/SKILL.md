---
name: scrape-google-maps
version: 1.0.0
client: scrape-google-maps
client_version: "1.0.0"
description: Search Google Maps for businesses and enrich results via SpiderIQ async jobs.
category: data-collection
triggers:
  - find businesses
  - search google maps
  - find restaurants
  - find companies near
  - enrich maps data
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F5FA"
    primaryEnv: OPVS_PAT
---

# Scrape Google Maps — Local Business Search & Enrichment

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## When to Use This Skill

Use **scrape-google-maps** when the user needs local business data tied to a geographic area: finding businesses by type and location, building lead lists from a region, or researching competitors in a specific market.

**Do NOT use this skill for:**
- Extracting emails/content from a known website URL -- use `scrape-website-extract-leads` instead
- Looking up company registration or financial data -- use `lookup-company-data` instead
- Finding a specific person's professional profile -- use `find-people-extract-linkedin-profile` instead

## Job Types

| Type | What It Does |
|------|--------------|
| `spiderMaps` | Searches Google Maps by query + location and returns business listings with name, address, phone, website, rating, reviews, and category |
| `spiderMapsEnrich` | Takes a Google Maps `place_id` from a previous search and returns extended details including hours, review text, photos, and owner responses |

## Expected Processing Times

- **spiderMaps:** 30-120 seconds depending on `max_results` (default 20)
- **spiderMapsEnrich:** 10-30 seconds per place

## What Results Contain

**spiderMaps** returns a list of businesses, each with: name, full address, phone number, website URL, Google rating (1-5), review count, business category, and Google Maps place_id.

**spiderMapsEnrich** returns deep details for a single business: everything from the search result plus opening hours, recent reviews with text, photo URLs, and owner response history.

## Anti-Patterns

- Do NOT submit more than 3 Maps jobs at once -- they are resource-intensive and will queue behind each other
- Do NOT set `max_results` above 50 unless the user explicitly needs that many -- it dramatically increases processing time
- Do NOT run enrichment on every result from a search -- ask the user which businesses to enrich first

## Response Guidelines

- Present results as a numbered list with name, rating, phone, website
- Highlight businesses with 4+ stars
- If results include websites, offer to run `scrape-website-extract-leads` for deeper contact extraction
- If results include emails, offer to run `verify-email-deliverability` to validate them
- For enrichment results, lead with hours and top reviews since those are the unique value

## Available Methods

- `submitJob` -- Submit a Google Maps search job
- `submitEnrichJob` -- Submit a Maps enrichment job for a specific place_id
- `getJobStatus` -- Check the current status of a submitted job
- `getJobResults` -- Retrieve the results of a completed job
- `cancelJob` -- Cancel a running or queued job
