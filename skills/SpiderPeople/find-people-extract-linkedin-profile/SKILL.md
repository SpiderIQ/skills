---
name: find-people-extract-linkedin-profile
version: 1.0.0
client: find-people-extract-linkedin-profile
client_version: "1.0.0"
description: Research professional profiles and LinkedIn data via SpiderIQ async jobs.
category: data-collection
triggers:
  - find person
  - lookup linkedin
  - research profile
  - who is
  - find decision maker
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F465"
    primaryEnv: OPVS_PAT
---

# Find People & Extract LinkedIn Profiles

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## When to Use This Skill

Use **find-people-extract-linkedin-profile** when the user wants to research a specific person by name, role, or company, or when they have a LinkedIn URL and want structured profile data. Best for identifying decision makers, building prospect lists with professional context, and enriching contact records with job history.

**Do NOT use this skill for:**
- Social media profiles (Facebook, Instagram) -- use `scrape-public-social-profiles` instead
- Company-level data (registration, financials) -- use `lookup-company-data` instead
- Extracting emails from a company website -- use `scrape-website-extract-leads` instead
- Bulk business discovery in a geographic area -- use `scrape-google-maps` instead

## Job Types

| Type | What It Does |
|------|--------------|
| `spiderPeople` | Searches for people by name, role, company, or freeform query. Returns matching profiles with name, title, company, location, and LinkedIn URL |
| `spiderPublicLinkedin` | Extracts structured data from a specific public LinkedIn profile URL: full name, headline, work experience history, education, skills, connections count, and location |

## Expected Processing Times

- **spiderPeople (search):** 10-30 seconds
- **spiderPublicLinkedin (profile extraction):** 10-20 seconds

## What Results Contain

**spiderPeople** returns a list of matching profiles, each with: full name, professional headline, current job title, current company, geographic location, and LinkedIn profile URL.

**spiderPublicLinkedin** returns detailed profile data: full name, headline, current and past work experience with dates, education history, connection count, location, and profile URL.

## Anti-Patterns

- Do NOT use vague search queries like just a first name -- always include company, role, or location for better results
- Do NOT submit LinkedIn extraction jobs for private profiles -- only public profiles can be scraped
- Do NOT run more than 5 people search jobs in rapid succession -- space them out to avoid rate limiting
- Do NOT assume the first search result is the correct person -- present multiple matches and let the user confirm

## Response Guidelines

- Present profiles as structured cards: name, title at company, location
- For LinkedIn extractions, list recent work experience with dates
- If multiple search results are returned, show the top 3-5 matches
- After finding a profile, offer to scrape their company website for email addresses using `scrape-website-extract-leads`
- If the user wants to verify a found email, offer `verify-email-deliverability`

## Available Methods

- `submitSearchJob` -- Submit a people search job by name/role/company
- `submitLinkedinJob` -- Submit a LinkedIn profile extraction job by URL
- `getJobStatus` -- Check the current status of a submitted job
- `getJobResults` -- Retrieve the results of a completed job
- `cancelJob` -- Cancel a running or queued job
