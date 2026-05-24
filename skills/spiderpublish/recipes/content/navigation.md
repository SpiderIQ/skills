# recipes/content/navigation

Edit the header / footer / docs-sidebar menus in place. PUT semantics — pass the full menu, server replaces in-place. Items can nest.

## When to use

- A tenant wants to add a new page to their site's main nav (`Home / Features / Pricing / Blog` → add `Customers`).
- You're restructuring the footer (split into "Product / Company / Resources" columns).
- You're hand-curating the docs sidebar (instead of auto-generated from the docs tree).
- You're adding external links (to GitHub, the public docs site, a third-party tool).

The three menu locations are fixed: `header`, `footer`, `docs_sidebar`. Custom locations (e.g. `mobile_drawer`) need theme template changes — they're not configurable via this MCP tool.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Target pages / posts exist.** Items reference URLs (`/about`, `/blog`, `https://github.com/...`). If you point to a page that doesn't exist, the nav still renders the link — clicking 404s.
3. **Theme template uses the menu.** Default theme's `sections/header.liquid` renders the `header` nav. If you've customized + dropped the `{% for item in navigation.header.items %}` block, the menu data persists but nothing renders.

## The 2-call path

```
1. content_get_navigation({ location })   — see current items
2. content_update_navigation({ location, items: [...] })   — replace in place (PUT semantics)
```

No deploy step needed for nav-only changes — the renderer reads navigation live from the API per request. (Same as posts.) Deploy only if you changed templates.

### 1. Get the current menu

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

### 2. Update the menu (full replace)

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

**PUT semantics:** `content_update_navigation` REPLACES the menu wholesale. Pass the full `items[]` array — anything you omit is gone. If you only want to add one item: get the current, append, update.

No dry_run/confirm gate by default — `content_update_navigation` mutates immediately.

## Common patterns

### Add one item without touching the rest

```
const current = await content_get_navigation({ location: "header" });
const updated = {
  ...current,
  items: [...current.items, { label: "Customers", url: "/customers" }]
};
await content_update_navigation({ location: "header", items: updated.items });
```

### Multi-column footer

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

### External link

```
{ label: "GitHub", url: "https://github.com/SpiderIQ/SpiderIQ", target: "_blank" }
```

`target: "_blank"` opens in a new tab. Most themes add `rel="noopener"` automatically.

## Docs sidebar — auto vs hand-curated

By default the `docs_sidebar` is auto-generated from `content_docs_tree()` — the theme's `sections/docs-sidebar.liquid` iterates the tree. If you `content_update_navigation({location: "docs_sidebar", items: [...]})`, the theme can switch to rendering the hand-curated menu instead (depends on the template).

Default theme: uses hand-curated `docs_sidebar` IF it's non-empty; falls back to the tree if empty. Set `items: []` to revert to auto.

## Verify

The new nav is live the moment `content_update_navigation` returns 200 — no deploy. Verify in a browser, or:

```
content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
```

Check `body_text_preview` for the new item labels. Or open the URL and click each new link to confirm they don't 404.

## Anti-patterns

1. **Passing PATCH-style partial updates.** PUT semantics — you replace the full `items[]`. To add one item: read the current, append, send the full list back.
2. **Pointing to a page that doesn't exist.** The nav renders the link; clicking 404s. Check `content_list_pages({status: "published"})` before adding `/foo` to the nav.
3. **Using `location: "<anything>"` other than the three allowed.** 422. The three: `header`, `footer`, `docs_sidebar`. Custom locations need theme template changes — out of scope for this tool.
4. **Forgetting `target: "_blank"` on external links.** Visitors stay on the external site; bad UX. Always pair external URLs with `target: "_blank"`.
5. **Deeply-nested children (3+ levels).** Most themes only render 2 levels (top + children). Three-level nests render as flat children unless your theme has explicit deep-tree support.

## See also

- [`landing-page.md`](landing-page.md) — author the pages your nav points at
- [`blog-post.md`](blog-post.md) — same for blog posts
- [`docs-page.md`](docs-page.md) — note on docs_sidebar auto-tree vs hand-curated
- [`section-override.md`](section-override.md) — customize the header / footer Liquid templates
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — full `content_*` tool list
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
