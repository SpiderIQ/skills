# recipes/content/dynamic-item-page

Create a dynamic ITEM page — resolves a single item by URL slug at request time. The "/blog/<post_slug>" or "/listings/<listing_slug>" pattern. Sibling to [`dynamic-list-page.md`](dynamic-list-page.md).

## When to use

- You have a blog list at `/blog` and need `/blog/<post_slug>` to render each post.
- You have a directory list at `/listings` and need `/listings/<listing_slug>` to render each listing.
- You want a 2-segment URL pattern (`/<prefix>/<item-slug>`) that resolves dynamically.

For the LIST page → [`dynamic-list-page.md`](dynamic-list-page.md). For a static one-off page → [`landing-page.md`](landing-page.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **The matching dynamic-list page exists** (typically — same `collection_type`, related slug prefix). Without it the item URLs work but visitors have no index.
3. **The collection has ≥1 published item** (otherwise every item URL 404s).
4. **Theme has `templates/dynamic-item.liquid`** (or per-collection variants: `templates/blog-post.liquid`, `templates/doc.liquid`, etc.). Default theme ships them.

## The 1-call path

```
content_create_page({
  title:    "Blog post detail",
  slug:     "blog",                  # the URL PREFIX, not a per-post slug
  template: "dynamic_item",
  collection_type: "posts"           # REQUIRED for dynamic_item
})
```

This is a SINGLE page that handles ALL `/blog/<any_slug>` URLs by resolving `<any_slug>` against published posts.

## The three collection types (same as dynamic_list)

| `collection_type` | Resolves slug against | URL pattern |
|---|---|---|
| `posts` | `content_posts.slug` | `/blog/<post_slug>` |
| `docs` | `content_docs.full_path` (recursive parent_id chain) | `/docs/<full_path>` |
| `directory_listings` | `content_directory_listings.slug` | `/<page-slug>/<listing_slug>` |

For `posts` and `docs`, the URL prefix is conventional (`/blog`, `/docs` — built into the default theme's routing). For `directory_listings`, the prefix is whatever `slug` you set on the dynamic-item page.

## Step 1 — verify the list page exists (recommended pairing)

```
content_list_pages({ status: "published" })
# Look for: { slug: "blog", template: "dynamic_list", collection_type: "posts" }
```

The dynamic-item page works without a list page — visitors hitting `/blog/<post>` resolve fine. But without a list at `/blog`, visitors landing on `/blog` 404. Pair them.

## Step 2 — create the item page

```
content_create_page({
  title:    "Blog post",            # mostly internal; per-item title comes from the resolved item
  slug:     "blog",                  # URL PREFIX — visitors hit /blog/<any-slug>
  template: "dynamic_item",
  collection_type: "posts"
  # NO blocks[] needed — the renderer uses templates/blog-post.liquid (or templates/dynamic-item.liquid)
})
// → { id: "<page-uuid>", slug: "blog", template: "dynamic_item", collection_type: "posts", status: "draft" }
```

**Critical:** `collection_type` is REQUIRED for `template: "dynamic_item"`. `_validate_collection_pairing` 422s on mismatched pairs.

`slug` is the URL **prefix**, NOT per-item. The renderer reads the second URL segment, looks up the item by `slug` (or `full_path` for docs), and renders.

`blocks[]` is OPTIONAL on dynamic-item pages — typically empty, because per-item rendering uses the matched item's content (post body, doc body, listing fields) via the theme template, NOT the page's `blocks`. If you ADD blocks, they render alongside (or above/below depending on the template) the resolved item content.

## Step 3 — publish + deploy

```
content_publish_page({ page_id })
content_publish_page({ page_id, confirm_token })

content_deploy_site_production({ confirm_token })
```

After deploy, `https://<tenant>/blog/<any-slug>` resolves dynamically.

## How the resolution works (renderer internals)

For `/blog/foo-bar` on a `dynamic_item` page:

1. Renderer matches URL → dynamic-item page at slug `blog`.
2. Extracts second segment `foo-bar`.
3. Queries content API: `GET /content/posts/foo-bar` (or `/content/docs/<full_path>` for docs, `/content/directory/listings/<slug>` for directory).
4. If found → renders via `templates/blog-post.liquid` (default theme has per-collection templates; falls back to `templates/dynamic-item.liquid` generic).
5. If NOT found → renders the 404 template (or `templates/blog-post.liquid` with empty item — depends on theme).

For `docs`, the URL can be N segments deep (`/docs/foo/bar/baz`) — the renderer concatenates segments after `/docs/` and matches `full_path`.

## Per-collection template files

The default theme has specific templates that take precedence over the generic `dynamic-item.liquid`:

| Collection | Template file (priority order) |
|---|---|
| `posts` | `templates/blog-post.liquid` → `templates/dynamic-item.liquid` |
| `docs` | `templates/doc.liquid` → `templates/dynamic-item.liquid` |
| `directory_listings` | `templates/listing.liquid` → `templates/dynamic-item.liquid` |

To customize per-collection rendering, override the specific file via `template_upsert` (or `content_override_section({ section_slug: "blog-post", ... })` for the per-post template).

## The 2-page pattern (list + item — typical setup)

```
# 1. The list page (renders the index)
content_create_page({
  title: "Blog",
  slug: "blog",
  template: "dynamic_list",
  collection_type: "posts",
  blocks: [{ id: "blk_hero", type: "hero", data: { headline: "Our writing" } }]
})

# 2. The item page (handles /blog/<post_slug> for every post)
content_create_page({
  title: "Blog post",
  slug: "blog",                # SAME slug as the list page — different template
  template: "dynamic_item",
  collection_type: "posts"
})

# 3. Publish + deploy both
content_publish_page({ page_id: list_page_id })
content_publish_page({ page_id: list_page_id, confirm_token })
content_publish_page({ page_id: item_page_id })
content_publish_page({ page_id: item_page_id, confirm_token })
content_deploy_site_production({ confirm_token })
```

The two pages share `slug: "blog"` but have different `template` values. The renderer's router distinguishes:
- Exact `/blog` → list page.
- `/blog/<anything>` → item page, resolved against `<anything>`.

## Common gotchas

### Why is `/blog/<post-slug>` returning 404?

- **The post isn't published.** Item pages only resolve published items.
- **The slug doesn't match.** Item slugs are flat (`^[a-z0-9][a-z0-9-]*$`). Check the post's actual slug via `content_get_post({ post_id })`.
- **No dynamic-item page exists.** You created the list but not the item page; visitors hit `/blog/<x>` → no match → 404.
- **Both list AND item page have `template: "dynamic_list"`.** The item page must be `template: "dynamic_item"`. Easy typo.

### Can I have two dynamic-item pages on different URL prefixes?

Yes:

```
# /blog/<post> resolved against posts
content_create_page({ slug: "blog", template: "dynamic_item", collection_type: "posts" })

# /articles/<post> ALSO resolved against posts (different prefix, same collection)
content_create_page({ slug: "articles", template: "dynamic_item", collection_type: "posts" })
```

Both `/blog/foo` and `/articles/foo` would render the same post. SEO risk (duplicate content); usually you want ONE prefix per collection.

### Can I mix in static content on a dynamic-item page?

The page's `blocks[]` render alongside the resolved item content. Useful for global elements (CTA at the bottom of every post, related-posts module). The per-item content comes from the matched row; `blocks[]` is static across all items.

## Verify

```
# Publish a test post first, then:
content_visual_check({ page_url: "https://<tenant>/blog/<test-post-slug>", viewport: "desktop" })
# body_text_preview should contain the post's title + body literals.
```

## Anti-patterns

1. **`template: "dynamic_item"` without `collection_type`.** 422 — `_validate_collection_pairing` rejects.
2. **Setting per-item content in the page's `blocks[]`.** Blocks are STATIC per dynamic-item page. Per-item content comes from the resolved row's content (post body, doc body, listing fields). To customize per-item rendering, override the template (`templates/blog-post.liquid` etc.).
3. **Creating a dynamic-item page WITHOUT a matching dynamic-list page.** The item page works, but visitors hitting the prefix URL (`/blog`) 404. Always create both for the common pattern.
4. **Using `dynamic_item` for a single-purpose page (e.g. one specific post displayed on its own page).** That's a static `template: "default"` page. Dynamic_item is for the GENERAL pattern of "URL segment → resolved item."
5. **Trying to nest dynamic items 3+ deep (`/blog/2026/05/post-slug`).** Not supported. Dynamic items match second-segment-onward in one chunk; docs match recursive `full_path`. For year/month dated URLs, you'd need a custom theme template or per-year list pages.
6. **Pointing `dynamic_item` at the same `collection_type` as another `dynamic_item` page on the same URL prefix.** Renderer matches one or the other — undefined behaviour. One dynamic-item per prefix per collection.

## See also

- [`dynamic-list-page.md`](dynamic-list-page.md) — the LIST sibling (typically created together)
- [`blog-post.md`](blog-post.md) — author the posts the item page renders
- [`docs-page.md`](docs-page.md) — author the docs the item page renders
- [`landing-page.md`](landing-page.md) — static one-off page (different surface)
- [`section-override.md`](section-override.md) — customize `templates/dynamic-item.liquid` or per-collection templates
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*` tool catalog
