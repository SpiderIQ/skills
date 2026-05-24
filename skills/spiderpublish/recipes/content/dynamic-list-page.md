# recipes/content/dynamic-list-page

Create a dynamic LIST page — iterates a collection (posts, docs, or directory_listings) and renders one card per item. The "/blog" / "/docs" / "/directory" index pattern.

## When to use

- You want a `/blog` index that auto-lists all published blog posts (so adding a post doesn't require editing the index).
- You want a `/docs` landing page that shows the docs tree.
- You want a `/listings` or `/places` page for a directory of `content_directory_listings`.
- More broadly: any page that should display a list of dynamically-changing items without manually editing the page.

For a single dynamic page (e.g. `/blog/<slug>` or `/listings/<city>`) → [`dynamic-item-page.md`](dynamic-item-page.md). For a static page → [`landing-page.md`](landing-page.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **The collection has ≥1 published item** (otherwise the page renders an empty list). Check:
   - For `posts`: `content_list_posts({ status: "published" })` returns ≥1.
   - For `docs`: `content_docs_tree()` returns ≥1.
   - For `directory_listings`: `directory_list_listings({ status: "published" })` returns ≥1.
3. **Theme has `templates/dynamic-list.liquid`.** Default theme ships it; check `template_list()` if customized.

## The 1-call path

```
content_create_page({
  title:    "Blog",
  slug:     "blog",
  template: "dynamic_list",
  collection_type: "posts"          # REQUIRED for dynamic_list
})
```

That's the whole page. The renderer iterates published `content_posts` and emits one card per item, using `templates/dynamic-list.liquid` for the layout.

## The three collection types

| `collection_type` | Iterates | URL convention |
|---|---|---|
| `posts` | Published `content_posts` (blog posts) | List at `/<slug>`; items at `/<slug>/<post_slug>` (typically `/blog/<post_slug>`) |
| `docs` | `content_docs` tree (only published nodes) | List at `/<slug>`; items at `/<slug>/<doc_full_path>` (typically `/docs/<full_path>`) |
| `directory_listings` | Published `content_directory_listings` | List at `/<slug>`; items at `/<slug>/<listing_slug>` (typically `/listings/<slug>`) |

The page slug is independent of the URL convention — you can have `template: dynamic_list, collection_type: posts, slug: "articles"` and the list lives at `/articles`. The dynamic-item page (the per-item page) is a SEPARATE recipe; see [`dynamic-item-page.md`](dynamic-item-page.md).

## Step 1 — verify items exist

```
content_list_posts({ status: "published", limit: 50 })
// → [{ id, title, slug, ... }, ...]
```

If empty, the dynamic-list page renders but visitors see "No posts yet." Solve by:
- Publishing at least one post first ([`blog-post.md`](blog-post.md)).
- OR adding a fallback `blocks[]` to the page (rendered ONLY when the collection is empty).

## Step 2 — create the page

```
content_create_page({
  title:    "Blog",
  slug:     "blog",
  template: "dynamic_list",
  collection_type: "posts",         # REQUIRED — must be one of: posts, docs, directory_listings
  seo_title:       "Blog — Acme",
  seo_description: "Engineering, product, and design notes from the Acme team.",
  blocks: [
    # Optional fallback / hero — rendered if collection is empty,
    # OR rendered above the list always (depends on theme template)
    {
      id: "blk_hero",
      type: "hero",
      data: {
        headline:    "From our team",
        subheadline: "Engineering, product, and design notes."
      }
    }
  ]
})
// → { id: "<page-uuid>", slug: "blog", template: "dynamic_list", collection_type: "posts", status: "draft" }
```

**Critical:** `collection_type` is REQUIRED when `template: "dynamic_list"` and must be one of `posts | docs | directory_listings`. Backend validator (`_validate_collection_pairing`) 422s on:
- `template: "dynamic_list"` without `collection_type` → 422 "collection_type required".
- `template: "default"` WITH `collection_type` → 422 "collection_type only valid for dynamic_list/dynamic_item".
- `collection_type: "foo"` → 422 "unknown collection_type".

Phase 11+12 is **opt-in** here. Pass `dry_run: true` for preview if you want to confirm.

## Step 3 — publish + deploy

```
content_publish_page({ page_id })
content_publish_page({ page_id, confirm_token })

content_deploy_site_production({ confirm_token })   # ~2-5s live
```

After deploy, `https://<tenant>/blog` renders the iterated list.

## How the iteration works (renderer internals)

The dynamic-list template (`templates/dynamic-list.liquid`) is a Liquid file that:

1. Fetches the collection at request time via the content API:
   - `posts` → `GET /content/posts?status=published&page=1&page_size=20`
   - `docs` → `GET /content/docs/tree` (recursive)
   - `directory_listings` → `GET /content/directory/listings?status=published`
2. Iterates the array in Liquid: `{% for item in collection %}<a href="{{ item_url }}">...</a>{% endfor %}`
3. Default item card layout (themable per-tenant).
4. Pagination via `?page=N` (default 20 per page; configurable in the template).

If you want different per-item rendering, customize `templates/dynamic-list.liquid` via `template_upsert` ([`section-override.md`](section-override.md) covers the pattern).

## URL routing — the item URL pattern

The dynamic-list page lives at `/<page-slug>`. The per-item URL pattern depends on `collection_type`:

| collection_type | Item URL |
|---|---|
| `posts` | `/blog/<post_slug>` (default; matches the `templates/blog-post.liquid` route) |
| `docs` | `/docs/<full_path>` (where `full_path` is the parent-id chain) |
| `directory_listings` | `/<page-slug>/<listing_slug>` |

For `posts` and `docs`, the URLs are conventional (and the default theme's renderer hard-codes them). For `directory_listings`, you typically pair the list page with a `template: "dynamic_item"` page using the same `slug` prefix. See [`dynamic-item-page.md`](dynamic-item-page.md).

## Common patterns

### Blog index with featured posts above the fold

```
content_create_page({
  title: "Blog",
  slug: "blog",
  template: "dynamic_list",
  collection_type: "posts",
  blocks: [
    {
      id: "blk_hero",
      type: "hero",
      data: { headline: "From the team", subheadline: "Latest writing" }
    }
    # The dynamic-list renders the iterated posts below the hero (template-dependent)
  ]
})
```

### Categorized directory list

```
content_create_page({
  title: "Local restaurants",
  slug: "restaurants",
  template: "dynamic_list",
  collection_type: "directory_listings",
  blocks: []
})
# The list iterates published directory_listings — pre-filter by category in the
# Liquid template if needed (template_inspect_block_fields / template_upsert).
```

### Empty-state with a CTA

The dynamic-list template typically renders the list + an empty state when collection is empty. To customize the empty state, override `templates/dynamic-list.liquid` via `template_upsert`. Add an `{% if collection.size == 0 %}` block with a CTA.

## Verify

```
content_visual_check({ page_url: "https://<tenant>/blog", viewport: "desktop" })
# Check screenshot shows the iterated list.
# Check body_text_preview contains item titles (server-rendered HTML).
```

## Anti-patterns

1. **`template: "dynamic_list"` without `collection_type`.** 422 "collection_type required". Always pair.
2. **`collection_type: "posts"` with `template: "default"`.** 422 — `collection_type` only applies to `dynamic_list` / `dynamic_item`.
3. **Trying to filter the iterated collection via the page's `blocks[]`.** Filtering happens in the Liquid template — `template_upsert` to customize. Page blocks are static (per-page), not per-item.
4. **Creating the dynamic-list page BEFORE any items exist.** It works, but visitors see "No posts yet." Always publish at least one item first.
5. **Using `dynamic_list` for a SINGLE-item display.** That's `dynamic_item` ([`dynamic-item-page.md`](dynamic-item-page.md)) — `dynamic_list` is for the index, `dynamic_item` is for the detail.
6. **Pointing two dynamic-list pages at the same `collection_type`.** Both render the same list at different URLs — confusing for visitors + SEO duplicate-content risk. Pick one URL for each collection.

## See also

- [`dynamic-item-page.md`](dynamic-item-page.md) — per-item detail page (the "/blog/<slug>" pattern)
- [`landing-page.md`](landing-page.md) — static page (alternative when no collection iteration)
- [`blog-post.md`](blog-post.md) — author the posts the list iterates
- [`docs-page.md`](docs-page.md) — author the docs the list iterates
- [`section-override.md`](section-override.md) — customize `templates/dynamic-list.liquid`
- [`../reference/block-types.md`](../reference/block-types.md) — page `blocks[]` shape
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*` tool catalog
