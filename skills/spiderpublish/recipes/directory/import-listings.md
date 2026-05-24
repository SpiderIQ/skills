# recipes/directory

Build a programmatic-SEO directory — categories + per-city pages + individual listings — with SEO title/description templates that auto-interpolate `{category}`, `{city}`, and `{listing}`.

Two concepts, three URLs:

- **Category** (e.g. `plumbers`) — a vertical with SEO templates
- **Listing** — an individual business inside a category, tagged with `{city, state, country, ...}`
- URLs: `/directory/{category}` → cities list · `/directory/{category}/{city}` → listings · `/directory/{category}/{city}/{listing}` → detail

## The one-shot path (v2.89.0+)

### MCP — recommended

```
directory_create_category(
  name = "Plumbers",
  seo_title_template = "Best {category} in {city} | Your Brand",
  seo_description_template = "Compare top-rated {category} in {city}. Ratings, reviews, hours, directions."
)

directory_bulk_upsert_listings(
  category_slug = "plumbers",
  listings = [
    {
      name: "Aqua Fix",
      city: "Miami Beach",
      state: "Florida",
      phone: "+1-305-555-1234",
      website: "https://aquafix.example.com",
      rating: 4.7,
      review_count: 182,
      data: { hours: [{day: "Mon-Fri", open: "08:00", close: "18:00"}] }
    },
    // ... up to 5000 listings per call
  ]
)
```

Returns `{upserted: N, failed: 0, affected_cities: ["miami-beach-florida", ...]}`. No publish step (listings default to `status: "published"`). No deploy step — the public `/directory/*` routes render live.

### CLI

```bash
spideriq directory categories create \
  --name "Plumbers" \
  --seo-title "Best {category} in {city} | Your Brand" \
  --seo-description "Compare top-rated {category} in {city}. Ratings, reviews, hours."

spideriq directory listings import plumbers --file plumbers-miami.json
```

`plumbers-miami.json` is a JSON array of listing objects.

## URL structure

| URL | What it renders |
|---|---|
| `/directory/{category_slug}` | Category landing — grid of every city that has published listings |
| `/directory/{category_slug}/{city_slug}` | Listings in that city, sorted by rating DESC then review_count DESC |
| `/directory/{category_slug}/{city_slug}/{listing_slug}` | Single listing with contact info + hours + optional breadcrumbs |

**`city_slug` is auto-computed** as `LOWER(city + '-' + state)` with non-alphanumeric stripped. "Miami Beach" + "Florida" → `miami-beach-florida`. Don't manage city slugs by hand — the materialized view does it.

## SEO templates

The three placeholders are substituted server-side on every directory page:

- `{category}` — the category's display name (e.g. "Plumbers")
- `{city}` — the listing's city (e.g. "Miami Beach")
- `{listing}` — the listing's name (e.g. "Aqua Fix")

Example templates:

```
seo_title_template:       "Best {category} in {city} | Your Brand"
seo_description_template: "Compare top-rated {category} in {city}. Ratings, reviews, hours, directions."
```

Every category, every `(category, city)`, and every published listing auto-lands in `/sitemap.xml` with `<lastmod>` and `<changefreq>weekly</changefreq>`.

## Listing fields

Only `name` is required. Everything else shapes the page + the merge-tag pipeline:

| Field | Required? | Notes |
|---|---|---|
| `name` | ✓ | Display name |
| `slug` | — | Auto-generated from name if omitted |
| `description` | — | Rendered on detail page |
| `city`, `state`, `country` | — | Drives `city_slug` computation + sitemap grouping |
| `address`, `latitude`, `longitude` | — | Detail page + future map support |
| `phone`, `email`, `website` | — | Contact card |
| `rating`, `review_count` | — | Sort order on city page + ★ badge |
| `data` | — | Free-form JSONB. `data.hours: [{day, open, close}]` renders automatically. Anything else is available to custom templates. |
| `source_job_id` | — | SpiderIQ job UUID for provenance. Set this when importing from SpiderMaps so you can audit which campaign produced each listing. |
| `status` | — | `published` (default), `draft`, `archived` |

## Ecosystem integration

### IDAP dump → directory

IDAP stores every business SpiderIQ has seen. A single call dumps an entire IDAP result set into a directory category:

```
# 1. Run a SpiderMaps campaign — collect N businesses with full IDAP context
# 2. Transform the results into listing objects
# 3. One call:
directory_bulk_upsert_listings(
  category_slug = "plumbers",
  listings = idap_results.map(biz => ({
    name: biz.company_name,
    city: biz.city,
    state: biz.region,
    country: biz.country_code,
    phone: biz.phone,
    website: biz.website,
    rating: biz.rating,
    review_count: biz.reviews_count,
    source_job_id: biz.source_job_id,  # traceability
    data: { categories: biz.categories, pain_points: biz.pain_points }
  }))
)
```

### Merge tags inside listings

Listings use the same merge-tag pipeline as dynamic landing pages. If you store `{{ salesperson_email }}` in a listing's custom field and render a bespoke detail template, the same `{{ ... }}` resolution rules apply.

## Common variants

### Bulk import from a file (CLI)

```bash
spideriq directory listings import plumbers --file ./exports/miami-plumbers.json
```

### Verify import

```
directory_list_listings(category_slug="plumbers", city="Miami Beach")
# → paginated result set, including your freshly imported rows
```

### Rebuild the city_stats materialized view manually

```
directory_refresh_stats()
```

Normally auto-refreshed on `directory_bulk_upsert_listings` success. Call manually if you've been hand-editing rows or importing via raw SQL.

## When to use

- You have an SEO strategy around "best {category} in {city}" long-tail queries
- You've run a SpiderMaps/IDAP campaign and want the results to surface as a directory
- You're migrating a Yellow Pages-style site and need per-category + per-city pages + individual business details
- You want to reuse the SpiderPublish render pipeline (Liquid templates, theme, merge tags) for a directory product

## When NOT to use

- You have fewer than 20 listings — just make normal pages
- Your "listings" are actually products (SKUs) — use blog posts or a separate product model
- You need complex faceted filtering (price range, distance radius, tag intersection) — directory is single-axis (category + city). For richer search, pair with a dedicated search index.

## Anti-patterns

- DO NOT create a category per city ("plumbers-miami", "plumbers-austin") — one category spans all cities. The platform derives cities from the listings' `city` field.
- DO NOT manage `city_slug` by hand — the materialized view computes it. Editing it directly will desync from the index.
- DO NOT bulk-import more than 5000 listings per call — paginate. Transactions time out and you'll need to retry.
- DO NOT bypass the bulk endpoint for IDAP dumps — individual `directory_upsert_listing` calls for a 3000-row dump burns 3000× the API budget.
- DO NOT add listings to a category that doesn't exist — you'll get 404. Create the category first, then import.

## Files in this skill

- `SKILL.md` — this file
- `schema.yaml` — Tier 2 tool-sequence for MCP consumers

## See also

- [AGENTS.md → Content → Directory](../../../AGENTS.md)
- [recipes/bulk-media-upload](../bulk-media-upload/SKILL.md) — how to upload listing images
- [LEARNINGS.md → Content](../../../LEARNINGS.md#content) — gotchas
- [SpiderIQ `/content/help` → `build_a_directory`](https://spideriq.ai/api/v1/content/help?format=yaml)
- [SpiderIQ `/content/playbook` → `build_a_directory`](https://spideriq.ai/api/v1/content/playbook?intent=build_a_directory&format=yaml)
