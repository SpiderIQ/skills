# recipes/marketplace/author-site-template

Publish a curated starter site to the marketplace catalog so other tenants can `content_apply_site_template({slug})` to clone it. Super-admin / marketplace-authoring-brand operation.

## When to use

- You're on the SpiderIQ team curating new starters for the catalog (restaurant, SaaS, agency, lawyer, …).
- You've built a polished example site in the **marketplace authoring tenant** (`cli_spideriq_templates` — the canonical brand for marketplace-authored assets) and want to promote it to the global catalog.
- You're shipping an industry-pack with 3-5 paired starters.

If you want to APPLY an existing template to a tenant → [`../content/apply-site-template.md`](../content/apply-site-template.md). If you want to clone the marketplace authoring tenant's UI patterns into a specific tenant → use that recipe, not this one. If you're authoring a single component (not a whole site) → [`../components/create-component.md`](../components/create-component.md) + [`../components/upload-component-preview.md`](../components/upload-component-preview.md).

## Prerequisites

1. **PAT scope is super_admin OR brand_admin of `cli_spideriq_templates`.** The marketplace authoring tenant is the canonical brand for `is_global: true` assets. Other PATs get 403 on the create-template endpoint.
2. **Source pages exist + are published** in the marketplace authoring tenant. The template clones from THESE.
3. **Preview image ready** — PNG/JPG/WEBP of the rendered site (typically a homepage screenshot or composite). ≤5 MB.
4. **Tenant scope verified** + bound to the authoring tenant. Run `./scripts/verify-tenant-scope.sh`.

## The 5-call path

```
1. (in authoring tenant) build the source pages — landing-page.md / blog-post.md / etc.
2. content_upload_site_template_preview   — upload the preview image to R2
3. (REST) POST /content/site-templates    — create the catalog row              # VERIFY tool name
4. content_get_site_template               — confirm shape
5. (across other tenants) content_apply_site_template — confirms it works end-to-end
```

**Resolved 2026-05-24 — product gap flagged:** the upload-preview MCP tool exists (`content_upload_site_template_preview`), and `next_step` strings in content.ts reference `content_create_site_template` / `content_update_site_template` as if they were registered. They are NOT — the catalog-row CRUD is REST-only via `POST /api/v1/dashboard/projects/{pid}/content/site-templates` and `PATCH .../{slug}` (files: [`app/api/v1/dashboard_site_templates.py:177`](https://github.com/SpiderIQ/SpiderIQ/blob/master/app/api/v1/dashboard_site_templates.py#L177), `:232`). Tracked for an MCP-wrapper PR; the `next_step` strings in content.ts also need updating once the wrappers land.

### Step 1 — build the source pages

In the marketplace authoring tenant (NOT the tenant the template will be applied to), build the pages exactly as you want them to land for downstream tenants:

```
# In cli_spideriq_templates context
content_create_page({ title: "Home", slug: "home", template: "default", blocks: [...] })
content_create_page({ title: "Menu", slug: "menu", template: "default", blocks: [...] })
content_create_page({ title: "About", slug: "about", ... })
content_create_page({ title: "Reservations", slug: "reservations", ... })
content_create_page({ title: "Contact", slug: "contact", ... })

# Publish all of them
content_publish_page({ page_id: ..., confirm_token: ... }) for each

# Set the nav menus
content_update_navigation({ location: "header", items: [...] })
content_update_navigation({ location: "footer", items: [...] })

# Set the theme settings (the whitelisted keys that get copied)
content_update_settings({
  settings: {
    primary_color:    "#8B4513",
    body_text_color:  "#1c1917",
    site_name:        "Trattoria Italiana",      # used as default; downstream tenants override
    logo_url:         "https://media.spideriq.ai/templates/trattoria/logo.svg"
  }
})
```

The source tenant's current state at template-publish-time is what gets cloned. Iterate until the source site is the canonical example.

### Step 2 — upload the preview image

```
content_upload_site_template_preview({
  slug:       "trattoria-italiana",                  # used as both the R2 key stem AND the path segment
  local_path: "./templates/trattoria-italiana/preview.png"
})
// → { url: "https://media.cdn.spideriq.ai/templates/trattoria-italiana.png", key, size_bytes, content_type }
```

5 MB cap; PNG/JPG/JPEG/GIF/WEBP allowed. The preview image is what shows in the marketplace browser card.

**Important:** this tool only uploads to R2 — it does NOT PATCH the catalog row. You'll set `preview_thumbnail_url` to the returned URL in the next step.

### Step 3 — create the catalog row

REST only as of 2026-05-24. No MCP wrapper for create/update; use the REST path below. (Upload-preview IS exposed via `content_upload_site_template_preview`.)

```bash
curl -X POST "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/site-templates" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "slug":                    "trattoria-italiana",
    "name":                    "Trattoria Italiana — restaurant starter",
    "description":             "Menu / About / Contact / Reservations starter with rustic warm palette. Mobile-first.",
    "industry":                "restaurant",
    "use_case":                "small-business",
    "tags":                    ["restaurant", "italian", "small-business", "warm-palette"],
    "preview_url":             "https://acme-templates.spideriq.ai/",
    "preview_thumbnail_url":   "https://media.cdn.spideriq.ai/templates/trattoria-italiana.png",
    "is_featured":             false,
    "source_page_slugs":       ["home", "menu", "about", "reservations", "contact"],
    "source_nav_locations":    ["header", "footer"],
    "source_settings_keys":    ["primary_color", "body_text_color", "site_name", "logo_url"],
    "source_component_slugs":  [],
    "agent_meta": {
      "mood":           "warm",
      "palette":        "earth-tone",
      "brand_fit_tags": ["small-business", "hospitality"],
      "scene_type":     "restaurant"
    }
  }'
# → 201 Created { template_id, slug, ... }
```

| Field | Notes |
|---|---|
| `slug` | URL-safe identifier. Stable handle for `content_apply_site_template`. |
| `name` | Display name in marketplace browsers. |
| `description` | Markdown-allowed. Shown on the catalog card. |
| `industry` / `use_case` | Filter dimensions for `content_list_site_templates`. |
| `tags[]` | Free-form. Surfaces in `content_list_site_templates({ tag })`. |
| `preview_url` | Live URL of the actual rendered example (the authoring tenant's primary domain). |
| `preview_thumbnail_url` | The image from Step 2. |
| `source_page_slugs[]` | The pages in the authoring tenant that get cloned on apply. ORDER matters — first slug is typically `home`. |
| `source_nav_locations[]` | Which nav menus get copied. Typically `header` + `footer`; `docs_sidebar` for doc-shaped templates. |
| `source_settings_keys[]` | Whitelisted theme keys that copy. **Never include secrets** (analytics_id, webhook URLs, encrypted keys). |
| `source_component_slugs[]` | If the template depends on tenant-authored components (vs `is_global` ones), list them so the apply tool can clone those too. Usually empty. |
| `agent_meta` | AI-discovery axes (mood / palette / brand_fit / scene_type) — for `marketplace_search` semantic queries. See catalog/CLAUDE.md → marketplace_taxonomy. |
| `is_featured` | Promote in the catalog. Curated decision; not for self-promotion. |

As of 2026-05-24, the REST create endpoint is NOT Phase 11+12 gated — single POST creates the catalog row. This is intentional for super_admin authoring flows (low-frequency, high-trust). If the gate is added later, the same recipe applies with a `dry_run=true` → `confirm_token` round-trip prepended.

### Step 4 — confirm the catalog row landed

```
content_get_site_template({ slug: "trattoria-italiana" })
// → full record including the source_page_blocks (what visitors will see on apply)
```

Read it back. Confirm `preview_thumbnail_url` is the right R2 URL, `source_page_slugs` lists what you expect.

### Step 5 — apply to a test tenant (end-to-end smoke)

In a test tenant (NOT the authoring tenant):

```
# Apply
content_apply_site_template({ slug: "trattoria-italiana", dry_run: true })
content_apply_site_template({ slug: "trattoria-italiana", confirm_token })

# Publish + deploy
# (per the standard publish + deploy flow)

# Visual-check the home page
content_visual_check({ page_url: "https://<test-tenant>/", viewport: "desktop" })
```

If the test tenant's deployed version looks like your authoring tenant's source pages → success. If not, debug + iterate on the source pages, then re-publish the template (PATCH the catalog row to point at the latest source state).

## Update an existing template

Templates aren't versioned by default — re-running create with the same slug 409s. To update:

```bash
# PATCH the catalog row
curl -X PATCH "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/site-templates/<slug>" \
  -H "Authorization: Bearer ..." \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Updated copy...",
    "is_featured": true
  }'
```

If you changed the SOURCE PAGES in the authoring tenant, downstream tenants who APPLIED earlier WON'T auto-update — the apply was a one-time clone. To roll forward, downstream tenants need to re-apply (which creates NEW drafts; the old applied pages are preserved separately).

## Versioning approach (for major changes)

For breaking changes to the template shape:

1. Don't update the existing slug.
2. Create a new slug (e.g. `trattoria-italiana-v2`).
3. Mark the old slug `is_featured: false` + add a description note ("Superseded by trattoria-italiana-v2").
4. Promote the new slug in `is_featured`.

This way, downstream tenants who applied v1 are stable; new tenants see v2.

## Anti-patterns

1. **Authoring directly in a customer's tenant + promoting from there.** Settings + content bleeds across tenants. Always author in `cli_spideriq_templates` (the canonical marketplace authoring brand).
2. **Including secrets in `source_settings_keys`.** `analytics_id`, `webhook_*`, encrypted keys → leak to every downstream tenant. Only include public + brand keys.
3. **Listing 30+ pages in `source_page_slugs`.** Apply becomes a heavy mutation (30 page creates + nav updates + settings merge). Aim for the minimum viable starter — 5-10 pages.
4. **Forgetting to set `agent_meta`.** `marketplace_search` is the high-leverage discovery surface; without `mood` / `palette` / `scene_type`, agents can't find your template semantically. ALWAYS set it.
5. **Skipping the end-to-end smoke (Step 5).** Bugs in the source pages bake into every apply. Test in a throwaway tenant before promoting.
6. **Using `is_featured: true` for your own template right after publishing.** Curation decision — leave to the SpiderIQ team to promote based on quality + downstream traction.

## See also

- [`../content/apply-site-template.md`](../content/apply-site-template.md) — the downstream apply flow (what the catalog row enables)
- [`../components/create-component.md`](../components/create-component.md) — author a component (different shape — components are slot-in pieces; site templates are whole sites)
- [`../components/upload-component-preview.md`](../components/upload-component-preview.md) — sibling pattern for component card art
- [`author-bg-video.md`](author-bg-video.md) — author a bg-video catalog row (parallel marketplace asset type)
- [`suggest-agent-meta.md`](suggest-agent-meta.md) — LLM-suggest the agent_meta axes
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*_site_template` tool catalog
- catalog/CLAUDE.md → "Marketplace Admin Slice 1" — backend internals
