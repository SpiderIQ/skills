# recipes/content/blog-post

Create + publish a blog post — title, body (Tiptap JSON), author, tags, categories, cover image, related posts, SEO. Publish flips it from draft to `/blog/<slug>`.

## When to use

- A tenant wants to ship a new blog post on their SpiderPublish site.
- You need author / category / tag entities attached (the relational ones, not legacy string tags).
- You want featured-flag, related-posts, OG image, SEO override — the full post surface.

For a 5-paragraph note where you just need the body and don't care about tagging: trim steps 2 + 3 + 4 + 5.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` and paste output (Exit 0 = safe; otherwise see [`../../_shared/auth.md`](../../_shared/auth.md)).
2. **Author exists** (if you want to attribute by `author_id`). `content_list_authors()` to check; `content_create_author()` to create. Free-text `author_name` works if you don't want author entities.
3. **Tags + categories exist** (if you want to use them — they're FKs). Both auto-create on update is NOT supported; explicit create first.

## The 6-call path

```
1. content_list_authors / _tags / _categories  — confirm FK targets exist
2. content_create_author / _tag / _category    — create missing FKs (skip if all exist)
3. content_create_post                         — write the draft (opt-in dry_run available)
4. content_get_post                            — confirm shape (no auditor here yet)
5. content_publish_post                        — flip status to published
6. content_deploy_site_production              — push to edge (only if you changed templates/settings; not strictly needed for posts — see below)
```

### 1. List existing authors / tags / categories

```
content_list_authors()
// → [{ id: "auth_...", name: "Jane Doe", slug: "jane-doe", role: "author", ... }, ...]

content_list_tags()
// → [{ id: "tag_...", name: "Engineering", slug: "engineering", post_count: 12 }, ...]

content_list_categories()
// → [{ id: "cat_...", name: "Product updates", slug: "product-updates", parent_id: null }, ...]
```

If your author / tag / category exists, grab the `id`s for step 3. If not, step 2.

### 2. Create missing FKs (skip if all exist)

```
# Author
content_create_author({
  name: "Jane Doe",
  slug: "jane-doe",
  bio:  "Engineer @ Acme. Writes about scaling Postgres.",
  avatar_url: "https://media.spideriq.ai/<tenant>/avatars/jane.jpg",
  role: "author"          // "author" | "editor" | "contributor" | "admin"
})
// → { id: "auth_..." }

# Tag (entity — preferred over legacy `tags: ["..."]` string list)
content_create_tag({
  name: "Engineering",
  slug: "engineering",
  description: "Engineering deep-dives",
  color: "#1f6feb"
})
// → { id: "tag_..." }

# Category
content_create_category({
  name: "Product updates",
  slug: "product-updates"
})
// → { id: "cat_..." }
```

All three are opt-in Phase 11+12 — mutate immediately by default. Pass `dry_run: true` if you want a preview.

### 3. Create the post

```
content_create_post({
  title: "How we moved 50M rows without downtime",
  slug:  "how-we-moved-50m-rows-without-downtime",
  body:  {
    type: "doc",
    content: [
      {
        type: "paragraph",
        content: [{ type: "text", text: "The story starts with a problem: the orders table was 50 million rows and growing." }]
      },
      {
        type: "heading",
        attrs: { level: 2 },
        content: [{ type: "text", text: "Why we couldn't just dump-and-reload" }]
      },
      {
        type: "paragraph",
        content: [{ type: "text", text: "Downtime budget was four hours. We measured a dump-restore at six." }]
      }
    ]
  },
  excerpt:      "A zero-downtime migration in three phases — dual-write, backfill, cutover.",
  tldr_summary: "Five sentences max. Mailchimp-style TL;DR above the body. Optional.",
  tag_ids:      ["tag_..."],            // preferred (entity tags)
  category_ids: ["cat_..."],
  cover_image_url:    "https://media.spideriq.ai/<tenant>/blog/zero-downtime-cover.jpg",
  featured_image_alt: "Diagram of dual-write / backfill / cutover phases",
  author_id:    "auth_...",
  is_featured:  false,
  related_post_ids: ["post_aaa...", "post_bbb..."],
  seo_title:       "Zero-downtime DB migration — Acme",
  seo_description: "How Acme moved 50M rows without a maintenance window."
})
// → { id: "post_...", slug: "how-we-moved-50m-rows-without-downtime", status: "draft" }
```

**Notes:**

- `title` is REQUIRED. `slug` auto-derives if omitted.
- `body` is a **Tiptap JSON document** — `{type: "doc", content: [...]}`. Strings here are silently rendered empty; pass an object. If you don't want to learn Tiptap, set `body: {type: "doc", content: []}` and use the dashboard's editor to populate it.
- `tag_ids` (entity tags, FK to `content_tags`) is the preferred field. Legacy `tags: ["string", ...]` still works but doesn't get post-counts in the dashboard.
- `category_ids` is a LIST — pass `[]` to clear. Posts can be in multiple categories.
- `cover_image_url` MUST end in `_url` to persist (catch from earlier sessions: `cover_image` silently drops).
- `is_featured` is the field; **not** `featured` (silent-no-op).
- `related_post_ids` order is preserved — the first is shown first.
- Phase 11+12 is **opt-in**. The call above mutates immediately. Pass `dry_run: true` for preview + confirm flow.

### 4. Confirm the shape

```
content_get_post({ post_id: "post_..." })
// → { id, title, slug, body, author: {...}, tags: [...], categories: [...], status: "draft", ... }
```

Read it back — confirm the author / tags / categories joined correctly, the cover image URL persisted, the Tiptap JSON didn't lose any nodes.

### 5. Publish

```
content_publish_post({ post_id: "post_..." })
// → { status: "published", published_at: "2026-05-24T..." }
```

`content_publish_post` is **immediate** — no dry_run/confirm gate on publish for posts (different from pages, where publish defaults to dry_run=true). If you need preview-first, use `content_update_post_status({ post_id, status: "published" })` after a `content_update_post` with `dry_run: true`.

### 6. Deploy (only if you ALSO changed templates / settings)

Blog posts render via the content API at request time — the Liquid template fetches `/content/posts/<slug>` and renders. **You do NOT need to redeploy the site for a new post to be visible.** The post is live as soon as `content_publish_post` returns.

You only need `content_deploy_site_production` if you also:
- Changed `templates/blog-post.liquid` (the post-page chrome).
- Changed `content_settings` (site name, default OG image, navigation).
- Changed `templates/blog.liquid` (the listing page chrome).

For a post-only change: skip deploy. The post is at `https://<tenant>/blog/<slug>` immediately.

## Verify

```
content_visual_check({
  page_url: "https://<tenant>/blog/<slug>",
  viewport: "desktop"
})
// → { success: true, screenshot_url, body_text_preview, console_errors: [] }
```

Check:
- `body_text_preview` contains the post title literal.
- `screenshot_url` shows your cover image + author + body.
- `console_errors` is empty.

(No `dom.shadow_hosts` assertion here — blog posts don't use shadow-DOM components by default.)

## Update an existing post

```
content_update_post({
  post_id: "post_...",
  body:    { type: "doc", content: [...]},        // full Tiptap doc; partial body NOT supported
  tag_ids: ["tag_aaa", "tag_bbb"]                 // [] to clear
})
```

Phase 11+12 is **opt-in** here — pass `dry_run: true` if you want to preview before mutating. Updating the body doesn't re-publish; status stays at whatever it was.

## Unpublish / archive

```
content_unpublish_post({ post_id: "post_..." })            # → draft
content_update_post_status({ post_id, status: "archived" }) # → archived (hidden from listings)
```

To delete entirely: `content_delete_post({ post_id })`. Phase 11+12 is **opt-in** on delete for posts (compare to pages where delete defaults to dry_run=true).

## Anti-patterns

1. **Passing `body` as a string.** The renderer expects Tiptap JSON. Strings silently render empty.
2. **Using `featured: true` instead of `is_featured: true`.** Silent-no-op; the post doesn't get featured.
3. **`cover_image` instead of `cover_image_url`.** Field name MUST end in `_url`. Silent-no-op otherwise.
4. **Forgetting to publish.** `content_create_post` lands at `status: "draft"`. The post is at `/blog/<slug>` only after `content_publish_post`.
5. **Redeploying the site for a post-only change.** Posts render live from the API. Deploy is only needed for template / settings / nav changes.
6. **Passing `tags: ["engineering"]` and `tag_ids: [...]`.** Use ONE. `tag_ids` (entity FKs) is the modern path; `tags` is legacy strings. Mixing produces ambiguous post-tag joins.

## See also

- [`landing-page.md`](landing-page.md) — block-based pages (different surface; pages don't use Tiptap)
- [`docs-page.md`](docs-page.md) — docs pages (same Tiptap body shape; different tree)
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — gate flavours per mutation
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*` post tools
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
- catalog/CLAUDE.md → "Public API Endpoints" — `/content/posts*` routes
