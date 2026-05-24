# recipes/content/docs-page

Add a page to the docs tree — title, body (Tiptap JSON), parent doc for nesting, computed `full_path`. Powers the `/docs/*` URL surface on every SpiderPublish tenant.

## When to use

- A tenant has a `docs/` section on their site and wants to add a new page.
- You need parent/child nesting: a sub-page under an existing parent (`/docs/getting-started/install` under `/docs/getting-started`).
- You want to reorder docs in the sidebar (via `sort_order`).

For a one-off marketing page that's NOT under `/docs/*` → use [`landing-page.md`](landing-page.md). For a blog post → [`blog-post.md`](blog-post.md). Docs are a separate tree with their own router (Liquid template `docs.liquid` → `templates/doc.liquid` for individual pages).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (paste output; exit 0 = safe).
2. **Parent doc exists** (if you're nesting). Discover with `content_docs_tree()`. If you're adding a top-level doc, no parent needed.
3. **Theme has `templates/docs.liquid` and `templates/doc.liquid`.** Default theme ships both; check `template_list()` if you've customized.

## The 3-call path

```
1. content_docs_tree                 — see the existing tree + find parent_id
2. content_create_doc                — add the new doc (immediate; no dry_run default)
3. content_get_settings (optional)   — confirm site_url for the public URL
```

No publish step — docs go live the moment they're created. No separate deploy needed (docs render at request time, like blog posts).

### 1. Get the tree

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

### 2. Create the doc

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

### 3. (Optional) confirm the public URL

```
content_get_settings()
// → { site_name, ..., primary_domain: "<tenant>.com", ... }
```

The new doc is at `https://<primary-domain>/docs/getting-started/authentication`. If `primary_domain` is null, the URL is `https://<tenant>.sites.spideriq.ai/docs/...`.

## Reorder docs in the sidebar

Sibling ordering uses `sort_order` (integer; ascending). To reorder:

- Set `sort_order: 0, 10, 20, ...` (gaps of 10 leave room for insertions).
- The REST API is `PATCH /content/docs/{id} { sort_order: N }`. No first-party MCP tool yet (follow-up).
- Dashboard UI: drag-and-drop the tree, which writes `sort_order` per node.

Default behaviour: docs without explicit `sort_order` sort by `created_at`.

## Duplicate a doc

```
content_duplicate_doc({
  doc_id:   "doc_...",
  new_slug: "duplicate-of-authentication"   // optional; defaults to <orig-slug>-copy
})
// → { id: "doc_..." (new), parent_id: same as source, full_path: ..., status: "draft" }
```

Phase 11+12 is **opt-in** on duplicate.

## Update a doc body

There's no first-party `content_update_doc` MCP tool yet (queued follow-up). Two paths today:

1. **Dashboard:** open the doc in Content Studio's docs editor.
2. **REST:** `PATCH /api/v1/dashboard/projects/{pid}/content/docs/{id}` with `{ body: {...}, title?: "..." }`.

## Verify

```
content_visual_check({
  page_url: "https://<tenant>/docs/<full_path>",
  viewport: "desktop"
})
// → { success: true, body_text_preview: "...your title literal...", console_errors: [] }
```

Check `body_text_preview` contains your title + a snippet from the body.

## Anti-patterns

1. **Passing `body` as a string.** Tiptap JSON — `{type: "doc", content: [...]}`. Strings silently render empty.
2. **Passing `slug` with `/` in it.** Slugs are FLAT segments (`^[a-z0-9][a-z0-9-]*$`). The URL hierarchy comes from `parent_id` chains, not slug paths. `slug: "getting-started/install"` either 422s on validate or silently flattens.
3. **Setting `full_path` directly.** Server-computed. Pass `parent_id` instead.
4. **Trying to reorder via `slug` rename.** Use `sort_order`. Renaming a slug breaks every external link to the doc.
5. **Forgetting to add the new doc to the docs sidebar nav.** Docs auto-appear in the docs tree (template iterates `content_docs_tree`), so you don't need to add it to a menu. But if your theme has a custom sidebar nav with hand-curated items, you'll need [`navigation.md`](navigation.md).

## See also

- [`blog-post.md`](blog-post.md) — same Tiptap body shape; different tree (posts not docs)
- [`landing-page.md`](landing-page.md) — block-based pages (different surface)
- [`navigation.md`](navigation.md) — docs_sidebar menu (if you've customized it)
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — full `content_*` doc tool list
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
- catalog/CLAUDE.md → "Public API Endpoints" — `/content/docs*` routes
