---
name: manage-locations
version: "1.0.0"
description: >
  Manage SpiderIQ location database — cities, postcodes, country coverage,
  and postcode research for campaign search expansion.
category: admin
client: manage-locations
client_version: "1.0.0"
homepage: https://app.spideriq.ai/admin/locations
metadata:
  openclaw:
    emoji: "\U0001F4CD"
    primaryEnv: SPIDERIQ_ADMIN_KEY
---

# Manage Locations

Manage the SpiderIQ location database used by campaigns and lead research.
~45,000 locations across 240 countries — cities and postcodes.

## When to Use

- **Expand campaign coverage** — add postcodes to cities so campaigns search at postcode granularity instead of city level
- **Check country gaps** — see which countries/cities are missing postcodes
- **Add new cities** — register cities not yet in the database
- **Audit coverage** — view stats before launching a campaign in a new country

## Key Concept: Postcode Expansion

Searching by city yields 20-500 Google Maps results. Searching by postcode yields a focused subset per area. A city with 100 postcodes gives 100 separate searches with much more total results.

**This is the primary workflow for this skill.**

### Postcode Expansion Workflow

1. **Check country stats:**
   ```
   getCountryStats(country_code: "DE")
   ```
   Look at `needs_postcodes` count — these are cities with population >= 500k that don't have postcode entries yet.

2. **Find cities needing postcodes:**
   ```
   listLocations(country_code: "DE", needs_postcodes: true)
   ```
   Returns cities flagged for postcode expansion.

3. **Research postcodes for each city:**
   Use your own knowledge to list postcodes for the city. For example, Berlin has postcodes 10115-14199. The `researchLocations` endpoint is a placeholder (returns empty) — use your knowledge instead.

4. **Create postcode entries:**
   For each postcode, create a location:
   ```
   createLocation(
     country_code: "DE",
     country_name: "Germany",
     search_string: "10115 Berlin, Germany",
     location_type: "postcode",
     display_name: "Berlin 10115",
     parent_city: "Berlin",
     admin_region: "Berlin"
   )
   ```

5. **Verify expansion:**
   ```
   getCountryStats(country_code: "DE")
   ```
   Confirm postcode count increased.

## Available Methods

| Method | What it does |
|--------|-------------|
| `listLocations` | Search/filter locations (country, type, region, population, text) |
| `getGlobalStats` | Total locations, countries, cities, postcodes, cities needing postcodes |
| `listCountries` | All countries with location counts |
| `getCountryStats` | Detailed stats for one country (cities, postcodes, gaps, regions) |
| `createLocation` | Add a city or postcode |
| `getLocation` | Get one location by ID |
| `updateLocation` | Modify location fields |
| `deleteLocation` | Remove a location (blocked if used in active campaigns) |
| `researchLocations` | AI research placeholder (returns empty — use agent knowledge) |

## Rules

- **Always set `parent_city`** when creating postcodes — campaigns use this to group results
- **Always set `location_type: "postcode"`** for postcode entries (default is "city")
- **Don't create duplicates** — same country_code + search_string returns 409
- **Don't delete locations in active campaigns** — returns 409; wait for campaign to complete
- **Use `search_string` for Google Maps** — format as "{postcode} {city}, {country}" for postcodes
- **Population >= 500k** auto-flags `needs_postcodes: true` on city entries
