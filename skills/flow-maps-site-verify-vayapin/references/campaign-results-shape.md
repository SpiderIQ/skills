# Reference: the shape of a finished business record

What a single business looks like after the full chain, so you know what you can
read back. This is the per-business record inside both `/jobs/{id}/results` and the
campaign `workflow-results` aggregate, and (flattened) what `/idap/businesses`
returns.

## Aggregate envelope (`workflow-results`)

```yaml
campaign_id: camp_x
status: completed
query: plumbers
country_code: DE
total_locations: 12
total_businesses: 540
total_with_domains: 470
total_domains_filtered: 70
total_emails_found: 1200
total_emails_verified: 860
locations:
  - location_id: 101
    search_string: "plumbers in München"
    status: completed
    businesses_count: 45
    businesses: [ ... per-business records ... ]
```

## Per-business record — the three stages

### From SpiderMaps (always present)

| Field | Notes |
|---|---|
| `business_name` | — |
| `business_address` | formatted address |
| `business_phone` / `gmaps_phone_e164` | raw + validated E.164 |
| `business_rating` / `business_reviews_count` | Google rating + count |
| `business_categories[]` | Google categories |
| `google_place_id` | stable Maps id |
| `gmaps_coordinates` | `{lat, lng}` |
| `original_website` / `domain` | site URL + parsed domain |
| `domain_filtered` / `filter_reason` | true if the domain was dropped pre-crawl (social/review/directory/maps) |

### From SpiderSite (if `spidersite.enabled`)

| Field | Notes |
|---|---|
| `spidersite_status` | `completed` / `failed` / `skipped` / `pending` |
| `pages_crawled` | — |
| `emails_found[]` / `phones_found[]` | raw extraction |
| `social_media{}` + flat `linkedin`/`twitter`/`facebook`/… | up to 14 platforms |
| `team_members[]` | if `extract_team` |
| `company_info` | if `extract_company_info` |
| `lead_scoring` | CHAMP grade — `icp_fit_grade`, `engagement_score`, `lead_priority`, `champ_breakdown` (only if `product_description`+`icp_description` were set) |
| `compendium_metadata` | markdown doc stats + `download_url` (the compendium body is fetched separately, not inlined) |

### From SpiderVerify (if `spiderverify.enabled`)

| Field | Notes |
|---|---|
| `spiderverify_status` | `completed` / `failed` / `skipped` / `pending` |
| `emails_verified[]` | per-email result (below) |
| `valid_emails_count` | count of deliverable addresses |

Each `emails_verified[]` entry:

| Field | Notes |
|---|---|
| `email` | the address |
| `status` | `valid` · `invalid` · `risky` · `unknown` |
| `score` | 0–100 |
| `is_deliverable` | SMTP confirmed |
| `is_free_email` / `is_disposable` / `is_role_account` / `is_catch_all` | quality flags |
| `has_gravatar` | if `check_gravatar` was on |
| `domain_info` | `{name, mx_found, mx_records, smtp_provider}` |

### Workflow metadata

- `workflow_stage` — `maps` · `site` · `verify` · `complete` · `failed` (how far this
  business got).

## Published pins

Not in the business record above — read via `include=pins` on IDAP
(`businesses[].pins[].vayapin_url` / `pin_name`). See
[vayapin-export.md](vayapin-export.md).

## Reading the same data via IDAP

`/idap/businesses` returns the business columns; expand the children with
`include=emails,phones,domains,contacts,pins`. The verified-email detail
(`status`, `score`, flags) lives on the email records — `GET /idap/emails?campaign_id=<id>`
or `include=emails`. See [read-results.md](read-results.md).
