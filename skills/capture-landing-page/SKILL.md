---
name: capture-landing-page
version: 1.0.0
client: capture-landing-page
client_version: "1.0.0"
description: Download websites as self-contained HTML bundles with above-fold and full-page screenshots — for competitor analysis, ad tracking, and campaign archival.
category: data-collection
triggers:
  - capture landing page
  - screenshot website
  - download page
  - archive website
  - save webpage
  - capture page
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F4F8"
    primaryEnv: OPVS_PAT
---

# Capture Landing Page — Screenshots & HTML Bundles

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## When to Use This Skill

Use **capture-landing-page** when the user needs a visual snapshot or archival copy of a webpage. Best for: capturing competitor landing pages before they change, documenting ad tracking link destinations, archiving A/B test variants, taking design reference screenshots, and AI-powered content extraction from a page's visual layout.

**Do NOT use this skill for:**
- Extracting emails, phones, or social links from a website -- use `scrape-website-extract-leads` instead (it crawls multiple pages and extracts structured contact data)
- Finding businesses by location -- use `scrape-google-maps` instead
- Getting social media profile data -- use `scrape-public-social-profiles` instead

## Job Type

| Type | What It Does |
|------|--------------|
| `spiderLanding` | Loads a URL in a browser, optionally dismisses popups and scrolls for lazy-loaded content, then captures above-fold screenshot (1440x900 default), full-page screenshot, and a self-contained HTML bundle with all assets embedded. Can also run AI content extraction to identify headlines, CTAs, value propositions, and design patterns |

## Expected Processing Times

- **Static pages:** 3-5 seconds
- **Marketing sites (animations, lazy loading):** 15-30 seconds
- **Complex SPAs:** 30-60 seconds
- AI content extraction adds 2-5 seconds on top

## What Results Contain

**Screenshots:** URLs to above-fold (viewport) PNG and full-page PNG images.

**HTML bundle:** URL to a self-contained HTML file (5KB-50MB) with all CSS, images, and fonts embedded -- can be opened offline.

**Content extraction** (when enabled): page title, meta description, Open Graph tags, extracted headlines (H1-H6), call-to-action elements, key value propositions, design analysis (layout type, color palette, form fields), and the URL redirect chain if the original URL had redirects.

## Anti-Patterns

- Do NOT use this to extract contact info or lead data -- it captures the visual page, not structured data. Use `scrape-website-extract-leads` for that
- Do NOT submit more than 3 capture jobs at once -- they use browser instances and are resource-intensive
- Do NOT capture pages that require login -- the browser session is anonymous
- Do NOT set extremely large viewports expecting better results -- stick to standard presets (Desktop 1440x900, HD 1920x1080, Tablet 768x1024)

## Response Guidelines

- Show screenshot URLs prominently -- these are the primary deliverable for most users
- If content extraction was enabled, summarize the key headlines and CTAs in a readable format
- Note the redirect chain if the URL had redirects -- the user may want to know the final destination
- For HTML bundles, mention the approximate file size so the user knows what to expect
- Offer to compare with previous captures if the user is tracking changes over time

## Available Methods

- `submitCapture` -- Submit a landing page capture job
- `getJobStatus` -- Check the current status of a submitted job
- `getJobResults` -- Retrieve the results of a completed capture job
