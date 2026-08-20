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
| `spiderPeople` | One endpoint, three modes chosen by the required `mode` field. `profile` fetches one LinkedIn profile by URL; `search` finds people from a natural-language query; `company` extracts a company's employees |
| `spiderPublicLinkedin` | Extracts structured data from a specific public LinkedIn profile URL: full name, headline, work experience history, education, skills, connections count, and location |

### `mode` is required — pick it before you submit

| mode | Required field | Returns | Cost |
|------|----------------|---------|------|
| `profile` | `linkedin_url` | one full profile (name, city, education, current company) | ~$0.003 |
| `search` | `search_query` | a list of matching profiles (name + headline + URL) | ~$0.01 |
| `company` | `company_url` | that company's employees with titles + locations | $4-12 per 1,000, set by `profile_mode` |

Omitting `mode` is a **422**, not a default. Sending the wrong mode's field is also a 422 —
`search_query` with `mode=profile` fails with `'linkedin_url' is required for profile mode`.

## Expected Processing Times

- **spiderPeople (search / profile):** 10-30 seconds
- **spiderPeople (company):** 20-60 seconds, longer as `max_employees` rises
- **spiderPublicLinkedin (profile extraction):** 10-20 seconds

## What Results Contain

**spiderPeople** returns a shape that depends on `mode`:
- `search` -> `profiles[]`, each with name, headline, and LinkedIn URL.
- `profile` -> one profile object: `full_name`, `city`, `about`, `current_company`, `education[]`, `experience[]`. Sparse fields are normal — Bright Data returns `headline: null` and `experience: []` for some public profiles, and that is the source data, not a failure.
- `company` -> `employees[]`, each with `full_name`, `title`, `location`, `linkedin_url`.

**spiderPublicLinkedin** returns detailed profile data: full name, headline, current and past work experience with dates, education history, connection count, location, and profile URL.

## Anti-Patterns

- Do NOT use vague search queries like just a first name -- always include company, role, or location for better results
- Do NOT submit LinkedIn extraction jobs for private profiles -- only public profiles can be scraped
- Do NOT run more than 5 people search jobs in rapid succession -- space them out to avoid rate limiting
- Do NOT submit `company` mode without `max_employees` -- it defaults to 100 and every employee is billed
- Do NOT read a job still at `status: queued` as "still working" indefinitely. A SpiderPeople job whose worker failed does NOT surface the error on the job row; it stays `queued` until a 24h watchdog cancels it. If a job sits `queued` for more than a few minutes, treat it as failed and resubmit rather than polling on.
- Do NOT assume the first search result is the correct person -- present multiple matches and let the user confirm

## Response Guidelines

- Present profiles as structured cards: name, title at company, location
- For LinkedIn extractions, list recent work experience with dates
- If multiple search results are returned, show the top 3-5 matches
- After finding a profile, offer to scrape their company website for email addresses using `scrape-website-extract-leads`
- If the user wants to verify a found email, offer `verify-email-deliverability`

## Available Methods

- `submitPeopleJob` -- Submit a SpiderPeople job in `profile`, `search`, or `company` mode
- `submitLinkedinJob` -- Submit a public-LinkedIn extraction job by URL
- `getJobStatus` -- Check the current status of a submitted job
- `getJobResults` -- Retrieve the results of a completed job
- `cancelJob` -- Cancel a running or queued job
