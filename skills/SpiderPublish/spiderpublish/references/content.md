# Content — pages, posts, docs, navigation, domains, settings

The core CMS surface. Authoring (create/update/delete/publish/list-with-drafts) goes through
`POST/PATCH/GET /api/v1/dashboard/content/...` (or the project-scoped
`/api/v1/dashboard/projects/{pid}/content/...`) with a Bearer PAT; genuinely public reads
(search, `/help`, vayapin) live under `/api/v1/content/...`. Almost every recipe ends by
deploying — that pipeline lives once in [`deploy-protocol.md`](deploy-protocol.md); don't
re-explain it. Block shapes live in [`block-types.md`](block-types.md). Read those two first.

**Read when:** building or editing a landing page, blog post, docs page, nav menu, custom
domain, site settings, a dynamic (data-bound) page, a scroll-video hero, or duplicating /
locking / restoring / exporting a page.


---

## Landing Page

Author + publish a marketing landing page from scratch — hero, features, social proof, CTA, deploy. This is the **canonical** block-based authoring recipe; every other content recipe cascades from here.

### When to use

- A tenant needs a new marketing landing page on their SpiderPublish site (`/`, `/features`, `/pricing`, a campaign URL like `/launch`).
- You want to compose the page from the bundled block types — no custom components needed.
- You're new to SpiderPublish authoring and need the end-to-end shape, including: block-field hygiene, dry_run preview, publish, deploy, visual verify.

If you want to *insert one marketplace section into an existing page* → [`landing-page-with-components.md`](#) (queued for v0.4.0) or just use `page_insert_section` + `content_get_component_by_slug`. If you want to *clone a curated starter site* → use `content_apply_site_template` instead.

### Prerequisites

1. **Tenant scope verified.** Run the script and paste output:
   ```bash
   ./scripts/verify-tenant-scope.sh
   ```
   Exit 0 → safe. Anything else → fix per [`../../_shared/auth.md`](../SKILL.md) before continuing.
2. **Discovery endpoints cached.** Fetch once per session:
   ```bash
   curl -s https://spideriq.ai/api/v1/content/help/block-fields | jq 'keys'
   ```
   Or via MCP: `template_inspect_block_fields()` — see [`../reference/block-types.md`](block-types.md).
3. **MCP server reachable.** `@spideriq/mcp-publish` (87 tools, atomic) OR `@spideriq/mcp` (134+ kitchen-sink) — see [`../reference/tool-surface.md`](tool-surface.md).

### The 5-call path

```
1. (optional) template_inspect_block_fields     — confirm field names per block
2. content_create_page                          — create the draft with blocks (or pass dry_run=true)
3. content_get_page  (audit_level: "warnings")  — read auditor output for silent-blank traps
4. content_publish_page                         — draft → published (defaults to dry_run=true)
5. content_deploy_site_production (or _site)   — push to CF edge; site live in ~2-5s
```

Plus one verification step at the end (`content_visual_check`). Estimated ~30 min for a 4-block page including iteration.

#### 1. Inspect block fields (optional but recommended)

Skip this if you're using only `hero` + `features_grid` + `cta_section` — they're committed-to-memory shapes. For anything else (`comparison_table`, `pricing_table`, the `rich_text` content-vs-html footgun), inspect first:

```
template_inspect_block_fields({ block_type: "comparison_table" })
// → { fields: [...], _aliases: {...}, _anti_patterns: [...], _notes: "..." }
```

The `_aliases` map (e.g. `{"title": "headline"}`) catches the most-common typos before you hit the silent-blank trap.

#### 2. Create the page (draft)

```
content_create_page({
  title: "Build conversational forms with SpiderPublish",
  slug:  "build-conversational-forms",
  template: "default",
  blocks: [
    {
      id:   "blk_hero",
      type: "hero",
      data: {
        headline:    "Conversational forms, hosted on your domain.",
        subheadline: "Multi-step + conditional logic + cal.com bookings. Edge-rendered. No third-party iframe.",
        cta_primary:   { label: "Start free trial", url: "/signup" },
        cta_secondary: { label: "See a demo",       url: "/demo" },
        background_image_url: "https://media.spideriq.ai/<tenant>/hero-bg.jpg",
        style: "centered"
      }
    },
    {
      id:   "blk_features",
      type: "features_grid",
      data: {
        headline: "Why teams switch",
        columns:  3,
        features: [
          { icon: "rocket", title: "Ship in minutes",    description: "Pick a template, deploy to your domain." },
          { icon: "lock",   title: "Five-lock defense",  description: "No silent cross-tenant writes." },
          { icon: "scale",  title: "One binary, N sites", description: "Liquid templates on Cloudflare's edge." }
        ]
      }
    },
    {
      id:   "blk_proof",
      type: "stats_bar",
      data: {
        stats: [
          { value: "12k+", label: "Forms shipped" },
          { value: "99.9%", label: "Renderer uptime" },
          { value: "2-5s", label: "Deploy time" }
        ]
      }
    },
    {
      id:   "blk_cta",
      type: "cta_section",
      data: {
        headline:    "Ready to ship your first form?",
        description: "Start free; no card needed.",
        cta_primary: { label: "Start free trial", url: "/signup" }
      }
    }
  ],
  seo_title:       "Conversational forms — SpiderPublish",
  seo_description: "Build, host, and embed multi-step forms on your own domain. No third-party iframe."
})
// → { id: "<page-uuid>", slug: "build-conversational-forms", status: "draft", ... }
```

**Notes:**

- `title` is REQUIRED. Everything else is optional — but `slug`, `blocks[]`, `seo_title`, `seo_description` matter for the result you want.
- `slug` is flat — `^[a-z0-9][a-z0-9-]*$`. No `/`. Nested URLs not supported here; docs use `parent_id` chains (see [`docs-page.md`](content.md#docs-page)).
- `template` selects which `templates/<name>.liquid` renders. `default` is fine for most landing pages. Use `landing` for header-only chrome, `blank` for full-canvas, or your own custom template name. **NOT** `forms-standalone` / `booking-standalone` — those are server-side-picked for `/f/<id>` (see Rule 65).
- Phase 11+12 is **opt-in** here. The call above mutates immediately. Pass `dry_run: true` to preview:

  ```
  content_create_page({ ..., dry_run: true })
  // → { preview, confirm_token: "cft_...", expires_at, snapshot_hash }
  ```

  Then call again with `{ ..., confirm_token: "cft_..." }` to confirm. See [`../reference/deploy-protocol.md`](deploy-protocol.md).

#### 3. Audit the draft (free)

```
content_get_page({ page_id: "<page-uuid>", audit_level: "warnings" })
// → { id, title, blocks, _page_audit: { errors: [], warnings: [...], info: [] } }
```

Read `_page_audit.warnings`. The auditor walks 10 rules; the one to watch for is `render.unused_field_in_default_theme` — **silent-blank section**. If you wrote `data.title` instead of `data.headline` on the hero, you'll see:

```json
{
  "rule_id": "render.unused_field_in_default_theme",
  "severity": "warning",
  "block_id": "blk_hero",
  "block_type": "hero",
  "unused_field": "title",
  "hint": "Did you mean 'headline'?"
}
```

Fix with `content_update_page` and re-audit. If `_page_audit.errors` is empty AND `_page_audit.warnings` has nothing about `render.unused_field_in_default_theme`, your blocks render. (The auditor also catches scroll-sequence empty frames, latent Tier 3 components missing dependencies, etc. — read every warning.)

#### 4. Publish (draft → published)

```
# Step 4a — dry_run (default behaviour — content_publish_page defaults dry_run=true)
content_publish_page({ page_id: "<page-uuid>" })
// → { dry_run: true, preview: {...}, confirm_token: "cft_...", expires_at, snapshot_hash }

# Step 4b — confirm
content_publish_page({
  page_id:       "<page-uuid>",
  confirm_token: "cft_..."
})
// → { status: "published", version_id: 1, published_at: "..." }
```

The publish creates a version snapshot in `content_page_versions` — you can roll back with `content_restore_page_version` if needed. See [`../reference/deploy-protocol.md`](deploy-protocol.md) for the gate semantics.

#### 5. Deploy the site

A published page is in STORE but not yet in front of end users — SpiderPublish's SERVE layer is Cloudflare Workers, which need a deploy to pick up the new content snapshot. **Run readiness first**:

```
content_deploy_readiness()
// → { ready: true, blocking: [], warnings: [...] }
```

If `ready: false` and `blocking: [...]` is non-empty, fix every blocking item (usually: domain not verified, settings.site_name missing, no published pages, no `home` page). Then:

```
# Stage 1 — preview the deploy
content_deploy_site_preview()
// → { preview_url: "https://preview-XXX.sites.spideriq.ai", confirm_token, expires_at, preview: {pages: 12, ...} }

# Stage 2 — production
content_deploy_site_production({ confirm_token: "cft_..." })
// → { status: "live", version_id: 48 }
```

Site is live in ~2-5s on the tenant's primary domain (or `<tenant>.sites.spideriq.ai` if no custom domain yet).

### Verify (don't trust the 200)

```
content_visual_check({
  page_url: "https://<tenant>/<slug>",
  viewport: "desktop"
})
// → { success: true, screenshot_url, dom: { shadow_hosts: [...] }, body_text_preview, console_errors: [] }
```

For a content page (no form blocks), check:
- `body_text_preview` includes your hero headline literal (the SSR HTML is the parent page).
- `console_errors` is empty (any errors here mean something broke client-side).
- `screenshot_url` looks like you expect when you open it.

**If the page contains a form block** (`{type: "component", component_slug: "spideriq-form-embed", ...}`) or you visual-check a form-rendering URL: assert on `dom.shadow_hosts.includes("spideriq-form")`, NEVER on `body_text_preview` (cross-origin iframe is opaque). Rule 62 — see [`../reference/booking-model.md`](booking-model.md#visual-check).

### Iterate (the realistic loop)

You almost never get it right first time. The healthy loop:

```
1. content_create_page (or _update_page)  — adjust blocks
2. content_get_page (audit_level)         — read warnings
3. content_publish_page (dry_run + confirm) — promote draft
4. content_deploy_site_production         — push to edge
5. content_visual_check                    — eyeball + assert
6. Fix → goto 1
```

For tighter loops without re-deploying, use `template_preview` — renders a template with mock data without persisting OR deploying. Useful for testing template overrides without affecting other pages.

### Anti-patterns

1. **Wrong `data.*` field names render BLANK, not 422.** `data.title` on hero, `data.items` on features_grid, `data.cta_text` anywhere → page publishes silently broken. **Always run `template_inspect_block_fields(block_type)` first** OR read [`../reference/block-types.md`](block-types.md). F-7 / Rule 65.
2. **`{type:'rich_text', data:{content:'<string>'}}` → 422.** Use `data.html` (string) or `data.content` (Tiptap JSON **object**). PR-#841 made this loud.
3. **`{type:'component', data:{slug:'x'}}` → 422.** `component_slug` is TOP-LEVEL on the block, not under `data`.
4. **`template: "forms-standalone"` / `"booking-standalone"` on a content page.** Those are server-side-picked by the `/f/<id>` route from the flow's `kind`. Setting them on a normal page binds a chrome that probably isn't what you want. Use `default`, `blank`, `landing`, or a custom template name. Rule 65.
5. **Skipping `content_deploy_readiness` before deploy.** Deploy will 4xx if blocking items aren't resolved; readiness probe gives you the list cheaply.
6. **Asserting on `body_text_preview` when the page has a form block.** Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.

### See also

- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the two-phase pipeline + ConfirmTokenError envelopes
- [`../reference/block-types.md`](block-types.md) — every block-type + `data.*` field + alias map
- [`../reference/tool-surface.md`](tool-surface.md) — MCP package picker + discovery endpoints
- [`../reference/booking-model.md`](booking-model.md) — `kind='form'` URL surface + Rule 62 visual-check
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth + tenant binding
- [`apply-theme.md`](templates-deploy.md#apply-theme) — change the visual identity site-wide
- [`navigation.md`](content.md#navigation) — add this page to the header / footer menu
- [`landing-page-with-components.md`](content.md) — compose with marketplace sections (v0.4.0)
- [`preview-iteration.md`](content.md#preview-iteration) — fast preview loop without full deploy


---

## Blog Post

Create + publish a blog post — title, body (Tiptap JSON), author, tags, categories, cover image, related posts, SEO. Publish flips it from draft to `/blog/<slug>`.

### When to use

- A tenant wants to ship a new blog post on their SpiderPublish site.
- You need author / category / tag entities attached (the relational ones, not legacy string tags).
- You want featured-flag, related-posts, OG image, SEO override — the full post surface.

For a 5-paragraph note where you just need the body and don't care about tagging: trim steps 2 + 3 + 4 + 5.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` and paste output (Exit 0 = safe; otherwise see [`../../_shared/auth.md`](../SKILL.md)).
2. **Author exists** (if you want to attribute by `author_id`). `content_list_authors()` to check; `content_create_author()` to create. Free-text `author_name` works if you don't want author entities.
3. **Tags + categories exist** (if you want to use them — they're FKs). Both auto-create on update is NOT supported; explicit create first.

### The 6-call path

```
1. content_list_authors / _tags / _categories  — confirm FK targets exist
2. content_create_author / _tag / _category    — create missing FKs (skip if all exist)
3. content_create_post                         — write the draft (opt-in dry_run available)
4. content_get_post                            — confirm shape (no auditor here yet)
5. content_publish_post                        — flip status to published
6. content_deploy_site_production              — push to edge (only if you changed templates/settings; not strictly needed for posts — see below)
```

#### 1. List existing authors / tags / categories

```
content_list_authors()
// → [{ id: "auth_...", name: "Jane Doe", slug: "jane-doe", role: "author", ... }, ...]

content_list_tags()
// → [{ id: "tag_...", name: "Engineering", slug: "engineering", post_count: 12 }, ...]

content_list_categories()
// → [{ id: "cat_...", name: "Product updates", slug: "product-updates", parent_id: null }, ...]
```

If your author / tag / category exists, grab the `id`s for step 3. If not, step 2.

#### 2. Create missing FKs (skip if all exist)

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

#### 3. Create the post

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

#### 4. Confirm the shape

```
content_get_post({ post_id: "post_..." })
// → { id, title, slug, body, author: {...}, tags: [...], categories: [...], status: "draft", ... }
```

Read it back — confirm the author / tags / categories joined correctly, the cover image URL persisted, the Tiptap JSON didn't lose any nodes.

#### 5. Publish

```
content_publish_post({ post_id: "post_..." })
// → { status: "published", published_at: "2026-05-24T..." }
```

`content_publish_post` is **immediate** — no dry_run/confirm gate on publish for posts (different from pages, where publish defaults to dry_run=true). If you need preview-first, use `content_update_post_status({ post_id, status: "published" })` after a `content_update_post` with `dry_run: true`.

#### 6. Deploy (only if you ALSO changed templates / settings)

Blog posts render via the content API at request time — the Liquid template fetches `/content/posts/<slug>` and renders. **You do NOT need to redeploy the site for a new post to be visible.** The post is live as soon as `content_publish_post` returns.

You only need `content_deploy_site_production` if you also:
- Changed `templates/blog-post.liquid` (the post-page chrome).
- Changed `content_settings` (site name, default OG image, navigation).
- Changed `templates/blog.liquid` (the listing page chrome).

For a post-only change: skip deploy. The post is at `https://<tenant>/blog/<slug>` immediately.

### Verify

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

### Update an existing post

```
content_update_post({
  post_id: "post_...",
  body:    { type: "doc", content: [...]},        // full Tiptap doc; partial body NOT supported
  tag_ids: ["tag_aaa", "tag_bbb"]                 // [] to clear
})
```

Phase 11+12 is **opt-in** here — pass `dry_run: true` if you want to preview before mutating. Updating the body doesn't re-publish; status stays at whatever it was.

### Unpublish / archive

```
content_unpublish_post({ post_id: "post_..." })            # → draft
content_update_post_status({ post_id, status: "archived" }) # → archived (hidden from listings)
```

To delete entirely: `content_delete_post({ post_id })`. Phase 11+12 is **opt-in** on delete for posts (compare to pages where delete defaults to dry_run=true).

### Anti-patterns

1. **Passing `body` as a string.** The renderer expects Tiptap JSON. Strings silently render empty.
2. **Using `featured: true` instead of `is_featured: true`.** Silent-no-op; the post doesn't get featured.
3. **`cover_image` instead of `cover_image_url`.** Field name MUST end in `_url`. Silent-no-op otherwise.
4. **Forgetting to publish.** `content_create_post` lands at `status: "draft"`. The post is at `/blog/<slug>` only after `content_publish_post`.
5. **Redeploying the site for a post-only change.** Posts render live from the API. Deploy is only needed for template / settings / nav changes.
6. **Passing `tags: ["engineering"]` and `tag_ids: [...]`.** Use ONE. `tag_ids` (entity FKs) is the modern path; `tags` is legacy strings. Mixing produces ambiguous post-tag joins.

### See also

- [`landing-page.md`](content.md#landing-page) — block-based pages (different surface; pages don't use Tiptap)
- [`docs-page.md`](content.md#docs-page) — docs pages (same Tiptap body shape; different tree)
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — gate flavours per mutation
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*` post tools
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth
- catalog/CLAUDE.md → "Public API Endpoints" — `/content/posts*` routes


---

## Docs Page

Add a page to the docs tree — title, body (Tiptap JSON), parent doc for nesting, computed `full_path`. Powers the `/docs/*` URL surface on every SpiderPublish tenant.

### When to use

- A tenant has a `docs/` section on their site and wants to add a new page.
- You need parent/child nesting: a sub-page under an existing parent (`/docs/getting-started/install` under `/docs/getting-started`).
- You want to reorder docs in the sidebar (via `sort_order`).

For a one-off marketing page that's NOT under `/docs/*` → use [`landing-page.md`](content.md#landing-page). For a blog post → [`blog-post.md`](content.md#blog-post). Docs are a separate tree with their own router (Liquid template `docs.liquid` → `templates/doc.liquid` for individual pages).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (paste output; exit 0 = safe).
2. **Parent doc exists** (if you're nesting). Discover with `content_docs_tree()`. If you're adding a top-level doc, no parent needed.
3. **Theme has `templates/docs.liquid` and `templates/doc.liquid`.** Default theme ships both; check `template_list()` if you've customized.

### The 3-call path

```
1. content_docs_tree                 — see the existing tree + find parent_id
2. content_create_doc                — add the new doc (immediate; no dry_run default)
3. content_get_settings (optional)   — confirm site_url for the public URL
```

No publish step — docs go live the moment they're created. No separate deploy needed (docs render at request time, like blog posts).

### Styling docs (you do NOT have to rewrite the template)

Docs colors/accent come from **site settings**, not from editing the template. `content_update_settings({ primary_color, surface_color, surface_elevated_color, subtle_color, body_text_color, heading_color })` injects CSS custom properties (`--primary`, `--surface`, `--body-text`, `--heading` …) into every page's `<head>`, **including `/docs/*`** — the default `doc.liquid` uses them for links, borders, and text. For extra CSS, use `custom_head_scripts` (a `<style>` block; requires deploy). Only reach for a full `template_upsert('templates/doc.liquid', …)` when you need to change *structure* (sidebar width, breadcrumbs).

> If `template_get('templates/doc.liquid')` returns a big inline-CSS template, that's **your tenant's** prior customization stored in KV — not what SpiderPublish ships. The default doc theme is small, var-driven, and has no `!important`.

#### 1. Get the tree

```
content_docs_tree()
// → [
//   { id: "doc_aaa", title: "Getting started", slug: "getting-started", full_path: "getting-started",
//     children: [
//       { id: "doc_bbb", title: "Install", slug: "install", full_path: "getting-started/install", children: [] }
//     ]},
//   { id: "doc_ccc", title: "API reference", slug: "api-reference", full_path: "api-reference", children: [...] }
// ]
```

The tree is hierarchical. Each node carries:
- `id` — UUID handle. Pass as `parent_id` when creating a child.
- `slug` — flat segment (`getting-started`, `install`). NOT the full path.
- `full_path` — backend-computed concatenation of slugs from root. The URL path is `/docs/{full_path}`.
- `children[]` — recursive.

If you want to add a sub-page under "Getting started", grab `doc_aaa`'s id.

#### 2. Create the doc

```
content_create_doc({
  title:     "Authentication",
  slug:      "authentication",
  body:      {
    type: "doc",
    content: [
      {
        type: "paragraph",
        content: [{ type: "text", text: "All API calls use Bearer token auth." }]
      },
      {
        type: "code_block",
        attrs: { language: "bash" },
        content: [{ type: "text", text: "curl -H \"Authorization: Bearer cli_id:key:secret\" https://spideriq.ai/api/v1/..." }]
      }
    ]
  },
  parent_id: "doc_aaa"               // omit for a top-level doc
})
// → { id: "doc_...", slug: "authentication", parent_id: "doc_aaa", full_path: "getting-started/authentication", ... }
```

**Notes:**

- `title` is REQUIRED. `slug` auto-derives if omitted.
- `body` is **Tiptap JSON** (`{type: "doc", content: [...]}`) — same shape as blog post body. Strings render empty.
- `parent_id` is OPTIONAL. Omit for a top-level doc; pass a parent's `id` to nest. **Don't** pass a slug or full_path — only UUIDs.
- The backend computes `full_path` from `parent_id` chain — you can't set it directly. To "move" a doc to a different parent, update its `parent_id` (via the REST API or dashboard; no MCP `content_update_doc` yet — follow-up).
- **No dry_run/confirm gate** on `content_create_doc` — it mutates immediately.

#### 3. (Optional) confirm the public URL

```
content_get_settings()
// → { site_name, ..., primary_domain: "<tenant>.com", ... }
```

The new doc is at `https://<primary-domain>/docs/getting-started/authentication`. If `primary_domain` is null, the URL is `https://<tenant>.sites.spideriq.ai/docs/...`.

### Reorder docs in the sidebar

Sibling ordering uses `sort_order` (integer; ascending). To reorder:

- Set `sort_order: 0, 10, 20, ...` (gaps of 10 leave room for insertions).
- The REST API is `PATCH /content/docs/{id} { sort_order: N }`. No first-party MCP tool yet (follow-up).
- Dashboard UI: drag-and-drop the tree, which writes `sort_order` per node.

Default behaviour: docs without explicit `sort_order` sort by `created_at`.

### Duplicate a doc

```
content_duplicate_doc({
  doc_id:   "doc_...",
  new_slug: "duplicate-of-authentication"   // optional; defaults to <orig-slug>-copy
})
// → { id: "doc_..." (new), parent_id: same as source, full_path: ..., status: "draft" }
```

Phase 11+12 is **opt-in** on duplicate.

### Update a doc body

There's no first-party `content_update_doc` MCP tool yet (queued follow-up). Two paths today:

1. **Dashboard:** open the doc in Content Studio's docs editor.
2. **REST:** `PATCH /api/v1/dashboard/projects/{pid}/content/docs/{id}` with `{ body: {...}, title?: "..." }`.

### Verify

```
content_visual_check({
  page_url: "https://<tenant>/docs/<full_path>",
  viewport: "desktop"
})
// → { success: true, body_text_preview: "...your title literal...", console_errors: [] }
```

Check `body_text_preview` contains your title + a snippet from the body.

### Anti-patterns

1. **Passing `body` as a string.** Tiptap JSON — `{type: "doc", content: [...]}`. Strings silently render empty.
2. **Passing `slug` with `/` in it.** Slugs are FLAT segments (`^[a-z0-9][a-z0-9-]*$`). The URL hierarchy comes from `parent_id` chains, not slug paths. `slug: "getting-started/install"` either 422s on validate or silently flattens.
3. **Setting `full_path` directly.** Server-computed. Pass `parent_id` instead.
4. **Trying to reorder via `slug` rename.** Use `sort_order`. Renaming a slug breaks every external link to the doc.
5. **Forgetting to add the new doc to the docs sidebar nav.** Docs auto-appear in the docs tree (template iterates `content_docs_tree`), so you don't need to add it to a menu. But if your theme has a custom sidebar nav with hand-curated items, you'll need [`navigation.md`](content.md#navigation).

### See also

- [`blog-post.md`](content.md#blog-post) — same Tiptap body shape; different tree (posts not docs)
- [`landing-page.md`](content.md#landing-page) — block-based pages (different surface)
- [`navigation.md`](content.md#navigation) — docs_sidebar menu (if you've customized it)
- [`../reference/tool-surface.md`](tool-surface.md) — full `content_*` doc tool list
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth
- catalog/CLAUDE.md → "Public API Endpoints" — `/content/docs*` routes


---

## Navigation

Edit the header / footer / docs-sidebar menus in place. PUT semantics — pass the full menu, server replaces in-place. Items can nest.

### When to use

- A tenant wants to add a new page to their site's main nav (`Home / Features / Pricing / Blog` → add `Customers`).
- You're restructuring the footer (split into "Product / Company / Resources" columns).
- You're hand-curating the docs sidebar (instead of auto-generated from the docs tree).
- You're adding external links (to GitHub, the public docs site, a third-party tool).

The three menu locations are fixed: `header`, `footer`, `docs_sidebar`. Custom locations (e.g. `mobile_drawer`) need theme template changes — they're not configurable via this MCP tool.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Target pages / posts exist.** Items reference URLs (`/about`, `/blog`, `https://github.com/...`). If you point to a page that doesn't exist, the nav still renders the link — clicking 404s.
3. **Theme template uses the menu.** Default theme's `sections/header.liquid` renders the `header` nav. If you've customized + dropped the `{% for item in navigation.header.items %}` block, the menu data persists but nothing renders.

### The 2-call path

```
1. content_get_navigation({ location })   — see current items
2. content_update_navigation({ location, items: [...] })   — replace in place (PUT semantics)
```

No deploy step needed for nav-only changes — the renderer reads navigation live from the API per request. (Same as posts.) Deploy only if you changed templates.

#### 1. Get the current menu

```
content_get_navigation({ location: "header" })
// → {
//   location: "header",
//   items: [
//     { label: "Features",  url: "/features", target: "_self", icon: null, children: [] },
//     { label: "Pricing",   url: "/pricing",  target: "_self", icon: null, children: [] },
//     { label: "Blog",      url: "/blog",     target: "_self", icon: null, children: [] }
//   ],
//   updated_at: "2026-05-..."
// }
```

Read it back to know the current shape. `location` must be one of: `header`, `footer`, `docs_sidebar`. The MCP tool 422s on anything else.

#### 2. Update the menu (full replace)

```
content_update_navigation({
  location: "header",
  items: [
    { label: "Features", url: "/features" },
    { label: "Pricing",  url: "/pricing" },
    {
      label: "Customers",
      url:   "/customers",
      children: [
        { label: "Case studies", url: "/customers/case-studies" },
        { label: "Testimonials", url: "/customers/testimonials" }
      ]
    },
    { label: "Blog", url: "/blog" },
    { label: "Docs", url: "/docs" }
  ]
})
// → { location: "header", items: [...], updated_at: "..." }
```

**Item shape:**

| Field | Type | Notes |
|---|---|---|
| `label` | string | Visible link text. |
| `url` | string | Absolute (`/about`, `/blog/foo`) or external (`https://github.com/...`). |
| `target` | `"_self" | "_blank"` | Optional; default `"_self"`. Use `"_blank"` for external links. |
| `icon` | string | Optional. Some themes render an icon prefix (`"github"`, `"docs"`). |
| `children` | array of items | Optional. Nested dropdown — typically rendered as a hover-menu in the header, an expandable group in footer / docs-sidebar. |
| `source` | object | Optional **binding** — makes the item render from the page tree instead of from hand-authored `children`. See "Three item modes" below. |

**PUT semantics:** `content_update_navigation` REPLACES the menu wholesale. Pass the full `items[]` array — anything you omit is gone. If you only want to add one item: get the current, append, update.

No dry_run/confirm gate by default — `content_update_navigation` mutates immediately.

### Three item modes

Every item is one of three things. They mix freely inside one menu.

| Mode | Write it as | What renders |
|---|---|---|
| **hand-authored** | no `source` | exactly what you wrote. The original behaviour — unchanged. |
| **site-bound** | `source: {kind:"site", depth:2}` | the whole page tree |
| **folder-bound** | `source: {kind:"folder", folder_id:"<uuid>", depth:2}` | one folder's published descendants |

```
content_update_navigation({
  location: "header",
  items: [
    { label: "Pricing", url: "/pricing" },                                  // hand-authored
    { label: "Guides",  source: { kind: "folder",                           // folder-bound
                                  folder_id: "3f2b…", depth: 2 } }
  ]
})
```

**Why bind instead of hand-listing a folder's pages:** a bound item is expanded
**server-side on every public read**, so publishing, renaming, reordering or
archiving a page updates the live menu with **no menu edit**. And only
**published, non-folder** descendants are ever emitted — a draft cannot leak
into a public menu, which is the failure mode hand-curated menus have.

`depth` is `1`–`3` (default `2`) and counts levels *below* the bound item.
Deeper is rejected with a 422.

> ⚠️ **`content_get_navigation` returns bindings UN-EXPANDED — that is correct.**
> It reads the dashboard route, so a bound item comes back with `source` set and
> `children` empty. The expansion only happens on the public read the renderer
> uses. Round-trip the **binding**; never "helpfully" replace it with a snapshot
> of its expanded children — that freezes the menu and it stops tracking the tree.

### Folders and their index page

A **folder** is a page row with `is_folder: true` — an organizational node in
the page tree with no live URL of its own. It is never rendered, sitemapped, or
listed in `llms.txt`.

```
1. content_create_page({ title: "Guides", is_folder: true })      → folder id
2. content_update_page({ page_id: <a page>, parent_id: <folder id> })   ← fill it
3. content_update_navigation({ location: "header", items: [
     { label: "Guides", source: { kind: "folder", folder_id: <folder id> } }
   ]})
```

Discover folder ids with `content_list_pages` — rows carry `is_folder` and
`parent_id`.

**Which page does the folder itself link to?** In order:

1. `index_page_id`, **if** it is still a published, non-folder *direct child*;
2. otherwise the folder's first published child by `sort_order`;
3. otherwise nothing — the item's `url` is `null` and themes render it as a
   label-only group header, never a dead link.

Set the override with `content_update_page({ page_id: <folder id>,
index_page_id: <child page id> })`. Folders only — setting it on a normal page,
or pointing a folder at itself, is rejected with a 400. It **self-heals**:
unpublish, archive, or move the target out of the folder and resolution falls
back to (2) silently, with no stale link.

### Common patterns

#### Add one item without touching the rest

```
const current = await content_get_navigation({ location: "header" });
const updated = {
  ...current,
  items: [...current.items, { label: "Customers", url: "/customers" }]
};
await content_update_navigation({ location: "header", items: updated.items });
```

#### Multi-column footer

```
content_update_navigation({
  location: "footer",
  items: [
    {
      label: "Product",
      url:   null,           // group header — no link
      children: [
        { label: "Features", url: "/features" },
        { label: "Pricing",  url: "/pricing" },
        { label: "Changelog", url: "/changelog" }
      ]
    },
    {
      label: "Company",
      url:   null,
      children: [
        { label: "About",     url: "/about" },
        { label: "Careers",   url: "/careers" },
        { label: "Contact",   url: "/contact" }
      ]
    },
    {
      label: "Resources",
      url:   null,
      children: [
        { label: "Blog",   url: "/blog" },
        { label: "Docs",   url: "/docs" },
        { label: "GitHub", url: "https://github.com/<org>", target: "_blank" }
      ]
    }
  ]
})
```

Most footer themes render top-level items as column headers, children as the column links. The `url: null` on the group header tells the renderer to not link the header itself.

#### External link

```
{ label: "GitHub", url: "https://github.com/SpiderIQ/SpiderIQ", target: "_blank" }
```

`target: "_blank"` opens in a new tab. Most themes add `rel="noopener"` automatically.

### Docs sidebar — auto vs hand-curated

By default the `docs_sidebar` is auto-generated from `content_docs_tree()` — the theme's `sections/docs-sidebar.liquid` iterates the tree. If you `content_update_navigation({location: "docs_sidebar", items: [...]})`, the theme can switch to rendering the hand-curated menu instead (depends on the template).

Default theme: uses hand-curated `docs_sidebar` IF it's non-empty; falls back to the tree if empty. Set `items: []` to revert to auto.

### Verify

The new nav is live the moment `content_update_navigation` returns 200 — no deploy. Verify in a browser, or:

```
content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
```

Check `body_text_preview` for the new item labels. Or open the URL and click each new link to confirm they don't 404.

### Anti-patterns

1. **Passing PATCH-style partial updates.** PUT semantics — you replace the full `items[]`. To add one item: read the current, append, send the full list back.
2. **Pointing to a page that doesn't exist.** The nav renders the link; clicking 404s. Check `content_list_pages({status: "published"})` before adding `/foo` to the nav.
3. **Using `location: "<anything>"` other than the three allowed.** 422. The three: `header`, `footer`, `docs_sidebar`. Custom locations need theme template changes — out of scope for this tool.
4. **Forgetting `target: "_blank"` on external links.** Visitors stay on the external site; bad UX. Always pair external URLs with `target: "_blank"`.
5. **Deeply-nested children (3+ levels).** Most themes only render 2 levels (top + children). Three-level nests render as flat children unless your theme has explicit deep-tree support.

### See also

- [`landing-page.md`](content.md#landing-page) — author the pages your nav points at
- [`blog-post.md`](content.md#blog-post) — same for blog posts
- [`docs-page.md`](content.md#docs-page) — note on docs_sidebar auto-tree vs hand-curated
- [`section-override.md`](content.md#section-override) — customize the header / footer Liquid templates
- [`../reference/tool-surface.md`](tool-surface.md) — full `content_*` tool list
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Custom Domain

Connect a custom domain (e.g. `acme.com`, `blog.acme.com`) to a SpiderPublish tenant. Two onboarding paths — CF-for-SaaS vs in-account-zone — picked by who owns the Cloudflare zone for the domain.

### When to use

- A tenant wants `acme.com` (instead of `acme.sites.spideriq.ai`) to serve their SpiderPublish site.
- You're moving an existing site from a different host to SpiderPublish and need to swap DNS without downtime.
- You're adding a second domain (e.g. `acme.com` + `www.acme.com` + `acme.co.uk`) to one tenant.

This is a **two-step** workflow: (1) register the domain with SpiderPublish, (2) verify DNS. Until verification succeeds, the domain doesn't route traffic.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You can change DNS for the domain.** If the tenant owns the registrar / DNS provider, they need to add a CNAME or move the zone. If they can't, this recipe stops at step 1.
3. **Decide the path: in-account vs CF-for-SaaS.** See "The two paths" below.

### The two paths

The choice depends on **who owns the Cloudflare zone for the domain**.

| Path | When | DNS step |
|---|---|---|
| **A — In-account zone** | SpiderIQ owns the Cloudflare zone (rare — only for sub-domains of `spideriq.ai`-adjacent zones we manage) OR you've moved the customer's zone into the SpiderIQ Cloudflare account | A Worker Route is auto-bound on the zone. No DNS change needed beyond pointing the domain at our nameservers. |
| **B — CF-for-SaaS** | The customer owns their Cloudflare zone (most common path for client domains) | Customer adds a CNAME (`acme.com → <something>.spideriq.ai`). SpiderPublish registers the hostname with CF-for-SaaS, which negotiates the TLS cert + edge routing. |

**Don't register both for the same hostname.** It silently produces CF 522s (the edge can't decide which Worker to dispatch to). If you don't know which path applies, ask the SpiderIQ team — they own the call.

Full breakdown: catalog/CLAUDE.md → "Two domain onboarding paths".

### The 4-call path

```
1. content_list_domains             — see what's already registered
2. content_add_domain               — register the new hostname
3. (DNS step OUTSIDE SpiderPublish)  — customer adds the CNAME / moves the zone
4. content_verify_domain            — server checks DNS; on success, the domain serves traffic
```

Optionally: `content_set_primary_domain` after verify, to make this domain the canonical one (the one `form_preview_url` and other URL-builders use as the host).

#### 1. List existing domains

```
content_list_domains()
// → [
//   { id, host: "<tenant>.sites.spideriq.ai", is_primary: true, verified_at: "...", verification_method: "auto" },
//   { id, host: "demo.acme.com", is_primary: false, verified_at: null, verification_method: "cname" }
// ]
```

Every tenant starts with `<tenant>.sites.spideriq.ai` (auto-verified). You're adding new entries.

#### 2. Register the new domain

```
content_add_domain({ domain: "acme.com" })
// → {
//     id, host: "acme.com",
//     verified_at: null,
//     verification_method: "cname",                 // OR "in_account" depending on path
//     verification_token: "spideriq-verify-...",     // sometimes needed for TXT-record path
//     cname_target: "tenant-cli_xxx.sites.spideriq.ai"   // the CNAME target the customer must add
//   }
```

The response tells you what DNS record the customer needs to add. For Path B (CF-for-SaaS), you'll typically get a `cname_target` to point `acme.com` at. For Path A (in-account zone), there's no DNS change beyond pointing the zone at our nameservers.

**`content_add_domain` is NOT gated.** It mutates immediately. (You can't "add" a domain wrong — it's just a row in `content_domains`; verification is what gates routing.)

#### 3. DNS step (customer-side, outside SpiderPublish)

Hand the `cname_target` (or `verification_token` if TXT-based) to the customer:

> "Please go to your DNS provider and add a CNAME record:
> - Name: `acme.com` (or `@` for the apex)
> - Type: `CNAME`
> - Value: `tenant-cli_xxx.sites.spideriq.ai`
> - TTL: 300 (5 min)"

Apex domain caveat: many DNS providers don't allow CNAME on the apex (`acme.com`). Workarounds:
- Cloudflare DNS: CNAME flattening — supported automatically.
- Other providers: use ALIAS or ANAME if available, or a redirect from apex to `www.`.
- If neither works, add `www.acme.com` as the primary and set up an apex-to-www redirect.

DNS propagation: typically <5 min globally; can take up to 48 hours on stale resolvers.

#### 4. Verify

```
content_verify_domain({ domain: "acme.com" })
// → { success: true, host: "acme.com", verified_at: "2026-05-24T...", cname_observed: "tenant-cli_xxx.sites.spideriq.ai" }
```

If `success: false`, the response carries why:

| Reason | What to fix |
|---|---|
| `cname_mismatch` | DNS still points at the old host. Wait for propagation (re-check in 5-10 min). |
| `txt_missing` | TXT-based verification — customer hasn't added the `spideriq-verify-...` TXT record yet. |
| `cf_saas_pending` | CF is still negotiating the TLS cert (15-60s typical). Re-check in 30s. |
| `no_authority` | The PAT scope doesn't own this domain. Check tenant binding. |

Verification is idempotent — call it as often as needed until it succeeds.

#### 5. (Optional) Set primary

```
content_set_primary_domain({ domain: "acme.com" })
// → { primary: "acme.com", was_primary: "<tenant>.sites.spideriq.ai" }
```

The primary domain is what `form_preview_url` and other URL-builders use as the host. It's also what `content_settings.canonical_url` defaults to for SEO `<link rel="canonical">` tags. Set it once you've verified — otherwise visitors hit the new domain but `<canonical>` still points at the old one.

### Verify (the live test)

After verify + set-primary, in a separate shell:

```bash
curl -sI https://acme.com/
# Should return HTTP/2 200, server: cloudflare, cf-ray: <ray>
```

If you get a 522 or 525, double-check you haven't registered the hostname on both paths (in-account zone AND CF-for-SaaS). One-only.

Visual check on the homepage:

```
content_visual_check({ page_url: "https://acme.com/", viewport: "desktop" })
```

### Remove a domain

```
content_delete_domain({ domain: "old.acme.com" })
// → { success: true, message: "Domain 'old.acme.com' removed" }
```

This unbinds the Worker Route + removes the row. Traffic to the hostname will start hitting the customer's DNS fallback (usually a 404 from their previous host, or NXDOMAIN if the CNAME is also removed).

**Opt-in dry_run** is not currently exposed on delete-domain — the operation is reversible (re-add + re-verify) so the safe-default isn't there. Be careful with primary domains; deleting the primary fails the request (re-assign primary first).

### Apex + www together (the canonical pattern)

For most customers, register BOTH the apex (`acme.com`) and the `www` subdomain (`www.acme.com`). Set the apex as primary. The Liquid renderer's request handler redirects `www.acme.com/<path>` → `acme.com/<path>` (301) when primary is set.

```
content_add_domain({ domain: "acme.com" })
content_add_domain({ domain: "www.acme.com" })
# customer adds CNAMEs for both
content_verify_domain({ domain: "acme.com" })
content_verify_domain({ domain: "www.acme.com" })
content_set_primary_domain({ domain: "acme.com" })
```

### Anti-patterns

1. **Registering the same hostname on both in-account + CF-for-SaaS.** Silent CF 522. Pick ONE path; if you don't know which, ask SpiderIQ ops.
2. **Skipping verification.** A domain row that's `verified_at: null` doesn't route traffic. Customers occasionally add a CNAME and assume it's done — always run `content_verify_domain` and check `success: true`.
3. **Setting primary before verify.** `content_set_primary_domain` requires the domain to be verified. Returns 422 otherwise.
4. **Trying to delete the primary domain.** Re-assign primary to another verified domain first, then delete.
5. **Adding CNAME records when the customer's DNS provider doesn't support CNAME-on-apex.** Use CNAME flattening (Cloudflare DNS), ALIAS / ANAME (other providers), or apex-to-www redirect as fallback.
6. **Assuming "domain verified" means the SITE is live there.** It means CF will route traffic to your tenant — but the tenant's site needs `content_deploy_site_production` to have actual content. Deploy after first domain setup. See [`../reference/deploy-protocol.md`](deploy-protocol.md).

### See also

- [`apply-theme.md`](templates-deploy.md#apply-theme) — apply a theme before pointing real traffic
- [`landing-page.md`](content.md#landing-page) — make sure the tenant has a published home page before customers land
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the deploy that pushes content to the verified domain
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth
- catalog/CLAUDE.md → "Two domain onboarding paths" — canonical internal guide
- catalog/DEPLOYMENT.md — which CF Worker / Dispatcher route serves which hostname (Rule 68: DEPLOYMENT.md wins for routing questions)


---

## Update Site Settings

Change site-wide settings — site name, SEO defaults, analytics, primary color, favicon, custom head/body scripts. The `extra='forbid'` surface — unknown keys 422 loudly.

### When to use

- A tenant just got provisioned and needs `site_name`, `favicon_url`, `logo_url`, `tagline` set.
- You're updating SEO defaults (`default_meta_title`, `default_meta_description`) site-wide.
- You're rolling out analytics (`analytics_id` for GA, or `custom_head_scripts` for Plausible/Posthog).
- You're updating the brand palette (`primary_color`, secondary, etc.).
- You need to set `extensions.feeds` (RSS/Atom/JSON Feed config) — see Wave 6.1.

For per-page SEO overrides (different `<title>` per page) → set `seo_title` / `seo_description` on `content_create_page` / `content_update_page`. For the visual theme as a whole → [`apply-theme.md`](templates-deploy.md#apply-theme). For navigation menus → [`navigation.md`](content.md#navigation).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You know the canonical field names.** Settings is `extra='forbid'` post-Antigravity hardening — unknown keys 422. Use the documented field list below.

### The 2-call path

```
1. content_get_settings              — see current state
2. content_update_settings           — Phase 11+12 dry_run + confirm
```

No deploy step needed for settings-only changes EXCEPT when you change `custom_head_scripts` / `custom_body_scripts` (those need a deploy to push the new HTML to CF edge).

#### 1. Get current settings

```
content_get_settings()
// → {
//   site_name:                  "Acme Inc",
//   tagline:                    "We build things",
//   default_meta_title:         "Acme Inc — engineering blog",
//   default_meta_description:   "Notes from the Acme engineering team",
//   primary_color:              "#1f6feb",
//   favicon_url:                "https://media.spideriq.ai/acme/favicon.ico",
//   logo_url:                   "https://media.spideriq.ai/acme/logo.svg",
//   analytics_id:               "G-XXXXXXXXXX",
//   custom_head_scripts:        "<script>...</script>",
//   custom_body_scripts:        "",
//   social_twitter:             "@acme",
//   social_github:              "https://github.com/acme",
//   extensions:                 { feeds: { rss_enabled: true, atom_enabled: false, ... } },
//   ...
// }
```

Read the existing values before mutating. Settings are merged (PATCH semantics on the `settings` dict) — you only pass keys you want to change, but you need to know what's there to avoid clobbering accidentally.

#### 2. Update (REQUIRED `settings:` wrapper)

```
content_update_settings({
  settings: {                          # REQUIRED top-level wrapper — NOT `changes`, NOT flat
    site_name:                "Acme — engineering",
    default_meta_title:       "Acme engineering blog — scaling systems at 50M users",
    default_meta_description: "Notes on Postgres, Kafka, and how we ship.",
    primary_color:            "#0f172a",
    custom_head_scripts:      "<script defer data-domain=\"acme.com\" src=\"https://plausible.io/js/script.js\"></script>"
  }
})
# → defaults to dry_run=true (settings is a destructive op)
# → { dry_run: true, preview, confirm_token: "cft_..." }

content_update_settings({
  settings: { ...same... },
  confirm_token: "cft_..."
})
# → { applied: true, updated_keys: ["site_name", "default_meta_title", ...] }
```

**Critical:** the `settings:` wrapper is REQUIRED. Calls without it return 422 "Field required".

| ✅ Right | ❌ Wrong (422) |
|---|---|
| `{ settings: { site_name: "X" } }` | `{ site_name: "X" }` (flat — missing wrapper) |
| `{ settings: { site_name: "X" } }` | `{ changes: { site_name: "X" } }` (wrong key — `form_update` uses `changes:`, this uses `settings:`) |

This is THE most common error for agents coming from `form_update`. Save yourself a 422.

#### Phase 11+12 — safe-default dry_run

`content_update_settings` defaults to **`dry_run=true`** (destructive — settings affect every page render). The first call returns a preview + `confirm_token`; second call with the token applies.

Read the preview's `before` and `after` blocks carefully. Settings can affect every page on the site — a typo in `primary_color` propagates everywhere. The preview is your safety net.

### The canonical field list (post-Antigravity `extra='forbid'`)

Settings is `extra='forbid'`. Unknown keys 422. The documented fields:

#### Identity

| Field | Type | Notes |
|---|---|---|
| `site_name` | string | Site's display name. Renders in `<title>` (when per-page seo_title is absent), nav logo alt, OG tags. |
| `tagline` | string | One-line subtitle. Some themes render under `site_name`. |
| `logo_url` | string (must end `_url`) | Site logo. Renders in header nav typically. |
| `favicon_url` | string (must end `_url`) | Favicon (ICO/PNG). |

#### SEO defaults (migration 244)

| Field | Type | Notes |
|---|---|---|
| `default_meta_title` | string, max 255 | Site-wide default `<title>` when a page doesn't set its own `seo_title`. |
| `default_meta_description` | string, max 500 | Site-wide default `<meta name="description">`. |
| `default_og_image_url` | string | Default OG image when a page doesn't set its own. |
| `canonical_url` | string | Canonical site URL (e.g. `https://acme.com`). Used in `<link rel="canonical">` builds. |

#### Colors + theme tokens

| Field | Type | Notes |
|---|---|---|
| `primary_color` | hex string | Brand primary. Themes use it for buttons, links, focus rings. |
| `secondary_color` | hex string | Brand secondary. Some themes use it for accents. |
| `body_text_color` | hex string | Body copy color. |

#### Analytics + scripts

| Field | Type | Notes |
|---|---|---|
| `analytics_id` | string | GA4 / Plausible / etc. ID. Renderer injects standard snippets when set. |
| `custom_head_scripts` | string (HTML) | Free-form HTML inserted in `<head>`. Use for Plausible script, Posthog, custom OG tags. **Requires deploy.** |
| `custom_body_scripts` | string (HTML) | Free-form HTML inserted right before `</body>`. Use for chat widgets, GTM. **Requires deploy.** |

#### Social

| Field | Type | Notes |
|---|---|---|
| `social_twitter` | string | Twitter handle (e.g. `@acme`). |
| `social_github` | string | GitHub org URL. |
| `social_linkedin` | string | LinkedIn URL. |
| `social_facebook` | string | Facebook page URL. |

#### Extensions

| Field | Type | Notes |
|---|---|---|
| `extensions.feeds.rss_enabled` | bool | Enable `/feed.xml`. Wave 6.1. |
| `extensions.feeds.atom_enabled` | bool | Enable `/atom.xml`. |
| `extensions.feeds.json_feed_enabled` | bool | Enable `/feed.json` (JSON Feed 1.1). |
| `extensions.sitemap.exclude_paths` | string[] | Paths to exclude from `/sitemap.xml`. |
| `extensions.robots.allow_paths` | string[] | Whitelist for `/robots.txt`. |

#### Map provider keys (W3.3 / W5.2)

| Field | Notes |
|---|---|
| `map_providers.mapbox.browser_key_encrypted` | Fernet-encrypted Mapbox browser key. Use the dashboard's encrypted-key UI to set; never paste plaintext via MCP (it'd persist plaintext). |
| `map_providers.google.browser_key_encrypted` | Same for Google Maps. |

#### Agent-shift digest (W6 — agent-native)

| Field | Notes |
|---|---|
| `agent_shift_digest_cadence` | `"daily" | "weekly" | "off"`. Frequency for the agent-shift digest emails (the "what did my agents change this week" summary). |
| `geo_toggle_enabled` | bool. Whether the `sys-geo-*` primitives auto-inject. |

**This list is non-exhaustive but covers the common surface.** Run `content_get_settings()` to see your tenant's complete current shape. If you try to set a field NOT in this list, you get a 422 — Antigravity 2026-05-22 hardening closed the silent-collusion trap where unknown keys persisted but didn't do anything.

### Common patterns

#### Set up analytics on a new tenant

```
content_update_settings({
  settings: {
    analytics_id: "G-XXXXXXXXXX"
  }
})
# Renderer auto-injects standard GA4 snippet — no custom_head_scripts needed
```

For Plausible / Posthog / non-GA analytics:

```
content_update_settings({
  settings: {
    custom_head_scripts: "<script defer data-domain=\"acme.com\" src=\"https://plausible.io/js/script.js\"></script>"
  }
})
# Requires deploy to push the new <head> HTML to CF edge.
```

#### Rebrand — change site name + logo + colors

```
content_update_settings({
  settings: {
    site_name:        "Acme — Reimagined",
    tagline:          "AI-native, customer-first",
    primary_color:    "#ec4899",
    secondary_color:  "#a855f7",
    logo_url:         "https://media.spideriq.ai/acme/logo-v2.svg",
    favicon_url:      "https://media.spideriq.ai/acme/favicon-v2.ico"
  }
})
```

Visual changes propagate to every page on next deploy (or next render if rendering live from API).

#### Enable RSS feed

```
content_update_settings({
  settings: {
    extensions: {
      feeds: {
        rss_enabled: true,
        atom_enabled: true,
        json_feed_enabled: false
      }
    }
  }
})
# After confirm, /feed.xml + /atom.xml are live for the tenant.
```

### Deploy after settings change?

- **No deploy needed** for: `site_name`, `tagline`, `logo_url`, `favicon_url`, `analytics_id`, `default_meta_*`, `primary_color`, `social_*`, `extensions.*`. The renderer reads settings live from the API per request.
- **Deploy required** for: `custom_head_scripts`, `custom_body_scripts`. These bake into the rendered HTML at deploy time; live changes don't propagate until next deploy.

For mixed changes (some live, some bake-time), do one `content_update_settings` covering all of them, then `content_deploy_site_production` to push the head/body script changes. The live-read fields update immediately; the baked-in ones update on deploy.

### Verify

```
# Read back
content_get_settings()
# Confirm the new values landed.

# Visual check
content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
# For visual changes (primary_color, logo): check screenshot.
# For SEO defaults: view-source on the page, check <title> + <meta>.
# For analytics: check the page source for the script injection.
```

### Anti-patterns

1. **Missing the `settings:` wrapper.** `{ site_name: "X" }` → 422 "Field required". Use `{ settings: { site_name: "X" } }`. The most-common agent error coming from `form_update` (which uses `changes:`).
2. **Setting unknown keys (`extra='forbid'`).** Unknown keys 422. Old behaviour silently persisted them with no effect — Antigravity 2026-05-22 fix closed this. Stick to the documented field list.
3. **Pasting plaintext map provider keys.** Use the dashboard's encrypted-key UI — MCP doesn't have a "set encrypted" tool today. Plaintext via MCP would persist plaintext.
4. **Setting `custom_head_scripts` to a multi-line `<script>` with embedded `</script>` tags inside literals.** Browser parses early. Escape: `<\/script>`.
5. **Forgetting to deploy after changing `custom_head_scripts` / `custom_body_scripts`.** Those bake at deploy time. Other settings update live.
6. **Confusing `default_meta_title` (site-wide default) with `seo_title` (per-page).** Set `default_meta_title` in settings; set `seo_title` on `content_create_page` / `content_update_page`.

### See also

- [`apply-theme.md`](templates-deploy.md#apply-theme) — swap the whole theme (different from settings — templates, not data)
- [`navigation.md`](content.md#navigation) — menu config (separate from settings)
- [`custom-domain.md`](integrations.md#custom-domain) — domain config (separate again)
- [`landing-page.md`](content.md#landing-page) — per-page SEO overrides
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — gate flavour (safe-default dry_run=true)
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*_settings` tool catalog
- catalog/CLAUDE.md → "Public API Endpoints" → `/content/settings` route


---

## Duplicate Page

Make a new page by copying an existing one — **one call, not gated**, fresh draft, fresh UUIDs on every block.

### When to use

- The client wants a new page that's similar to an existing one — duplicating saves 80% of the build (faster than rebuilding from blocks, lower variance than a template apply).
- You're applying a template by cloning master pages into the tenant (template-gallery pattern).
- Internal A/B testing — fork a published page, edit copy, publish under a new slug, route a slice of traffic with the redirect block.
- Spinning up a per-event landing page that reuses the main marketing page's structure with one section swapped.

### Prerequisites

- A PAT scoped to the tenant that owns the source page.
- The source page's `page_id` (UUID).

### The one call

```
content_duplicate_page({
  page_id: "<source-uuid>"
})
# → {
#     id: "<new-uuid>",
#     slug: "<original-slug>-copy",      # or -copy-2, -copy-3, ... lowest unused
#     title: "<original-title> (Copy)",
#     status: "draft",                    # always
#     blocks: [...with fresh UUIDs...],
#     ...
#   }
```

That's it. Not Phase 11+12 gated — duplicates create **new rows** rather than overwriting state, so no confirm_token is needed. Just call once and you get the new page.

#### With a chosen slug

```
content_duplicate_page({
  page_id: "<source-uuid>",
  new_slug: "black-friday-2026"
})
# → { id: "<new-uuid>", slug: "black-friday-2026", ... }
```

`new_slug` must match `^[a-z0-9][a-z0-9-]*$` — no `/`, no leading dash, no uppercase. The MCP tool enforces the pattern; a bad slug returns a 422 with the regex.

### What gets cloned vs regenerated

| Field | Behavior |
|---|---|
| `id` | **Regenerated** — new page UUID |
| `slug` | Auto: `{original}-copy[-N]`. Explicit: `new_slug`. |
| `title` | `<original> (Copy)` so the dashboard list shows it distinctly |
| `status` | Forced to `draft` regardless of the source's state |
| `blocks[].id` | **Regenerated** for every block (fresh UUIDs) so the new page is independent of the source |
| `blocks[].component_slug`, `props`, `data` | Identical to source |
| `blocks[].anchor_block_id` | Rewritten to point at the new block UUIDs (preserves intra-page anchor links) |
| `seo_title`, `seo_description` | Copied verbatim — **edit these before publishing** to avoid duplicate-content SEO hits |
| `template` | Copied |
| `version_number` | Resets to `1` on the new page (the duplicate is a fresh history) |

### Steps

```
1. content_get_page({ page_id: "<source-uuid>" })   — confirm the source is what you think
2. content_duplicate_page({ page_id, new_slug? })    — get the new draft
3. content_update_page({ page_id: "<new-uuid>", seo_title, seo_description })
                                                      — fix SEO so the duplicate doesn't compete with the source
4. content_publish_page({ page_id: "<new-uuid>" })   — safe-default dry_run; review + confirm
5. content_deploy_site_preview() → content_deploy_site_production(confirm_token)
                                                      — push live
```

### Gotchas

- **SEO will collide if you publish the duplicate as-is.** `seo_title` + `seo_description` copy verbatim. If both pages are indexed, Google penalises duplicate content. Always edit SEO on the new page before publishing — Step 3 is non-optional for production.
- **Slug auto-generation is lowest-N.** First duplicate of `pricing` → `pricing-copy`. Second → `pricing-copy-2`. Tenth → `pricing-copy-10`. If `pricing-copy-3` was deleted, the next call still picks `pricing-copy-3` (lowest unused). Predictable but easy to confuse with stale lists.
- **Cross-tenant duplication is refused 404.** A PAT scoped to `cli_A` cannot duplicate a page from `cli_B` — Lock 5 (the WHERE clause) rejects the read, so the duplicate never reaches the INSERT. Use the marketplace `content_apply_site_template` flow for cross-tenant copies of curated content.
- **Block-internal references survive but external page refs don't.** `anchor_block_id` (intra-page) is rewritten to the new UUIDs. But if a block has a `data.next_page_id` pointing at another page on the source, the duplicate still points at THAT page (not a duplicate of it). Audit `data.*_page_id` fields after duplication.
- **Duplicating a page with a `kind='form'` flow block** copies the block (with its `component_slug: "form"` and `data.flow_id`) — but you now have **two pages embedding the same flow**. Submissions from both pages land in the same flow. If you want them isolated, duplicate the flow too with `form_duplicate({ flow_id })` and rewire the new page's block.

### Verify

```
content_get_page({ page_id: "<new-uuid>" })
# → confirm status=draft, fresh block UUIDs, slug matches what you asked for

# Diff against the source to confirm only id/slug/title changed:
diff <(content_get_page({page_id: "<source-uuid>"}) | jq .blocks) \
     <(content_get_page({page_id: "<new-uuid>"})    | jq '.blocks | map(.id = "REDACTED")')
# Should be empty (modulo the .id redaction).
```

After publish + deploy, eyeball the new URL:

```
content_visual_check({
  page_url: "https://<tenant-domain>/<new-slug>",
  viewport: "desktop"
})
```

### Anti-patterns

- **Publishing the duplicate without editing SEO.** Duplicate-content penalty. Always edit `seo_title` + `seo_description` first.
- **Treating `content_duplicate_page` as "copy and edit in place."** It's "copy to a new row." If you wanted to edit the source, just call `content_update_page` on the source.
- **Duplicating to "back up" a page before edits.** Use [`export-page-roundtrip.md`](content.md#export-page-roundtrip) for a true snapshot, or [`restore-page-version.md`](content.md#restore-page-version) to roll back if needed. The version history is already there — don't pollute the page list.
- **Looping `content_duplicate_page` 50× to seed a directory.** Use [`../directory/import-listings.md`](integrations.md#import-listings) for bulk SEO pages — that hits a single bulk endpoint instead of 50 round-trips.
- **Forgetting that `content_publish_page` is safe-default-gated.** Even though duplicate isn't gated, publishing the new page is. Review the preview, then confirm with the token.

### See also

- [`duplicate-block.md`](content.md#duplicate-block) — same primitive at block granularity (deep-copy one section inside the same page)
- [`apply-site-template.md`](templates-deploy.md#apply-site-template) — duplicate a CURATED set of pages from the marketplace in one call
- [`export-page-roundtrip.md`](content.md#export-page-roundtrip) — when you need an offline copy rather than a STORE duplicate
- [`landing-page.md`](content.md#landing-page) — building a new page from scratch (alternative path)
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — publish + deploy gate flavours


---

## Duplicate Block

Insert a **deep copy of one block** into the same page — at any position. One call, not gated, fresh block UUID.

### When to use

- Duplicating a CTA section to use in a different position on the same page (top hero + mid-scroll + footer).
- Cloning a tier-priced "feature card" inside a `pricing-grid` block when the props were tuned just right.
- Building variations of the same section without rebuilding from scratch.
- Pattern: "do that thing again, just below the original."

### Prerequisites

- A PAT scoped to the tenant.
- The page's `page_id` (UUID).
- The source `block_id` to duplicate. Read it from `content_get_page` → `blocks[]`.

### The one call

```
content_duplicate_block({
  page_id:  "<page-uuid>",
  block_id: "<source-block-id>",
  position: "after"      # default; see below
})
# → { page: {...updated with new block inserted...}, new_block_id: "<fresh-uuid>" }
```

That's it. Not Phase 11+12 gated. Page status is unchanged — this won't unpublish a published page.

### `position` semantics

| Value | Behavior |
|---|---|
| `"after"` (default) | Insert immediately after the source block |
| `"before"` | Insert immediately before the source block |
| Integer (e.g. `0`, `3`, `99`) | Insert at the explicit 0-based index. Clamped to `[0, len(blocks)]` |

```
# Place the copy at the very top:
content_duplicate_block({ page_id, block_id: "blk_hero", position: 0 })

# Place the copy at the very end:
content_duplicate_block({ page_id, block_id: "blk_features", position: 999 })   # clamps to len
```

### What gets cloned

- The entire block JSON — `type`, `component_slug`, `component_version`, `props`, `data`, layout settings.
- The `block.id` is **regenerated** (fresh UUID); everything else is byte-identical.
- Intra-page `anchor_block_id` references INSIDE the duplicated block are NOT rewritten — if you duplicate a tabbed block whose internal panels reference each other by id, the copy's panels still reference the ORIGINAL panels. Audit after for tabbed/accordion/anchor patterns.

### Steps

```
1. content_get_page({ page_id })                   — find the block you want to duplicate
2. content_duplicate_block({ page_id, block_id })  — get the new block id
3. content_update_page({ page_id, blocks: [...] }) — (optional) edit the new block's copy/props
4. content_publish_page({ page_id })               — safe-default dry_run; review + confirm
5. content_deploy_site_preview() → content_deploy_site_production(confirm_token)
```

### Gotchas

- **The two copies share the same `component_slug` AND `component_version`.** If the underlying component gets a v4 published, both copies will pick it up on next deploy (the page references the slug, not a pinned version, unless you set `component_version` explicitly).
- **Forms inside duplicated blocks are NOT cloned.** If you duplicate a block whose `component_slug == "form"` and `data.flow_id` points at a flow, the copy points at the SAME flow. Submissions from both blocks land together. To isolate, duplicate the flow (`form_duplicate({ flow_id })`) and edit the copy's `data.flow_id`.
- **Tier 3 components (GSAP / scroll-sequence) cost CPU per instance.** Duplicating a `sys-scroll-sequence` block puts two GSAP timelines on the page; mobile users feel it. Audit performance after duplicating animation-heavy blocks.
- **Intra-block anchor refs don't rewrite.** Tab/accordion blocks with internal panel ids referencing each other will silently misbehave if the panels appear twice. Fix manually: edit the copy's internal ids in a follow-up `content_update_page`.
- **`position` greater than `len(blocks)` clamps to the end** — it doesn't error. Useful for "always append," but easy to confuse with off-by-one bugs.

### Verify

```
content_get_page({ page_id })
# → confirm blocks[] has the new block at the expected index
#   confirm new_block_id is in blocks[].id
#   confirm props match the source byte-identical (except .id)
```

For visual confirmation after deploy:

```
content_visual_check({
  page_url: "https://<tenant-domain>/<page-slug>",
  viewport: "desktop"
})
```

For form-containing duplicates, assert on `dom.shadow_hosts.includes("spideriq-form")` — see [`../reference/booking-model.md`](booking-model.md) and Rule 62.

### Anti-patterns

- **Calling `content_duplicate_block` 12× in a loop** to build a list. Use `content_update_page` with a constructed `blocks[]` instead — one round-trip vs 12.
- **Duplicating a block to "back it up" before editing.** Just edit; the version history (per-page) carries the snapshot already. Restore via [`restore-page-version.md`](content.md#restore-page-version) if needed.
- **Duplicating a form block expecting submission isolation.** The copy points at the same `flow_id` — submissions converge. Duplicate the flow if isolation matters.
- **Forgetting to edit the duplicate's copy/CTA text.** Two identical CTAs on the same page rarely lift conversion; you wanted "same component, different message."
- **Duplicating Tier 3 animation blocks without performance-budgeting.** Two scroll-sequences on mobile = jank. Use [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) post-deploy with `viewport: "mobile"` to catch this.

### See also

- [`duplicate-page.md`](content.md#duplicate-page) — same primitive at page granularity (full-page deep copy with fresh UUIDs everywhere)
- [`../components/find-component.md`](components.md#find-component) — for inspecting what the duplicated component does
- [`section-override.md`](content.md#section-override) — when you want a "duplicate but with my version of one section" pattern
- [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) — verify the duplicate renders correctly
- [`../reference/block-types.md`](block-types.md) — the block schema being deep-copied


---

## Dynamic List Page

Create a dynamic LIST page — iterates a collection (posts, docs, or directory_listings) and renders one card per item. The "/blog" / "/docs" / "/directory" index pattern.

### When to use

- You want a `/blog` index that auto-lists all published blog posts (so adding a post doesn't require editing the index).
- You want a `/docs` landing page that shows the docs tree.
- You want a `/listings` or `/places` page for a directory of `content_directory_listings`.
- More broadly: any page that should display a list of dynamically-changing items without manually editing the page.

For a single dynamic page (e.g. `/blog/<slug>` or `/listings/<city>`) → [`dynamic-item-page.md`](content.md#dynamic-item-page). For a static page → [`landing-page.md`](content.md#landing-page).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **The collection has ≥1 published item** (otherwise the page renders an empty list). Check:
   - For `posts`: `content_list_posts({ status: "published" })` returns ≥1.
   - For `docs`: `content_docs_tree()` returns ≥1.
   - For `directory_listings`: `directory_list_listings({ status: "published" })` returns ≥1.
3. **Theme has `templates/dynamic-list.liquid`.** Default theme ships it; check `template_list()` if customized.

### The 1-call path

```
content_create_page({
  title:    "Blog",
  slug:     "blog",
  template: "dynamic_list",
  collection_type: "posts"          # REQUIRED for dynamic_list
})
```

That's the whole page. The renderer iterates published `content_posts` and emits one card per item, using `templates/dynamic-list.liquid` for the layout.

### The three collection types

| `collection_type` | Iterates | URL convention |
|---|---|---|
| `posts` | Published `content_posts` (blog posts) | List at `/<slug>`; items at `/<slug>/<post_slug>` (typically `/blog/<post_slug>`) |
| `docs` | `content_docs` tree (only published nodes) | List at `/<slug>`; items at `/<slug>/<doc_full_path>` (typically `/docs/<full_path>`) |
| `directory_listings` | Published `content_directory_listings` | List at `/<slug>`; items at `/<slug>/<listing_slug>` (typically `/listings/<slug>`) |

The page slug is independent of the URL convention — you can have `template: dynamic_list, collection_type: posts, slug: "articles"` and the list lives at `/articles`. The dynamic-item page (the per-item page) is a SEPARATE recipe; see [`dynamic-item-page.md`](content.md#dynamic-item-page).

### Step 1 — verify items exist

```
content_list_posts({ status: "published", limit: 50 })
// → [{ id, title, slug, ... }, ...]
```

If empty, the dynamic-list page renders but visitors see "No posts yet." Solve by:
- Publishing at least one post first ([`blog-post.md`](content.md#blog-post)).
- OR adding a fallback `blocks[]` to the page (rendered ONLY when the collection is empty).

### Step 2 — create the page

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

### Step 3 — publish + deploy

```
content_publish_page({ page_id })
content_publish_page({ page_id, confirm_token })

content_deploy_site_production({ confirm_token })   # ~2-5s live
```

After deploy, `https://<tenant>/blog` renders the iterated list.

### How the iteration works (renderer internals)

The dynamic-list template (`templates/dynamic-list.liquid`) is a Liquid file that:

1. Fetches the collection at request time via the content API:
   - `posts` → `GET /content/posts?status=published&page=1&page_size=20`
   - `docs` → `GET /content/docs/tree` (recursive)
   - `directory_listings` → `GET /content/directory/listings?status=published`
2. Iterates the array in Liquid: `{% for item in collection %}<a href="{{ item_url }}">...</a>{% endfor %}`
3. Default item card layout (themable per-tenant).
4. Pagination via `?page=N` (default 20 per page; configurable in the template).

If you want different per-item rendering, customize `templates/dynamic-list.liquid` via `template_upsert` ([`section-override.md`](content.md#section-override) covers the pattern).

### URL routing — the item URL pattern

The dynamic-list page lives at `/<page-slug>`. The per-item URL pattern depends on `collection_type`:

| collection_type | Item URL |
|---|---|
| `posts` | `/blog/<post_slug>` (default; matches the `templates/blog-post.liquid` route) |
| `docs` | `/docs/<full_path>` (where `full_path` is the parent-id chain) |
| `directory_listings` | `/<page-slug>/<listing_slug>` |

For `posts` and `docs`, the URLs are conventional (and the default theme's renderer hard-codes them). For `directory_listings`, you typically pair the list page with a `template: "dynamic_item"` page using the same `slug` prefix. See [`dynamic-item-page.md`](content.md#dynamic-item-page).

### Common patterns

#### Blog index with featured posts above the fold

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

#### Categorized directory list

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

#### Empty-state with a CTA

The dynamic-list template typically renders the list + an empty state when collection is empty. To customize the empty state, override `templates/dynamic-list.liquid` via `template_upsert`. Add an `{% if collection.size == 0 %}` block with a CTA.

### Verify

```
content_visual_check({ page_url: "https://<tenant>/blog", viewport: "desktop" })
# Check screenshot shows the iterated list.
# Check body_text_preview contains item titles (server-rendered HTML).
```

### Anti-patterns

1. **`template: "dynamic_list"` without `collection_type`.** 422 "collection_type required". Always pair.
2. **`collection_type: "posts"` with `template: "default"`.** 422 — `collection_type` only applies to `dynamic_list` / `dynamic_item`.
3. **Trying to filter the iterated collection via the page's `blocks[]`.** Filtering happens in the Liquid template — `template_upsert` to customize. Page blocks are static (per-page), not per-item.
4. **Creating the dynamic-list page BEFORE any items exist.** It works, but visitors see "No posts yet." Always publish at least one item first.
5. **Using `dynamic_list` for a SINGLE-item display.** That's `dynamic_item` ([`dynamic-item-page.md`](content.md#dynamic-item-page)) — `dynamic_list` is for the index, `dynamic_item` is for the detail.
6. **Pointing two dynamic-list pages at the same `collection_type`.** Both render the same list at different URLs — confusing for visitors + SEO duplicate-content risk. Pick one URL for each collection.

### See also

- [`dynamic-item-page.md`](content.md#dynamic-item-page) — per-item detail page (the "/blog/<slug>" pattern)
- [`landing-page.md`](content.md#landing-page) — static page (alternative when no collection iteration)
- [`blog-post.md`](content.md#blog-post) — author the posts the list iterates
- [`docs-page.md`](content.md#docs-page) — author the docs the list iterates
- [`section-override.md`](content.md#section-override) — customize `templates/dynamic-list.liquid`
- [`../reference/block-types.md`](block-types.md) — page `blocks[]` shape
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*` tool catalog


---

## Dynamic Item Page

Create a dynamic ITEM page — resolves a single item by URL slug at request time. The "/blog/<post_slug>" or "/listings/<listing_slug>" pattern. Sibling to [`dynamic-list-page.md`](content.md#dynamic-list-page).

### When to use

- You have a blog list at `/blog` and need `/blog/<post_slug>` to render each post.
- You have a directory list at `/listings` and need `/listings/<listing_slug>` to render each listing.
- You want a 2-segment URL pattern (`/<prefix>/<item-slug>`) that resolves dynamically.

For the LIST page → [`dynamic-list-page.md`](content.md#dynamic-list-page). For a static one-off page → [`landing-page.md`](content.md#landing-page).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **The matching dynamic-list page exists** (typically — same `collection_type`, related slug prefix). Without it the item URLs work but visitors have no index.
3. **The collection has ≥1 published item** (otherwise every item URL 404s).
4. **Theme has `templates/dynamic-item.liquid`** (or per-collection variants: `templates/blog-post.liquid`, `templates/doc.liquid`, etc.). Default theme ships them.

### The 1-call path

```
content_create_page({
  title:    "Blog post detail",
  slug:     "blog",                  # the URL PREFIX, not a per-post slug
  template: "dynamic_item",
  collection_type: "posts"           # REQUIRED for dynamic_item
})
```

This is a SINGLE page that handles ALL `/blog/<any_slug>` URLs by resolving `<any_slug>` against published posts.

### The three collection types (same as dynamic_list)

| `collection_type` | Resolves slug against | URL pattern |
|---|---|---|
| `posts` | `content_posts.slug` | `/blog/<post_slug>` |
| `docs` | `content_docs.full_path` (recursive parent_id chain) | `/docs/<full_path>` |
| `directory_listings` | `content_directory_listings.slug` | `/<page-slug>/<listing_slug>` |

For `posts` and `docs`, the URL prefix is conventional (`/blog`, `/docs` — built into the default theme's routing). For `directory_listings`, the prefix is whatever `slug` you set on the dynamic-item page.

### Step 1 — verify the list page exists (recommended pairing)

```
content_list_pages({ status: "published" })
# Look for: { slug: "blog", template: "dynamic_list", collection_type: "posts" }
```

The dynamic-item page works without a list page — visitors hitting `/blog/<post>` resolve fine. But without a list at `/blog`, visitors landing on `/blog` 404. Pair them.

### Step 2 — create the item page

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

### Step 3 — publish + deploy

```
content_publish_page({ page_id })
content_publish_page({ page_id, confirm_token })

content_deploy_site_production({ confirm_token })
```

After deploy, `https://<tenant>/blog/<any-slug>` resolves dynamically.

### How the resolution works (renderer internals)

For `/blog/foo-bar` on a `dynamic_item` page:

1. Renderer matches URL → dynamic-item page at slug `blog`.
2. Extracts second segment `foo-bar`.
3. Queries content API: `GET /content/posts/foo-bar` (or `/content/docs/<full_path>` for docs, `/content/directory/listings/<slug>` for directory).
4. If found → renders via `templates/blog-post.liquid` (default theme has per-collection templates; falls back to `templates/dynamic-item.liquid` generic).
5. If NOT found → renders the 404 template (or `templates/blog-post.liquid` with empty item — depends on theme).

For `docs`, the URL can be N segments deep (`/docs/foo/bar/baz`) — the renderer concatenates segments after `/docs/` and matches `full_path`.

### Per-collection template files

The default theme has specific templates that take precedence over the generic `dynamic-item.liquid`:

| Collection | Template file (priority order) |
|---|---|
| `posts` | `templates/blog-post.liquid` → `templates/dynamic-item.liquid` |
| `docs` | `templates/doc.liquid` → `templates/dynamic-item.liquid` |
| `directory_listings` | `templates/listing.liquid` → `templates/dynamic-item.liquid` |

To customize per-collection rendering, override the specific file via `template_upsert` (or `content_override_section({ section_slug: "blog-post", ... })` for the per-post template).

### The 2-page pattern (list + item — typical setup)

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

### Common gotchas

#### Why is `/blog/<post-slug>` returning 404?

- **The post isn't published.** Item pages only resolve published items.
- **The slug doesn't match.** Item slugs are flat (`^[a-z0-9][a-z0-9-]*$`). Check the post's actual slug via `content_get_post({ post_id })`.
- **No dynamic-item page exists.** You created the list but not the item page; visitors hit `/blog/<x>` → no match → 404.
- **Both list AND item page have `template: "dynamic_list"`.** The item page must be `template: "dynamic_item"`. Easy typo.

#### Can I have two dynamic-item pages on different URL prefixes?

Yes:

```
# /blog/<post> resolved against posts
content_create_page({ slug: "blog", template: "dynamic_item", collection_type: "posts" })

# /articles/<post> ALSO resolved against posts (different prefix, same collection)
content_create_page({ slug: "articles", template: "dynamic_item", collection_type: "posts" })
```

Both `/blog/foo` and `/articles/foo` would render the same post. SEO risk (duplicate content); usually you want ONE prefix per collection.

#### Can I mix in static content on a dynamic-item page?

The page's `blocks[]` render alongside the resolved item content. Useful for global elements (CTA at the bottom of every post, related-posts module). The per-item content comes from the matched row; `blocks[]` is static across all items.

### Verify

```
# Publish a test post first, then:
content_visual_check({ page_url: "https://<tenant>/blog/<test-post-slug>", viewport: "desktop" })
# body_text_preview should contain the post's title + body literals.
```

### Anti-patterns

1. **`template: "dynamic_item"` without `collection_type`.** 422 — `_validate_collection_pairing` rejects.
2. **Setting per-item content in the page's `blocks[]`.** Blocks are STATIC per dynamic-item page. Per-item content comes from the resolved row's content (post body, doc body, listing fields). To customize per-item rendering, override the template (`templates/blog-post.liquid` etc.).
3. **Creating a dynamic-item page WITHOUT a matching dynamic-list page.** The item page works, but visitors hitting the prefix URL (`/blog`) 404. Always create both for the common pattern.
4. **Using `dynamic_item` for a single-purpose page (e.g. one specific post displayed on its own page).** That's a static `template: "default"` page. Dynamic_item is for the GENERAL pattern of "URL segment → resolved item."
5. **Trying to nest dynamic items 3+ deep (`/blog/2026/05/post-slug`).** Not supported. Dynamic items match second-segment-onward in one chunk; docs match recursive `full_path`. For year/month dated URLs, you'd need a custom theme template or per-year list pages.
6. **Pointing `dynamic_item` at the same `collection_type` as another `dynamic_item` page on the same URL prefix.** Renderer matches one or the other — undefined behaviour. One dynamic-item per prefix per collection.

### See also

- [`dynamic-list-page.md`](content.md#dynamic-list-page) — the LIST sibling (typically created together)
- [`blog-post.md`](content.md#blog-post) — author the posts the item page renders
- [`docs-page.md`](content.md#docs-page) — author the docs the item page renders
- [`landing-page.md`](content.md#landing-page) — static one-off page (different surface)
- [`section-override.md`](content.md#section-override) — customize `templates/dynamic-item.liquid` or per-collection templates
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*` tool catalog


---

## Section Override

Replace a single section (header, footer, hero, blog listing) for this tenant only — without forking the entire theme. Plus the layout-preset shortcut for chrome-only changes.

### When to use

- A tenant wants a custom header (their logo, their nav style) but the rest of the theme is fine.
- You want to swap the footer's copyright + links without touching anything else.
- You're A/B-ing a new blog-listing layout without affecting individual blog posts.
- You want to switch the whole site to "no header, no footer" (a `blank` layout) for a campaign — without writing Liquid.

If you want to swap the ENTIRE theme → [`apply-theme.md`](templates-deploy.md#apply-theme). If you want a brand-new Liquid template at a new path → use `template_upsert` directly. This recipe is for the named-section shortcut.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You know the section slug.** Common: `header`, `footer`, `hero`. Special: `blog-listing`, `blog-post`, `layout`, `head`. See "Section slugs" below.
3. **(Recommended) Read the current section.** Use `content_get_section_source` first — start from the existing source rather than from scratch.

### Section slugs

| Slug | Maps to | What it controls |
|---|---|---|
| `header` | `sections/header.liquid` | Site-wide top nav |
| `footer` | `sections/footer.liquid` | Site-wide footer |
| `hero`   | `sections/hero.liquid` | The default-theme hero section (if your pages use `{% section 'hero' %}`) |
| `blog-listing` | `templates/blog.liquid` | The `/blog` index page |
| `blog-post` | `templates/blog-post.liquid` | Individual `/blog/<slug>` chrome |
| `layout` | `layout/theme.liquid` | The outer HTML shell (head, body, where main content + sections render) |
| `head`   | `snippets/head.liquid` | The `<head>` contents (meta tags, favicon links, analytics snippets) |

Any other slug like `myfeature` maps to `sections/myfeature.liquid`. The section then must be referenced from a layout or template via `{% section 'myfeature' %}` to appear — otherwise it's stored but never rendered.

### The 3-call path

```
1. content_get_section_source({ section_slug })   — see what's currently rendering
2. content_override_section({ section_slug, liquid_source })   — write the new source
3. content_deploy_site_production                  — push to edge (~2-5s)
```

Plus visual-check at the end.

#### 1. Get the current source

```
content_get_section_source({ section_slug: "header" })
// → {
//     section_slug: "header",
//     path: "sections/header.liquid",
//     origin: "client_override" | "theme_default",
//     source: "<liquid string OR null if origin is theme_default>"
//   }
```

If `origin: "client_override"` you've already got a custom version — `source` is the Liquid you'd be replacing. If `origin: "theme_default"`, the source is `null` and the response includes a `next_steps` hint pointing at the public theme repo (`github.com/SpiderIQ/SpiderPublish`) so you can grab the baseline as a starting point.

Don't try to fetch the default-theme source via this tool — it lives in the public repo, not in the API. Copy-paste it into your editor as the starting template.

#### 2. Override

```
content_override_section({
  section_slug: "header",
  liquid_source: `
<header class="bg-surface border-b border-neutral-800 sticky top-0 z-10">
  <div class="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
    <a href="/" class="flex items-center gap-2">
      <img src="{{ settings.logo_url }}" alt="{{ settings.site_name }}" class="h-8" />
      <span class="font-semibold">{{ settings.site_name }}</span>
    </a>
    <nav class="flex gap-6">
      {% for item in navigation.header.items %}
        <a href="{{ item.url }}" target="{{ item.target | default: '_self' }}"
           class="text-neutral-300 hover:text-white">{{ item.label }}</a>
      {% endfor %}
    </nav>
  </div>
</header>`
})
// → { success: true, path: "sections/header.liquid", written: true }
```

The override is written to the tenant's per-tenant KV. **The site has NOT changed yet** — templates are cached at deploy time. Step 3 pushes the change live.

**Param-name compatibility** (the tool accepts either pair):
- Canonical: `{ section_slug, liquid_source }`
- Legacy: `{ section, liquid }`

Pass either. If both are supplied, the canonical names win. (Historical detail: there used to be two tools — they were merged in 2026-05-20 per Rule 64.)

**No dry_run/confirm gate** on `content_override_section` by default — it's opt-in via `template_upsert`'s gate fields (`dry_run`, `confirm_token`). For most tenant authoring, immediate writes are fine; the deploy step is the actual customer-facing change.

#### 3. Deploy

```
content_deploy_readiness()
# → { ready: true, ... }

content_deploy_site_preview()
# → { preview_url: "https://preview-XXX.sites.spideriq.ai", confirm_token, ... }
# Eyeball the preview URL before confirming.

content_deploy_site_production({ confirm_token: "cft_..." })
# → { status: "live", version_id: 50 }
```

Site is live in ~2-5s.

### Layout presets — the chrome-only shortcut

If you don't want to write Liquid and you just want a different "shape" of chrome (header? footer? edge-to-edge?), use `content_apply_layout_preset`:

```
content_apply_layout_preset({ preset: "blank" })
// → { success: true, preset: "blank", description: "No header, no footer; full-page content", next_steps: "Deploy ..." }
```

Available presets (writes the corresponding `layout/theme.liquid`):

| Preset | Chrome shape | When to use |
|---|---|---|
| `default` | header + main + footer | Standard site |
| `blank` | no header, no footer | Landing pages where the page content owns the full canvas |
| `minimal` | footer only | Docs / legal — site attribution at bottom, no global nav |
| `landing` | header only | Marketing landing — CTA / form owns the lower viewport |
| `chromed` | header + footer; main is edge-to-edge (no padding) | Pages where content renders wide hero / full-bleed sections |

After applying, deploy. The layout preset only changes `layout/theme.liquid` — individual sections (header, footer) are still whatever you've got. So you can `content_apply_layout_preset({preset: "landing"})` AND have a custom `header` override; the layout switches but your header customization persists.

### Anti-patterns

1. **Customizing `templates/form.liquid` thinking it's the form-page chrome.** That file isn't read. Form pages at `/f/<flow_id>` render via `templates/forms-standalone.liquid` (kind='form') or `templates/booking-standalone.liquid` (kind='booking'), picked server-side by the `/f/` route from the flow's `kind`. To customize form-page chrome, override `forms-standalone` instead. Rule 65.
2. **Targeting `template == 'form'` in `layout/theme.liquid` Liquid conditionals.** Use `template == 'forms-standalone'` — the Liquid `template` variable mirrors the file basename, not a friendly synonym. Rule 65.
3. **Forgetting that the section override survives theme swaps.** `template_apply_theme` lists `templates_to_overwrite` in its dry_run — if your override is in that list, it'll be reset. Save + re-apply. See [`apply-theme.md`](templates-deploy.md#apply-theme).
4. **Writing CSS in `<style>` tags inside section Liquid (vs the theme's `assets/styles.css` or a `{% style %}` tag).** Sections render in normal DOM, not Shadow DOM, so `<style>` works — but conventionally CSS lives in theme assets or settings.custom_head_code. Inline `<style>` in a section is fine but noisy.
5. **Deploying without `content_deploy_readiness` first.** Save the round-trip on a failed deploy.
6. **Section with no `{% section 'X' %}` reference in any layout / template.** The override is written but never rendered. Add the reference to a layout (or template) that uses the section.

### See also

- [`apply-theme.md`](templates-deploy.md#apply-theme) — swap the entire theme (vs override one section)
- [`landing-page.md`](content.md#landing-page) — author pages that use the overridden sections
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the two-phase deploy after override
- [`../reference/tool-surface.md`](tool-surface.md) — `template_*` + `content_override_section` tools
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth
- catalog/LEARNINGS.md Rules 64 + 65 — source incidents


---

## Scroll Video Hero

Cinematic scroll-scrubbed hero from a source video — **one tool call**.

### The one-shot path (preferred, v2.87.0+)

```
video_to_scroll_sequence(
  video_url = "https://media.cdn.spideriq.ai/.../hero.mp4",
  page_slug = "home"
)
```

That single MCP call runs the whole pipeline server-side:
1. Submits `extract_frames` against the video (ffmpeg, WebP, ~7× smaller than JPEG).
2. Polls to completion.
3. Inserts a `sys-scroll-sequence` component block into the target page **as a draft**.
4. Returns `{manifest, block, page}` including the new version ID.

Then, because the block lands as a draft (never auto-publishes):
```
content_deploy_site_preview()        → review at preview-XXX.sites.spideriq.ai
content_deploy_site_production(confirm_token)
```

#### Common variants

```
# Custom frame count + longer scroll distance
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  target_frames=180,
  scroll_distance_vh=600,
)

# FPS-based sampling instead of exact count
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  strategy="fps", fps=24,
)

# Insert before an existing hero block instead of appending
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  position={"before": "hero-gradient"},
)

# Just want the block JSON, don't touch the page yet
video_to_scroll_sequence(
  video_url="...", page_slug="home",
  dry_run=true,
)
```

### Two input shapes (v1.1.0+)

The `sys-scroll-sequence` component accepts **either** of these prop shapes:

#### Shape A — `{base_url, pattern, count}` (preferred)

```json
{
  "type": "component",
  "component_slug": "sys-scroll-sequence",
  "props": {
    "base_url": "https://media.spideriq.ai/client-xxx/content/scroll-sequences/<job_id>",
    "pattern": "frame_{0001..0120}.webp",
    "count": 120,
    "scroll_distance_vh": 400,
    "preload_strategy": "progressive"
  }
}
```

This is what `video_to_scroll_sequence` produces. Tiny prop footprint (~20 bytes of URLs), component expands them at render time. **Use this whenever frames come from `extract_frames`.**

#### Shape B — `{image_urls[]}` (v1.1.0, for hand-picked URLs)

```json
{
  "type": "component",
  "component_slug": "sys-scroll-sequence",
  "props": {
    "image_urls": [
      "https://cdn.example.com/hero/frame_001.webp",
      "https://cdn.example.com/hero/frame_002.webp",
      "..."
    ],
    "scroll_distance_vh": 400,
    "preload_strategy": "progressive"
  }
}
```

Use when frames live on multiple hosts, have non-numeric names, or come from a legacy CDN that doesn't fit a URL pattern. Heavier (all URLs stored inline, up to 600), but unconstrained.

The component's `oneOf` schema rejects mixing both shapes in the same block.

### The legacy 5-step recipe (fallback — still works)

If your MCP server is older than v2.87.0 (no `video_to_scroll_sequence` tool) or you need to split the steps for a custom flow:

1. **Reference a source video** — must be a public URL (SpiderMedia or di-atomic preferred).
   Tool: `upload_file` / `media_import_from_url` if the video isn't already hosted.

2. **Submit `extract_frames` job.**
   Tool: `submit_job(type="spiderVideo", payload={action:"extract_frames", ...})`.
   Params:
   - `video_url` — the mp4 URL
   - `strategy` — `"target_frames"` (default 120), `"fps"`, or `"duration_fps"`
   - `output_format` — `"webp"` (recommended)

3. **Poll until completion.**
   Tool: `get_job_results(job_id)` → `status == "completed"` → manifest at `data.manifest = {base_url, pattern, count}`.

4. **Insert the `sys-scroll-sequence` block into a page.**
   Tool: `content_create_page` / `content_update_page`.
   ```json
   {
     "type": "component",
     "component_slug": "sys-scroll-sequence",
     "props": {
       "base_url": "<from manifest>",
       "pattern":  "<from manifest>",
       "count":    <from manifest>,
       "scroll_distance_vh": 400,
       "preload_strategy": "progressive"
     }
   }
   ```

5. **Deploy.**
   `content_deploy_site_preview` → verify → `content_deploy_site_production(confirm_token)`.

The one-shot call just bundles steps 2–4 into a single API call. Step 1 stays explicit (you decide where the source lives), and step 5 stays explicit (preview + confirm_token gate).

### Why not hand-roll your own frames?

- `sys-scroll-sequence` is Tier 3 (GSAP + ScrollTrigger) and handles canvas setup, sticky positioning, progressive preload (±15 frame window) — so your component stays ~2 KB of JS instead of 14 KB.
- Hardcoding 100+ URLs in a custom component triggers CDN rate-limit drops → black-frame "flashlight strobe" during scroll.
- Tier 3 CDN deps are deduplicated globally — your page doesn't pay the GSAP load cost twice.

### Recommended frame counts

| Scroll section length | Frames | Strategy |
|---|---|---|
| Short hero (~400 vh) | 90–120 | `target_frames=120` |
| Medium hero (~600 vh) | 120–180 | `target_frames=150` |
| Long cinematic (1000 vh+) | 180–240 | `target_frames=200` |

Above 240 frames: split into two sequences or use a real `<video>` element.

### Files in this skill

- `SKILL.md` — this file (human-readable recipe)
- `schema.yaml` — Tier 2 tool-sequence (one-shot + legacy 5-step)
- `impl.ts` — Tier 3 self-contained TypeScript against `@spideriq/core`

### See also

- [AGENTS.md → Scroll-Linked Hero](../SKILL.md)
- [LEARNINGS.md → Media & Scroll-Sequences](../SKILL.md)
- examples/scroll-sequence.sh — runnable bash version
- components/scroll-sequence.json — block-config reference


---

## Preview Iteration

The safe component-edit loop. Lets you iterate on a component's HTML/CSS/JS without touching DB state or production, then promote once it's right.

### The 4-stage loop

```
  template_preview (pure — no DB write, no deploy)
          │
          ▼
  open preview URL in a browser
          │
          ▼
  happy with look?  ──NO──▶ edit source, back to template_preview
          │
          ▼
  content_create_component or content_update_component (dry_run → confirm_token)
          │
          ▼
  content_publish_component (dry_run → confirm_token)
          │
          ▼
  content_deploy_site_preview  →  verify  →  content_deploy_site_production
```

### Why this matters

Before `template_preview` existed, the only way to check a component's rendering was to create-publish-deploy it — full round-trip, impossible to back out cleanly. This recipe is the "dev environment" Antigravity's report asked for. It already exists — it just wasn't obvious.

### Step-by-step

1. **Draft locally** — write your HTML / CSS / JS / props_schema in your editor. No MCP calls yet.

2. **Preview** — call `template_preview`:
   ```json
   {
     "component": {
       "html_template": "<section>...</section>",
       "css": ":host { ... }",
       "js": "root.querySelector(...)",
       "props_schema": { "type": "object", "properties": { ... } }
     },
     "props": { "headline": "Test", "cta_url": "#" }
   }
   ```
   Returns: `{ preview_url, rendered_html, resolved_context }`. **No DB write. No KV write. No deploy.**

3. **Browser-check** — open `preview_url` in your own browser (or an agent-browser). Look for:
   - Layout collapsed / font wrong → CSS issue
   - Props not binding → props_schema mismatch
   - JS error in console → scoped-JS issue (probably `document.querySelector` instead of `root.querySelector`)

4. **Iterate** — edit, call `template_preview` again. Repeat until correct.

5. **Save draft** — `content_create_component` (or `content_update_component`). Destructive mutation, gated:
   ```
   content_create_component({...}, dry_run=true)   → returns confirm_token
   content_create_component({...}, confirm_token)  → actually creates
   ```

6. **Publish** — `content_publish_component(id, dry_run=true → confirm_token)`. Now it's referenceable from page blocks as `component_slug`.

7. **Deploy** — reference it in a page block, then:
   ```
   content_deploy_site_preview()              → preview_url + confirm_token
   # verify in browser
   content_deploy_site_production(confirm_token)
   ```

### What NOT to do

- **Don't skip `template_preview`.** Creating-publishing-deploying a broken component pollutes your version history and costs you a rollback cycle.
- **Don't reuse a `confirm_token`.** They're single-use. Call `dry_run=true` again to issue a fresh one.
- **Don't hold a `confirm_token` for more than 10 minutes.** They expire. Re-issue.

### See also

- [skills/templates-engine](../SKILL.md) — full template tool surface including `template_preview`
- [skills/content-platform](../SKILL.md) — component CRUD
- CLAUDE.md in the repo root has the full Phase 11+12 preview→confirm flow


---

## Restore Page Version

Roll a page back to a historical snapshot — **safely**. The restore tool defaults to dry_run so you see the diff before you spend a confirm_token.

### When to use

- A bad deploy hit production and you need to revert one page without rolling back the whole site (for the site-level rollback see [`../deploy/rollback-deploy.md`](templates-deploy.md#rollback-deploy)).
- A client edit dropped a hero / CTA and you want to bring back the previous version's `blocks[]`.
- A teammate landed a draft on the wrong page and you need the original copy back.
- Auditing what changed between version N and N+1 before deciding whether to restore.

### Prerequisites

- A PAT scoped to the tenant that owns the page (see [`../../_shared/auth.md`](../SKILL.md)).
- The page's `page_id` (UUID). Get it from `content_list_pages` or the dashboard URL.
- A historical `version_number` to target. `content_list_page_versions({ page_id })` returns the full ledger; each row carries `{version_number, snapshot_block_count, snapshot_created_at, change_summary}`.
- If the page is currently **locked** (a teammate parked it for review), you need either the lock holder's session OR `super_admin` / `brand_admin` to pass `force=true`. See [`lock-page-during-review.md`](content.md#lock-page-during-review).

### Steps

#### 1. List versions to find your target

```
content_list_page_versions({ page_id: "<uuid>" })
# → [
#     { version_number: 7, snapshot_block_count: 14, snapshot_created_at: "...", change_summary: "Updated hero copy" },
#     { version_number: 6, snapshot_block_count: 12, ... },
#     ...
#   ]
```

Pick the version you want to land — usually the one immediately before the bad change.

#### 2. Inspect the target version (optional, recommended)

Before restoring, see what the snapshot actually looks like:

```
content_get_page_version({ page_id: "<uuid>", version_number: 6 })
# → { page: {<full snapshot>}, version_number: 6, snapshot_created_at: "..." }
```

Useful when version numbers are dense and you're not sure which one carries the wording you remember.

#### 3. Dry-run the restore

```
content_restore_page_version({
  page_id: "<uuid>",
  version_number: 6
})
# → {
#     dry_run: true,
#     preview: {
#       before: { block_count: 14, status: "published", title: "Pricing" },
#       after:  { block_count: 12, status: "draft",     title: "Pricing" },
#       diff:   { blocks_removed: 3, blocks_added: 1, snapshot_created_at: "..." }
#     },
#     confirm_token: "cft_01HXXXXXXXXXX",
#     expires_at: "...",
#     snapshot_hash: "sha256:..."
#   }
```

This is `safe-default gate` — dry_run is **on by default** (see [`../reference/deploy-protocol.md`](deploy-protocol.md) → "Safe-default gate"). The preview lists `snapshot_block_count` vs `current_block_count` + `snapshot_created_at`. Verify the deltas match your intent.

#### 4. Consume the token

```
content_restore_page_version({
  page_id: "<uuid>",
  version_number: 6,
  confirm_token: "cft_01HXXXXXXXXXX"
})
# → { success: true, page: {<new draft>}, new_version_number: 8 }
```

The restored page lands as **status='draft'** — never auto-publishes over the live page. A new version row is appended (here `8`) recording the restore so the audit chain stays intact: 6 → 7 (bad change) → 8 (restore from 6). You can always re-restore to 7 if the restore itself was wrong.

#### 5. Verify, then publish

```
content_get_page({ page_id: "<uuid>" })
# → confirm blocks[] match the version 6 snapshot you expected

content_publish_page({ page_id: "<uuid>" })
# → safe-default dry_run; preview the diff, then confirm with token
```

If this page is part of a published site, follow with `content_deploy_site_preview` → `content_deploy_site_production` to push the change live. See [`../reference/deploy-protocol.md`](deploy-protocol.md).

### Gotchas

- **The restore always lands as draft.** If the live version was 7 and you restore from 6, visitors still see 7 until you publish 8 (the restore). That's by design — same reason the dry_run is on; gives you a chance to compare.
- **`snapshot_hash` is bound to the page state at dry_run time.** If a teammate edits the page between your dry_run and confirm, you get a 403 `snapshot_mismatch`. Re-run dry_run; the diff will reflect their edit.
- **Token TTL is 7 days** for tool-level dry_runs (5 minutes for the deploy pipeline). Sitting on a restore token over a weekend is fine; sitting on it for two weeks is not.
- **Locked pages refuse restore without `force`.** A 423 envelope returns `{ locked_by_actor_id, locked_reason, unlock_endpoint }`. Either call `unlock_page` first (if you own the lock) or pass `force=true` if you have `super_admin` / `brand_admin`.
- **Page slug doesn't roll back** — the restore brings back `blocks[]`, `title`, `seo_title`, `seo_description`. The current slug stays. If you also need to roll back the slug (rare), follow up with `content_update_page({ page_id, slug: "<old-slug>" })`.

### Verify

After publishing the restored version, eyeball the live page if the tenant has a custom domain attached:

```
content_visual_check({
  page_url: "https://<tenant-domain>/<page-slug>",
  viewport: "desktop"
})
# → { ok: true, body_text_preview: "...the restored copy you expect..." }
```

If the page contains a form, assert on `dom.shadow_hosts.includes("spideriq-form")`, **NOT** `body_text_preview` — see Rule 62 in [`../reference/booking-model.md`](booking-model.md).

### Anti-patterns

- **Calling restore without listing versions first.** `version_number` is 1-indexed and dense. Guessing "the previous one" picks the wrong row half the time. Always list, then `get_page_version` to confirm, then restore.
- **Treating restore as a delete-and-recreate.** It's not. Restore re-emits `blocks[]` from the snapshot into a **new draft** on the same page row — same `page_id`, same primary key. No URLs break, no inbound links rot.
- **Skipping the dry_run** because "I'm sure." The safe-default gate exists for exactly the case where you're sure and wrong. Cost is one extra round-trip; benefit is the diff envelope catching a wrong-tenant call (Lock 1) or wrong-page-id (Lock 5 — see [`../reference/deploy-protocol.md`](deploy-protocol.md)).
- **Forgetting to publish + deploy after restoring.** The restored page sits as draft until you publish; the site visitors still see the old version until `content_deploy_site_production` runs. Restore is two steps in STORE; visitors don't see anything until SERVE redeploys.
- **Using `force=true` to bypass another reviewer's lock without coordinating.** The lock holder will see your restore land mid-review. Ping them in chat first; locks exist precisely to avoid this surprise.

### See also

- [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) — verify the restored page renders correctly before/after deploy
- [`lock-page-during-review.md`](content.md#lock-page-during-review) — pair with restore: lock → restore → unlock
- [`../deploy/rollback-deploy.md`](templates-deploy.md#rollback-deploy) — site-level rollback (every page in one shot)
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — `safe-default gate`, confirm-token envelopes, `ConfirmTokenError` map
- [`../../_shared/auth.md`](../SKILL.md) — PAT scope + tenant binding


---

## Lock Page During Review

Lock a page against further edits during client review or scheduled launch. Other agents (and dashboard users) see **423 Locked** with the lock provenance and an `unlock_endpoint` URL until the lock-holder (or a super_admin via `force=true`) unlocks. Closes the gap where two agents race on the same page mid-review.

### When to use

- Designer or agency hands a page off for client review and doesn't want any agent to keep editing.
- Scheduled launch — page is "frozen" until a specific date/time; lock is set at the start and unlocked at go-live.
- An incident — a published page is misbehaving and you want to stop further mutations while you investigate.
- Pre-restore — before calling `content_restore_page_version`, lock the page so a parallel agent doesn't apply more edits between the dry-run preview and the confirm.

### The one-shot calls

```bash
# Lock
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/lock
Body: { "reason": "client review week of 2026-05-12" }
# → { id, slug, is_locked: true, locked_by_actor_id, locked_at, locked_reason }

# Unlock (lock-holder OR super_admin / brand_admin with ?force=true)
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/unlock
# → { id, slug, is_locked: false, locked_by_actor_id: null }

# List versions
GET /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/versions
# → { page_id, versions: [{version_number, title, block_count, blocks_size, change_summary, created_at, ...}], total }

# Get one version (full body)
GET /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/versions/{N}

# Restore — Phase 11+12 dry_run/confirm_token gated
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/restore?version_number=N&dry_run=true
# → { dry_run: true, preview: {snapshot_block_count, current_block_count, snapshot_created_at, will_become}, confirm_token, expires_at }
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/restore?version_number=N&confirm_token=cft_xxx
# → restored page row (status=draft; new version row appended with change_summary='Restored from vN')
```

**MCP tools** — ship in `@spideriq/mcp-publish@1.11.0+` and kitchen-sink `@spideriq/mcp@1.11.0+` (94 atomic tools total):

- `content_lock_page({page_id, reason?})`
- `content_unlock_page({page_id, force?})` — `force=true` requires super_admin or brand_admin (server-enforced)
- `content_list_page_versions({page_id})`
- `content_get_page_version({page_id, version_number})`
- `content_restore_page_version({page_id, version_number, dry_run?, confirm_token?, force?})`

### The 423 Locked envelope (what other agents see)

When the page is locked and a mutation comes in (`PATCH /pages/{id}`, `/publish`, `/unpublish`, `DELETE`, `/insert-section`, `/restore`), the server returns **HTTP 423 Locked** with this body:

```json
{
  "detail": {
    "error": "page_locked",
    "message": "Page is locked by api:cli_xxx.",
    "locked_by_actor_id": "api:cli_xxx",
    "locked_at": "2026-05-09T21:11:00Z",
    "locked_reason": "client review week of 2026-05-12",
    "unlock_endpoint": "/api/v1/dashboard/projects/cli_xxx/content/pages/<id>/unlock"
  }
}
```

**Recovery path for the receiving agent:**

1. Parse `locked_by_actor_id` and `locked_reason`. If the reason indicates a deadline ("client review week of 2026-05-12"), the right move is to back off and revisit later.
2. If you are the lock-holder (your `actor_id` matches), call `content_unlock_page({page_id})` and retry.
3. If you have super_admin or brand_admin role and the lock-holder is unavailable, call `content_unlock_page({page_id, force: true})`. This emits an audit row.
4. Otherwise: do not retry mechanically. Use `content_list_page_versions` if you need to inspect history during the lock window — that endpoint is read-only and works on locked pages.

### Authorization model

| Actor | Can lock? | Can unlock (own lock)? | Can unlock (someone else's lock)? |
|---|---|---|---|
| `client_user` | yes | yes | no |
| `brand_admin` | yes | yes | yes (with `?force=true`) |
| `super_admin` | yes | yes | yes (with `?force=true`) |
| `api_client` (PAT) | yes | yes | no — even with `force=true`, server returns 403 (`force=true requires super_admin or brand_admin role.`) |

### Idempotency

- **Lock** is idempotent — re-locking refreshes `locked_at` and `locked_reason`. The previous lock-holder loses the lock provenance but mutations stay refused.
- **Unlock** on an already-unlocked page returns the current page state (no error).
- **Restore** appends a NEW version row recording the restore — the audit chain stays linear. Calling restore against the same `version_number` twice creates two new version rows.

### Anti-patterns

- **Don't** call `content_unlock_page({force: true})` reflexively when you see a 423. Read the `locked_reason` first; if it names a deadline, the lock is intentional. Force-unlocking around an active client review breaks the trust model the lock exists to enforce.
- **Don't** loop on a 423 retry-without-backoff. The lock provenance won't change until someone explicitly unlocks. If your agent is the lock-holder (matched `actor_id`), call unlock; otherwise back off.
- **Don't** call `content_publish_page` to "force" through a lock. Publish is gated by the same lock check; you'll get the same 423.
- **Don't** assume `versions[]` is unbounded — `version_number` is monotonically increasing and a long-lived page can accumulate hundreds of versions. Use the `block_count` + `blocks_size` summary in the list to decide which versions to fetch in full.

### Idempotency / cost notes

- Lock toggle is a single `UPDATE content_pages` — sub-millisecond.
- Versions list uses `idx_content_pages_locked` partial index for the cross-tenant "what's locked" query (super_admin admin dashboard).
- `versions/{N}` returns the full snapshot blocks — can be tens of KB; prefer the summary list for browsing, fetch the full version only when you need to diff.


---

## Export Page Roundtrip

Pull the **full page envelope** — page row + every referenced component inlined + settings + domains + audit walk — in one call. Use this when you need the whole picture before editing, or for a VSCode-extension round-trip (export → edit locally → push back).

### When to use

- You need to understand what a `vp-hero` block actually is (its `html_template`, `css`, `js`, `props_schema`) before editing the page that uses it.
- A page references a Tier 3 component (GSAP / ScrollTrigger / Three.js) and you want to know about latent dependencies before redeploying.
- Surfacing broken sections before pushing — the PageAuditor walk catches scroll-sequence empty frames, missing primary domain, SEO holes, etc.
- Round-tripping a page through the **VSCode extension** for offline editing: export → `spideriq pull` into local registry → edit JSON/Markdown → `spideriq push` back.
- Backing up a page for archival before a high-risk template-apply or theme swap.

### Prerequisites

- A PAT scoped to the tenant (see [`../../_shared/auth.md`](../SKILL.md)).
- The page's `page_id` (UUID).

### The one call

```
content_export_page({
  page_id: "<uuid>",
  format: "json"   # default; alternatives: "md" | "archive"
})
```

That single MCP call returns a **flat envelope** containing:

1. **`page`** — the full row (title, slug, status, `blocks[]`, seo_*, template, version_number).
2. **`components`** — for every component referenced by `page.blocks`, the FULL component body inlined: `html_template`, `js`, `css`, `props_schema`, `dependencies`, `agent_meta`, `kind`, `layouts`.
3. **`settings`** — the tenant's `content_settings` row (default_meta_title, default_meta_description, brand_colors, font_family, etc.).
4. **`domains`** — the tenant's `content_domains` rows (primary + aliases, verified status, CF zone IDs).
5. **`audit`** — a PageAuditor walk with **10 v1 rules**:
   - scroll-sequence empty frames
   - missing primary domain
   - page SEO holes (no `seo_title`, no `seo_description`)
   - latent Tier 3 components (CDN deps not in `dependencies`)
   - duplicate `block.id` values
   - orphan `anchor_block_id` references
   - … (full list in the response under `audit.rules`)
6. **`manifest`** — `{exported_at, exporter_version, snapshot_hash}` so a downstream `spideriq push` can detect divergence.

### The three output formats

| Format | Use when | Returns |
|---|---|---|
| **`json`** (default) | Programmatic consumption — feeding the envelope into another tool, building a backup pipeline | Flat JSON object |
| **`md`** | Human review, code review on a PR, sharing context with a teammate via chat | Single Markdown document with sections per slice |
| **`archive`** | VSCode-extension round-trip; matches the local-registry layout 1:1 | ZIP byte stream: `page.json` + `components/<slug>@<version>.json` (one file per component) + `settings.json` + `domains.json` + `audit.md` + `manifest.json` |

The `archive` shape matches what `spideriq pull` writes to disk, so:

```bash
# Pull the export → local registry
spideriq content pages export <page-id> --format archive --out ./tenant-snapshot.zip
unzip ./tenant-snapshot.zip -d ./tenant-snapshot/

# Edit files locally with the VSCode extension
# (the extension watches ./tenant-snapshot/page.json and the components/*.json files)

# Push back when done
spideriq content pages push ./tenant-snapshot/
```

`spideriq push` runs the same `content_export_page` against the live page first, diffs the local copy against the fresh export, and emits `content_update_page` + per-component `content_update_component` mutations only for changed slices. If the live page diverged between your pull and push, you get a merge prompt — not a silent overwrite.

### Choosing between `content_get_page` and `content_export_page`

| Tool | Returns | Cost | Use when |
|---|---|---|---|
| `content_get_page` | The page row alone (blocks reference components by slug + version, body NOT inlined) | Cheap — single SELECT | You only need page metadata, blocks, SEO. The components themselves are already known. |
| `content_export_page` | Page + ALL referenced components inlined + settings + domains + audit | Heavier — N+1 SELECTs + audit walk | You need the FULL picture before editing, OR you're doing a round-trip, OR you want the audit walk |

Default to `content_get_page`. Reach for `content_export_page` when you actually need the components inlined.

### Gotchas

- **The envelope is a snapshot, not a live view.** Two seconds after export, the page might have moved. The `manifest.snapshot_hash` lets a downstream push detect this; without it, you're flying blind.
- **`audit` is informational, not blocking.** A page with audit findings can still be edited and republished. The audit is your hint about what to fix; SpiderPublish doesn't reject mutations based on it.
- **Component inlining can be large.** A page with 12 Tier 3 components can produce a 500 KB envelope (each component's `js` can be ~30 KB). The `archive` format zips this; the `json` and `md` formats don't.
- **Archive format isn't a backup substitute.** It's a point-in-time export of one page + its components. For tenant-wide backups, run R2 backups (see `CLAUDE.md` → Backups in the main repo).
- **Setting `format: "md"` flattens the JSON tree** for readability but loses the round-trip path. Use `json` or `archive` if you intend to push changes back.

### Verify

For a JSON export, sanity-check the envelope before consuming:

```bash
jq 'keys' export.json
# → ["audit", "components", "domains", "manifest", "page", "settings"]

jq '.audit.findings | length' export.json
# → 0   (clean) or N (issues to surface to the user)

jq '.components | keys' export.json
# → ["hero-gradient", "cta-button", "faq-accordion", ...]
```

For an archive export:

```bash
unzip -l snapshot.zip
# Archive: snapshot.zip
#   page.json
#   components/hero-gradient@v3.json
#   components/cta-button@v2.json
#   settings.json
#   domains.json
#   audit.md
#   manifest.json
```

### Anti-patterns

- **Using `content_export_page` for a quick metadata read.** Use `content_get_page` instead — 10× cheaper.
- **Pushing back a modified `md` export.** The Markdown format is one-way (export only); the `spideriq push` path only consumes `archive` (preferred) or `json`. Edit those.
- **Editing the inlined component body inside `components[]` and expecting it to land on the component row.** The exporter inlines for context; round-trip push routes component edits through `content_update_component` separately. Mixing semantics breaks the push diff.
- **Treating the audit walk as authoritative.** It's 10 lightweight rules. For a deeper analysis run [`../audit/audit-and-fix.md`](audit.md#audit-and-fix) — that adds visual-check, link-audit, and tenant-scope verification.
- **Skipping the manifest check on push.** `manifest.snapshot_hash` is the safety net against "I edited locally for two days; live page moved underneath." Always check it.

### See also

- [`../audit/audit-and-fix.md`](audit.md#audit-and-fix) — full audit suite (this recipe's `audit` slice is a subset)
- [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) — Playwright sidecar for live-render verification
- [`duplicate-page.md`](content.md#duplicate-page) — when you want a copy in STORE rather than an offline export
- [`restore-page-version.md`](content.md#restore-page-version) — roll back to a historical snapshot (different semantic; no offline edit)
- [`../reference/block-types.md`](block-types.md) — block model + component reference shape (what gets inlined)


---

## Import Tilda Site

Port a Tilda (or Webflow / Lovable / hand-coded) site to SpiderPublish as Shadow-DOM components, one section at a time, using the opt-in `auto_extract_css` flag so inline `<style>` blocks don't blow up.

### When to use

- You have legacy HTML that embeds `<style>` blocks in every section (the Tilda / Webflow pattern).
- You want every section to render isolated via Shadow DOM so migrations don't introduce CSS spillage.
- You're migrating 10–60 pages and want a repeatable script-per-section flow.

**Not for:** hand-authored components where you want the explicit-over-magical contract. Default behavior still rejects inline `<style>` with a 400 — this recipe is the opt-in escape hatch.

### Proven references

| Client | Domain | Notes |
|---|---|---|
| SMS-Chemicals | sms-chemicals.com | First full Tilda → SpiderPublish port. Referenced below. |
| Di-Atomic | di-atomic.com | 33 pages, large component library; hit the silent-accept bug + duplicate-component-variant trap. |
| Onyx Radiance | onyx-radiance.com | From-scratch rebuild; pioneered the category='header'\|'footer' auto-skip pattern. |

### Steps

#### 1. Export the source HTML

- **Tilda:** download `.zip` from the Tilda dashboard, or use the Tilda API with `TILDA_PUBLIC_KEY` / `TILDA_PRIVATE_KEY`.
- **Webflow / Lovable / hand-coded:** extract each page section into its own HTML file. A section = a logical block (hero, features, CTA, pricing, footer, …).

You want one HTML file per component-to-be.

#### 2. Upload images to SpiderMedia

Don't leave `src="…"` pointing at `static.tildacdn.one` or other external hosts — edge caching won't help, rate limits will bite you, and link-rot breaks your site months later. One call:

```bash
# MCP
upload_local_directory(local_dir="./tilda-export/images/", folder="tilda-migration/")
# or CLI
npx @spideriq/cli media upload ./tilda-export/images/ --folder tilda-migration/
```

Then rewrite every `src`/`href` in your exported HTML to point at `https://media.cdn.spideriq.ai/…`.

#### 3. Create each section as a component with `auto_extract_css=true`

The server regex-extracts every `<style>...</style>` block from `html_template` and appends the contents to the `css` field before the loud-error validator runs. Your legacy HTML stays readable; Shadow DOM stays isolated.

```bash
POST /api/v1/dashboard/projects/{pid}/content/components
{
  "slug": "home-hero",
  "name": "Home Hero",
  "category": "hero",
  "html_template": "<style>.hero{background:#0a0a0b;...}</style><section class=\"hero\">...</section>",
  "auto_extract_css": true
}
# → 200 OK. Response: html_template is clean (no <style>), css contains the moved rules.
```

Runnable end-to-end: examples/tilda-migrate.sh.

#### 4. Mark headers/footers with `category` so native chrome auto-skips

If the page will have a custom header or footer component, create it with `category: "header"` or `"footer"`:

```json
{ "slug": "acme-header", "category": "header", "html_template": "<header>...</header>", "css": "..." }
```

When any page block resolves to a component with `category='header'`, the renderer suppresses the native `{% section 'header' %}`. No `nukeUI()` polling JS, no `template='blank'` fallback, no conditional `copyright_text` scripts. Same rule for footers.

#### 5. Publish the component

```bash
POST /components/{id}/publish?dry_run=true   → confirm_token
POST /components/{id}/publish?confirm_token=cft_…  → published
```

#### 6. Create the page with canonical block payload

**Anti-pattern (returns 422 since 2026-04-24):**

```json
// ❌ component_slug belongs at the BLOCK's top level, not under data
{ "type": "component", "data": { "slug": "home-hero", "props": {...} } }
```

**Canonical shape:**

```json
{
  "id": "b1-hero",
  "type": "component",
  "component_slug": "home-hero",
  "component_version": "1.0.0",
  "props": { "headline": "Welcome" }
}
```

**Flat slugs only:** `product-pillowcase`, not `product/pillowcase`. Nested slugs return 422 at creation (the renderer can't route them anyway).

```bash
POST /content/pages
{
  "slug": "home",
  "title": "Home",
  "template": "default",
  "blocks": [
    { "id": "b1-header", "type": "component", "component_slug": "acme-header", "component_version": "1.0.0" },
    { "id": "b2-hero",   "type": "component", "component_slug": "home-hero",   "component_version": "1.0.0" },
    { "id": "b3-footer", "type": "component", "component_slug": "acme-footer", "component_version": "1.0.0" }
  ]
}
```

#### 7. Publish + deploy

```bash
# Per-page
POST /pages/{id}/publish?dry_run=true  → confirm_token  → consume

# Site-wide, when all pages are in
content_deploy_site_preview()           → review preview_url
content_deploy_site_production(confirm_token=...)  → live in ~2-5 s
```

Use `--yolo` on the CLI (`spideriq content deploy --yolo`) if you're iterating on copy and don't need the preview step.

### Anti-patterns that cost hours

| Don't | Why | Do |
|---|---|---|
| POST HTML with inline `<style>` and no `auto_extract_css=true` | 400: "Found `<style>` block… Component CSS must live in the `css` field" | Pass `auto_extract_css: true` |
| Leave external `<link rel="stylesheet">` inside `html_template` | Shadow DOM silently ignores it — blank section | Inline the CSS (download, concat, put in `css` field) |
| Use `slug: "product/pillowcase"` | 422 at creation (since 2026-04-24) | Flat slug `product-pillowcase` |
| Write `nukeUI()` JavaScript to hide double chrome | Polling setInterval → FOUC + CPU burn | Create header with `category: "header"` — renderer auto-suppresses native |
| Pass `data: {slug: "x"}` on a component block | 422 since 2026-04-24 | `component_slug: "x"` at the block's top level |
| `filename="..."` without `preserve_filename: true` on bulk media upload | Prefixed `YYYYMMDD_HHMMSS_` in the key → your relative image URLs break | `preserve_filename: true` (auto-enabled by `upload_local_directory` for `scroll-sequences/*`) |
| Loop `component_update` + N × `content_update_page` to change a shared component | 10+ calls, risk of partial update | `component_update_and_propagate(slug, ...)` — one call |

### Cleanup after ship

```bash
# Verify no broken links survived the migration
content_audit_links()
```

If `broken[]` has entries that are legacy `/old/…` paths you don't want to preserve, create `content_redirect` rows (301s) to the new locations.

### See also

- [recipes/component-update-and-propagate](components.md#update-and-propagate) — for site-wide header/footer changes post-migration
- [recipes/link-audit](audit.md#link-audit) — the post-migration check
- [recipes/bulk-media-upload](media.md#bulk-upload) — for moving the Tilda image assets in one call
- examples/tilda-migrate.sh — runnable end-to-end
- [LEARNINGS.md → Apr 2026 Triage](../SKILL.md) — the silent-failure modes this recipe closes
