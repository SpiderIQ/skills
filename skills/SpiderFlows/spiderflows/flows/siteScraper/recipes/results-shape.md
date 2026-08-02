# Reference: the shape of a finished site-crawl record

What one site looks like after the crawl, so you know what you can read back. This
is the record inside `GET /jobs/{job_id}/results` — the **flat** v2.7.6+ structure
(2–3 levels deep, no nesting). The optional AI sections are **always present but
`null`** unless the matching feature was enabled.

## Aggregate envelope

```yaml
url: https://example.com
pages_crawled: 8
crawl_status: success          # success | partial | failed

# Contacts (flat)
emails: [contact@example.com, sales@example.com]   # EXTRACTED, not SMTP-verified
phones:                                            # validated objects (v2.12.0)
  - { raw: "+1-555-123-4567", e164: "+15551234567", country_code: US,
      type: FIXED_LINE_OR_MOBILE, valid: true }
addresses: ["123 Main St, San Francisco, CA 94105"]
logo: { url: "https://media.spideriq.ai/...", confidence: high, type: image }

# Social (14 platforms, always present, null if not found)
linkedin: https://linkedin.com/company/example
twitter:  https://twitter.com/example
facebook: ...        # + instagram youtube tiktok github pinterest snapchat
                     #   reddit medium discord whatsapp telegram

# Content
markdown_compendium: "# Example\n\n..."   # if compendium enabled
compendium: { chars: 15234, available: true, cleanup_level: fit, storage_location: inline }

# AI (null unless enabled)
company_vitals:        { ... }   # extract_company_info
team_members:          [ ... ]   # extract_team
pain_points:           { ... }   # extract_pain_points
lead_scoring:          { ... }   # product_description + icp_description (CHAMP)
custom_analysis:       { ... }   # custom_ai_prompt
personalization_hooks: { ... }

# Landing-page intelligence (first crawled page only)
meta:       { core: {...}, og: {...}, twitter: {...}, icons: {...}, verification: {...} }
schema_org: { blocks: [...], count: 1, by_type: {...}, dropped_types: [...] }

metadata: { crawl_strategy: ..., sitemap_used: ..., spa_enabled: ..., ai_usage: {...} }
```

## What comes back, by feature

### Always (every crawl, zero AI)

| Field | Notes |
|---|---|
| `emails[]` | extracted addresses (tracking/noise filtered). **Not** SMTP-verified. |
| `phones[]` | each a validated object — `e164`, `national`, `international`, `country_code`, `type`, `valid` (libphonenumber) |
| `addresses[]` | physical addresses found |
| `logo` | hosted logo URL + `confidence` + `source` (null if none found) |
| `linkedin` … `telegram` | 14 flat social fields, `null` when absent |
| `meta` | landing-page `<head>`: `core` (title/description/canonical/lang), `og`, `twitter`, `dc`, `icons`, `verification`, … — groups with no tags are omitted |
| `schema_org` | raw JSON-LD blocks filtered to business types (Organization, LocalBusiness + subtypes, Product, Person, …); `dropped_types` lists content types that were filtered out |
| `metadata` | crawl stats — strategy, sitemap used, SPA pages, `ai_usage.total_tokens` |

### From `compendium` (on by default in `compendium`/`leads`/`full`)

`markdown_compendium` (the cleaned markdown) + a `compendium` metadata object
(`chars`, `cleanup_level`, `storage_location`). Large compendiums are **not inline**
— see the gotcha below.

### From AI extraction (opt-in)

| Field | Enabled by |
|---|---|
| `company_vitals` | `extract_company_info` (or `leads`/`full`) — summary, industry, services, target audience |
| `team_members[]` | `extract_team` (or `leads`/`full`) — name, title, email, linkedin |
| `pain_points` | `extract_pain_points` — `inferred_challenges` + `recent_mentions` |
| `lead_scoring` | `product_description` **+** `icp_description` — CHAMP grade + `icp_fit_score` |
| `custom_analysis` | `custom_ai_prompt` — your prompt's JSON output |

## Gotchas

- **`emails[]` are extracted, not verified.** No deliverability `status`/`score`
  here (that's the lead chain's SpiderVerify stage). Treat them as candidates.
- **AI sections are `null`, not missing, when off.** Check for a non-null
  `team_members` / `company_vitals` before telling the user "no team found" — an
  empty section usually means the feature wasn't enabled, not that the data is
  absent.
- **`crawl_status: partial` is legitimate.** Some pages can fail (timeouts, blocks)
  while the crawl still returns useful data. Read `pages_crawled` and the per-field
  presence, not just the top-line status.
- **`team_members` only comes from contact/about/team pages** — and only the first
  ~10 (`leads`) / ~15 (`full`) of them, to save tokens. A person on a deep page may
  be missed.
- **Big compendiums return a URL, not inline text** (>10 MB → presigned download,
  24h TTL). See [the compendium-storage learning](../learnings/2026-05-26-large-compendium-returns-a-url/artifacts/what-we-learned.md).
- **`meta` and `schema_org` are landing-page only** — the URL you submitted, parsed
  once, regardless of how many pages were crawled.

## Reading the same contacts via IDAP

The crawl's contacts auto-sync to your normalized CRM. Query them as IDAP types —
`businesses`, `contacts`, `emails`, `phones`, `domains` — scoped to the site by
`resolve?domain=`. The compendium, `lead_scoring`, `meta`, and `schema_org` live
**only** in `/results`, not in IDAP. See [read-results.md](read-results.md).
