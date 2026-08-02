## find-people-extract-linkedin-profile

People search + LinkedIn profile extraction. 5 tool calls — submit search, results, profile fetch, list, status.

### What this skill does

- **`search_people`** — queries by name/title/company/location. Returns candidate matches with LinkedIn URLs.
- **`extract_profile`** — given a LinkedIn URL or vanity slug, returns headline, summary, current role, work history, education, skills (when public), connections-count band.
- **`bulk_search`** — batch over a list of (company, role) tuples — useful for "find me the marketing director at each of these 50 companies".
- **`get_search_status`** + **`list_searches`** — async + history.

### Why a separate skill from `lookup-company-data`?

Company-data answers "what's this company like?" People answers "who works there in role X?" Different sources, different anti-bot challenges, different rate limits. SpiderPeople worker handles LinkedIn-aware browser automation distinct from the general-purpose SpiderSite.

### Typical workflows

- **B2B outreach** — agent has a target company, calls `search_people(company="X", title="VP Marketing")`, gets the candidate, drafts personalized outreach.
- **Persona enrichment** — agent extends an existing contact record with LinkedIn data (work history, recent role changes for ABM signals).
- **Org chart mapping** — agent does `bulk_search` to find every C-level at a target account.

### Compliance notes

LinkedIn data is publicly accessible, but privacy regulations (GDPR) require lawful basis for processing. SpiderIQ scopes data to the active brand and doesn't replicate across tenants. Brands using LinkedIn data for outreach are responsible for their own legitimate-interest assessments.
