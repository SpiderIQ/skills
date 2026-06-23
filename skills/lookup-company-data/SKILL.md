---
name: lookup-company-data
version: 1.0.0
client: lookup-company-data
client_version: "1.0.0"
description: Look up company financial records, registration data, and VAT validation — covers UK Companies House (~5M companies), US SEC EDGAR (~10K public), and EU VIES VAT checks.
category: data-collection
triggers:
  - company lookup
  - check company
  - company data
  - VAT check
  - financial records
  - companies house
  - SEC filing
  - company registration
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F3E2"
    primaryEnv: OPVS_PAT
---

# Lookup Company Data — Registry & VAT Validation

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## When to Use This Skill

Use **lookup-company-data** when the user needs official company registration data, wants to verify a business exists and is active, needs director/officer information, or wants to validate an EU VAT number. This skill queries government registries, not web scraping -- the data is authoritative.

**Do NOT use this skill for:**
- Finding businesses by location (restaurants, shops, etc.) -- use `scrape-google-maps` instead
- Extracting contact info from a company's website -- use `scrape-website-extract-leads` instead
- Researching individual people at a company -- use `find-people-extract-linkedin-profile` instead
- Social media presence of a company -- use `scrape-public-social-profiles` instead

## Three Operating Modes

| Mode | When to Use |
|------|-------------|
| **Search** (by company name + country) | User knows the company name but not the registration number. Returns multiple matches ranked by confidence score |
| **Lookup** (by registration number + country) | User has the exact company number (e.g., Companies House number, KVK number). Faster and more accurate than search, returns full details |
| **VAT Validation** (by VAT number) | User needs to verify an EU VAT number is valid. Checks against VIES database for all EU member states |

## Registry Coverage

| Region | Source | Scope |
|--------|--------|-------|
| UK | Companies House | ~5 million companies: registration, address, SIC codes, officers, filing history |
| EU | VIES | All member states: VAT validity, company name, address. Note: Germany obscures company details per privacy rules |
| US | SEC EDGAR | ~10,000 public companies: financial filings, officers, public records |

## Expected Processing Times

- **Search by name:** 5-15 seconds
- **Lookup by identifier:** 3-10 seconds
- **VAT validation:** 3-10 seconds (VIES service reliability varies)

## What Results Contain

**Search results** return: list of matching companies with registered name, registration number, legal entity type, active/dissolved status, incorporation date, registered address, and a confidence score (0-1) indicating match quality.

**Lookup results** return: full company details including everything from search plus officers/directors (UK), SIC industry codes (UK), and filing history.

**VAT results** return: validity status (valid/invalid), registered company name and address (except Germany which redacts these).

All results include a `data_freshness` indicator showing whether the data is real-time or from a 24-hour cache.

## Anti-Patterns

- Do NOT run search without specifying a country code -- it is a required parameter and searches are country-specific
- Do NOT assume search results are exact matches -- always check the confidence score and present multiple results to the user
- Do NOT use this for countries outside UK/EU/US -- coverage is limited to these registries
- Do NOT repeatedly query the same company -- results are cached for 24 hours

## Response Guidelines

- Show company status prominently (active vs dissolved) -- this is usually the most important fact
- For search results, rank by confidence score and present the top matches
- Format addresses in a readable way, not raw structured data
- For VAT checks, clearly state valid or invalid with the company name
- Note data freshness (real-time vs cached) so the user knows how current the data is
- For UK companies, proactively mention SIC codes and officer names since they are uniquely available

## Available Methods

- `submitSearchJob` -- Search for companies by name and country
- `submitLookupJob` -- Look up a company by registration number and country
- `submitVatJob` -- Validate an EU VAT number
- `getJobStatus` -- Check the current status of a submitted job
- `getJobResults` -- Retrieve the results of a completed job
- `cancelJob` -- Cancel a running or queued job
