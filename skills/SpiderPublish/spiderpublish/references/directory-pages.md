# Directory pages — programmatic SEO from the tenant's own business data

> **REQUIRES — read before you plan.**
> **Package:** `directory_*` ships in **every** universe (kitchen sink · `mcp-publish` default). Floors: `@spideriq/mcp-publish` ≥ 1.43.0 · `@spideriq/mcp` ≥ 1.91.1 · `@spideriq/cli` ≥ 1.73.1 · `@spideriq/core` ≥ 1.76.0.
> **Tools:** `directory_create_category` · `directory_import_from_idap` · `directory_bulk_upsert_listings` · `directory_upsert_listing` · `directory_list_categories` · `directory_list_listings` · `directory_get_category` · `directory_update_category` · `directory_delete_category` · `directory_delete_listing` · `directory_refresh_stats` — **11 tools, and that is the whole family.**
> **Listings are LIVE ON PUBLISH — no deploy.** Rows land, pages render at request time (~60s edge cache). **Deploy only if you changed a Liquid template or the tenant's `directory_base`.**
> **Not sure which universe you are in?** SKILL.md → *Step 0*.


A directory is many pages generated from one dataset: *"Plumbers in Miami"*, *"Plumbers in
Austin"*, one page per business. You author **two** things — a **category** and its **listings** —
and the platform generates every URL, every SEO title, and every `sitemap.xml` entry from them.

Reach for this when the user says: *programmatic SEO*, *a page per city*, *a business directory*,
*local listings*, *"plumbers in {city}"*, *turn our scraped businesses into pages*.

Everything below is **project-scoped**. Bind a project first (`spideriq use <id>`, a
`-w/--workspace`, or an `X-Project-Id` header).

---

## Which shape do you want?

```
  Do the URLs need a CITY in them?  ("plumbers in miami")
    │
    ├─ YES → CATEGORY-FIRST. This file.
    │        /{directory_base}/{category}/{city}/{listing}
    │        Built-in routes, SEO templates, sitemap. No page rows at all.
    │
    └─ NO  → FLAT. One page, every listing, no category or city segment.
             A dynamic_list page bound to collection_type "directory_listings".
             → references/dynamic-collections.md

  Both layouts read the SAME listings and can coexist. Flat does not replace nested.
```

Not this file: **one** personalised page per prospect at `/lp/{page}/{id}` — that is
`references/dynamic-landing.md`, a different surface with different rules.

---

## The model — it renders a COPY, not IDAP

This is the fact that explains every behaviour below.

```
   norm_cli_<tenant>.businesses          content_directory_listings
   (IDAP — the canonical corpus)   ──▶   (a COPY, owned by the CMS)   ──▶  public pages
                                 import                              render
```

The import **copies rows in**. Public pages then read `content_directory_listings`, and **never
touch IDAP at request time**. Consequences you must design around:

- **A change in IDAP does not appear on the site.** Nothing syncs. There is no scheduler. You
  re-run the import, and the loop is yours to drive.
- **The copy can be edited independently** (`directory_upsert_listing`) — useful, and it means a
  re-import can overwrite an editorial fix.
- **Re-import never removes anything** unless you ask it to. See *Staleness*, below.

---

## Build one

```
directory_create_category(name="Plumbers", slug="plumbers",
  seo_title_template="Best {category} in {city} | Acme",
  seo_description_template="Compare {category} in {city}. Ratings, reviews, hours.")

directory_import_from_idap(category_slug="plumbers",
  category_filter="Plumber", country_code="US", rating_min=4.0, limit=5000)
```

That is the whole directory. **No publish step** — listings default to `status='published'`.
**No deploy step** — the pages render live.

### The URL shape — four levels, and the prefix is a per-tenant setting

| URL | Renders |
|---|---|
| `/{directory_base}/{category_slug}` | category hub — the list of **cities** that have listings |
| `/{directory_base}/{category_slug}/{city_slug}` | listings in that city, rating DESC then review_count DESC |
| `/{directory_base}/{category_slug}/{city_slug}/{listing_slug}` | one listing — contact, hours, breadcrumbs |
| `/sitemap.xml` | every category, every (category, city), and every published listing — automatically |

**`{directory_base}` defaults to `"directory"` and is renamable per tenant:**

```
template_update_config(directory_base="ls")   →  /ls/plumbers/manchester/acme
```

422 if it is malformed (`^[a-z0-9][a-z0-9-]*$`), a reserved namespace (`blog`, `docs`,
`changelog`, `press`, `newsroom`, `f`, `lp`, `api`), or collides with an existing page slug or a
collection `route_base`. **Renaming is SEO-safe**: the old `/directory/...` URLs keep serving as
permanent **301** redirects to the new prefix, and `sitemap.xml` switches to advertising only the
new one. A published CMS page at slug `<directory_base>` renders in place of the built-in hub.

⚠️ `directory_base` lives in the deploy-time config overlay — changing it **needs a deploy**, unlike
listings.

### 🔴 `{city}` is not yours to set

`city_slug` is **derived server-side** from each listing's `city` + `state`
(`'Miami Beach'` + `'Florida'` → `miami-beach-florida`). There is no city field on a category and
no way to pass a city slug.

**So: never create one category per city.** One category spans all its cities — that is what the
hub page is. `directory_create_category(name="Plumbers in Miami")` is the classic wrong turn; it
produces a directory with one city per vertical and no hub worth having.

### SEO templates render server-side — and ship to Google

`seo_title_template` / `seo_description_template` accept `{category}`, `{city}` and `{listing}`.
They are rendered on every public directory read **and** they generate the `<title>` /
`<description>` of every `sitemap.xml` entry the category contributes.

🔴 **A placeholder typo therefore ships to search engines, not just to a page.** Read one rendered
listing back before you import 5,000.

---

## Getting listings in

### From the tenant's own IDAP corpus — one call

```
directory_import_from_idap(category_slug="plumbers",
  category_filter="Plumber",     # matches the businesses.categories[] array
  country_code="US",             # ISO-2, uppercase, exact
  city="Miami",                  # ILIKE substring
  rating_min=4.0,                # inclusive
  limit=5000,                    # hard cap 5000
  prune=False)                   # see Staleness
```

Reads `norm_cli_*.businesses` **directly** — no scheduler, no sync pipeline, no export step, no
external call. It carries **every declared column** through: the typed columns land on
`content_directory_listings`, everything else lands in the listing's `data` JSONB. It returns
`{upserted, inserted, updated, pruned, failed, source_rows, affected_cities, source_schema,
fields_mapped, filter, sync_log_id, failures?, prune_skipped_reason?, hint?}`.

If the tenant has never run SpiderMaps there is no `norm_cli_*` schema; the response's `hint`
explains the workaround rather than failing silently.

### From anything else — bulk upsert

```
directory_bulk_upsert_listings(category_slug="plumbers", listings=[
  {name, slug?, city, state?, description?, phone?, email?, website?, rating?,
   review_count?, address?, latitude?, longitude?, data?, status?, source_job_id?}, ...])
```

Use this for a hand-built list, a third-party feed, an Airtable view — any **non-IDAP** source.
Set `source_job_id` when you have one so provenance is auditable.

**5000 listings per call.** Paginate above that; larger single calls risk a transaction timeout.

### 🔴 Idempotency is by `slug`, within a category

The unique index is **`(category_id, slug)`**. Re-running an import matches on that pair and
UPDATEs; anything else INSERTs.

There is **no `external_id` column** and **no `on_conflict` parameter** — not on the table, not in
`directory_service.py`, not in any tool schema. If you want provenance from a source system, put
its record id in the listing's **`data` JSONB**, or use **`source_job_id`**. Do not build a sync
that depends on an idempotency key the platform does not have.

⚠️ A listing slug is unique **per category**, not per tenant. Two categories may legitimately hold
the same slug.

---

## Staleness — the thing that will bite you

🔴 **Both import paths are an UPSERT and NEITHER REMOVES ANYTHING.** A business deleted from IDAP,
or renamed so it now derives a different slug, leaves its **old listing published forever** — and
every re-import drifts the category further from its source. Nothing errors. The stale listing just
keeps serving.

**The fix, and it is OFF BY DEFAULT:**

```
directory_import_from_idap(category_slug="plumbers", ..., prune=True)
```

`prune` **archives** (`status='archived'` — never deletes; reversible with
`directory_upsert_listing`) every listing the import's own result set did not produce.

**It refuses rather than guess**, and names which in `prune_skipped_reason`:

| reason | why refusing is correct |
|---|---|
| `source_returned_no_rows` | an empty result is far more often a filter that matched nothing than a category that genuinely emptied. Pruning there would archive **everything**. |
| `source_truncated_at_limit` | the SELECT hit `limit`, so "absent from this page" is a pagination artefact, not a deletion. Raise `limit` or narrow the filter. |

🔴 **A refusal is an ANSWER, not a transient error.** `pruned: 0` with a reason is the correct
result; re-running unchanged refuses identically. Change the inputs, do not retry.

### Three ways to re-run the import — same operation, three doors

| Surface | Call |
|---|---|
| **MCP** | `directory_import_from_idap(category_slug, {category_filter, country_code, city, rating_min, limit, prune})` |
| **CLI** | `spideriq directory listings import-from-idap <category-slug> --category-filter "Plumber" --country-code US --rating-min 4.0 --limit 5000 --prune` |
| **Dashboard** | **Content Studio → Directory** (sidebar, between *Collections* and *Docs*) → open a category → the **Import from IDAP** tab, with five filters: category, country, city, `rating_min`, `limit`. The sibling tab is *Paste JSON*. |

⚠️ The dashboard tab only mounts on a category that **exists** — a category editor opened on a
missing slug early-returns to a not-found state before the import panel renders. Create the
category first.

There is **no scheduler on any of the three.** Re-running is a decision someone makes.

---

## Counts and stats — two similar names, two different numbers

```
directory_refresh_stats()
```

Rebuilds the **`city_stats` materialized view** — the per-(category, city) rollup that hubs and
city pages read to know which cities exist and how many listings each holds.

🔴 **It does NOT recompute a category's `listing_count`.** That column lives on the category row
and is maintained by the **write** paths only (bulk upsert, import, prune, delete-listing). Nothing
recomputes it on demand and this tool will not. If a `listing_count` looks wrong, re-run the write
that produced it.

You rarely need `directory_refresh_stats` at all — every write path refreshes `city_stats` itself.
Reach for it when a hub or city page shows a stale city list after a change made outside the normal
write path.

---

## Customising the look

Three Liquid templates back the three public routes. Override any of them with `template_upsert`:

| Route | Template |
|---|---|
| category hub | `templates/directory-category.liquid` |
| city page | `templates/directory-city.liquid` |
| listing detail | `templates/directory-listing.liquid` |

They read `listing.*` (the typed columns) and `data.*` (whatever you stored in the listing's `data`
JSONB). A template change **needs a deploy**; a listing change does not.

🔴 **Merge tags do NOT work here.** `{{ first_name }}`, `{{ company_name }}` and the rest are
`/lp/` **lead-scoped only** — they are built from a lead resolved by the `/lp/{page}/{identifier}`
routes, and on every other route, directory pages included, they resolve to the canonical empty
shape. On a directory page they render as empty strings, silently. Use `listing.*` / `data.*`.

⚠️ **An override is a copy, and it shadows.** A tenant holding an override of one of these files
keeps serving its own version after a platform template fix — including when the override is a
byte-identical copy of the old default. Check the tenant's templates before promising a fix reaches
their site.

---

## Verify

```
directory_list_listings({category_slug: "plumbers", limit: 5})
content_visual_check({page_url: "https://<tenant>/directory/plumbers/miami-florida", viewport: "desktop"})
```

🔴 **Count, do not eyeball.** An absent field and an empty field render identically on these pages
— the templates run their values through `| default:` chains. Read a listing back through
`directory_list_listings` and check the keys are there before trusting a screenshot.

---

## Do not claim

- **Do not claim anything syncs.** There is no scheduler and no background job. A directory is as
  current as the last import someone ran.
- **Do not claim a re-import cleans up.** It does not, unless `prune=true` — and `prune` can
  legitimately refuse.
- **Do not offer `external_id` or `on_conflict`.** Neither exists at any layer.
- **Do not offer `directory_archive_listing`.** It is not a tool. Archive with
  `directory_upsert_listing(category_slug, slug, status="archived")`.
- **Do not say `directory_refresh_stats` fixes `listing_count`.** It refreshes `city_stats`.
- **Do not write `/directory/` as a fixed contract.** It is `{directory_base}` and the tenant may
  have renamed it.
- **Do not promise merge tags on directory pages.**
- **Do not claim listings need a deploy.** Only templates and `directory_base` do.

## See also

- `references/dynamic-collections.md` — the FLAT layout over these same listings, and every other
  `collection_type`
- `references/integrations.md` — importing from an outside system (Airtable and friends)
- `references/dynamic-landing.md` — one personalised page per prospect, the other IDAP surface
- `references/templates-deploy.md` — `template_upsert`, themes, and the deploy protocol
- `references/tool-surface.md` — the `directory_*` family in the tool map
