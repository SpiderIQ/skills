# recipes/content/apply-site-template

Clone a curated starter site (the marketplace's "site template" assets) into the current tenant — N pages + nav menus + whitelisted theme settings, all as drafts. Phase 11+12 gated.

## When to use

- A tenant just got provisioned and you want them to have something more interesting than a blank "Home" page on day 1.
- The client picked a template from the marketplace gallery and you're materializing it.
- You're A/B-testing different starter sites without rebuilding from blocks each time.
- A new agency client wants a "lawyer" / "restaurant" / "SaaS" starter that matches their vertical.

If you want to author your OWN site template to publish to the marketplace → [`../marketplace/author-site-template.md`](../marketplace/author-site-template.md). If you want to swap the visual theme of an existing site → [`apply-theme.md`](apply-theme.md). If you want a single section, not a whole site → use `page_insert_section` ([`../marketplace/browse-cro-components.md`](../marketplace/browse-cro-components.md)).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Target tenant has minimal existing content.** Apply-site-template doesn't OVERWRITE existing pages — it ADDS new drafts. If the tenant already has 50 published pages, you'll end up with 50 + N pages. Best on fresh or near-fresh tenants.
3. **Template slug known.** Discover with `content_list_site_templates` (filters: `industry`, `use_case`, `tag`, `is_featured`).

## The 4-call path

```
1. content_list_site_templates           — browse the catalog
2. content_get_site_template             — inspect what's about to land
3. content_apply_site_template            — dry_run + confirm
4. content_publish_page / content_deploy_site — review + publish + deploy
```

### 1. Browse

```
content_list_site_templates({
  industry:    "restaurant",      # filter by vertical
  use_case:    "small-business",
  is_featured: true               # surface curated
})
// → [
//   {
//     slug: "trattoria-italiana",
//     name: "Trattoria Italiana — restaurant starter",
//     industry: "restaurant",
//     use_case: "small-business",
//     description: "Menu / About / Contact / Reservations starter with rustic warm palette",
//     preview_url: "https://media.spideriq.ai/site-templates/trattoria/preview.png",
//     source_page_slugs: ["home", "menu", "about", "reservations", "contact"],
//     source_nav_locations: ["header", "footer"],
//     source_settings_keys: ["primary_color", "body_text_color", "site_name", "logo_url"],
//     agent_meta: { mood: "warm", palette: "earth-tone", scene_type: "restaurant" }
//   },
//   ...
// ]
```

Each entry tells you what pages will land, which menus will be set, which settings get copied. Read `agent_meta` for AI-discoverability tags.

### 2. Inspect

```
content_get_site_template({ slug: "trattoria-italiana" })
// → { ... full record including source_page_blocks for each page ... }
```

`source_page_blocks` is the actual block structure that will materialize into each page. Read it to know what components/blocks the visitor will see. Useful if you want to confirm fit before applying.

### 3. Apply (dry_run + confirm)

```
# Step 3a — preview
content_apply_site_template({ slug: "trattoria-italiana", dry_run: true })
// → {
//   dry_run: true,
//   preview: {
//     pages_to_create:        ["home", "menu", "about", "reservations", "contact"],
//     pages_already_exist:    [],    # warns if any of the target slugs conflict
//     settings_keys_to_apply: ["primary_color", "body_text_color", "site_name", "logo_url"],
//     nav_locations_to_set:   ["header", "footer"]
//   },
//   confirm_token: "cft_...",
//   expires_at: "..."
// }
```

Read `pages_already_exist` carefully. If any target slug conflicts with an existing page, the existing one is preserved and the template's version is SKIPPED. Move/rename existing pages first if you want the template to land.

```
# Step 3b — confirm
content_apply_site_template({
  slug: "trattoria-italiana",
  confirm_token: "cft_..."
})
// → {
//   pages_created:    [{ id: "page_...", slug: "home", status: "draft" }, ...],
//   nav_updated:      ["header", "footer"],
//   settings_applied: { primary_color: "#8B4513", ... },
//   template_applied_count: 142     # bumps for the leaderboard
// }
```

All new pages land at `status: draft`. The nav is REPLACED for the locations the template names (header + footer); existing menus at other locations (docs_sidebar) untouched. Settings keys are MERGED — only the whitelisted keys from the template are written; other tenant settings preserved.

### 4. Review + publish + deploy

```
# Review each draft
content_list_pages({ status: "draft", limit: 50 })
content_get_page({ page_id: "page_...", audit_level: "warnings" })

# Customize before publish (typical: replace template's placeholder copy with real text)
content_update_page({ page_id, blocks: [...] })

# Publish each (safe-default dry_run=true)
content_publish_page({ page_id: "page_..." })
content_publish_page({ page_id, confirm_token })

# Deploy
content_deploy_readiness()
content_deploy_site_preview()
content_deploy_site_production({ confirm_token })
```

## What the template actually copies

| Copied | Not copied |
|---|---|
| Source pages → drafts in target tenant | Posts, docs, redirects, custom domains |
| Whitelisted theme settings (primary_color, body_text_color, site_name, logo_url, …) | All other settings (analytics_id, webhook_*, encrypted secrets) |
| Nav menus for the template's declared locations | Other nav locations (docs_sidebar usually) |
| Image URLs in blocks (still pointing at SpiderMedia CDN) | Images themselves (not re-uploaded; references shared with source tenant) |

Whitelist semantics protect tenant secrets — even if the source template had `analytics_id`, it's NOT copied.

## Iterate — apply multiple templates

You can apply MULTIPLE templates to one tenant if they don't conflict on page slugs:

```
content_apply_site_template({ slug: "trattoria-italiana", confirm_token: "..." })   # adds home, menu, about, reservations, contact
content_apply_site_template({ slug: "blog-starter", confirm_token: "..." })          # adds blog landing + first 3 posts (uses different slugs)
```

If two templates declare the same slug (`home`), the second one's `home` will land as `pages_already_exist: ["home"]` and be skipped. Resolve by renaming the first one's `home` to something else BEFORE applying the second.

## Verify

After deploy:

```
content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
# Check screenshot matches the template's preview_url eyeballed earlier.
```

## Rollback

The applied template is "just" a bulk page-create + nav-update + settings-merge. To roll back:

- Delete the created pages: `content_delete_page` (safe-default dry_run=true).
- Reset nav: `content_update_navigation({ location, items: [...previous] })`.
- Reset settings: `content_update_settings({ settings: { ...previous } })`.

There's no single "rollback this template apply" tool today — each side-effect rolls back separately. For destructive rollback on a production tenant, prefer "branch the tenant before apply" via `content_export_page` snapshots.

## Anti-patterns

1. **Applying a site template to a tenant with 50+ existing published pages.** The drafts land alongside, the nav gets replaced. Visitors see a confusing mix. Apply on FRESH tenants only, or move existing pages aside first.
2. **Publishing drafts without reviewing them.** Templates ship with placeholder copy ("Lorem ipsum welcome to our restaurant"). Review + customize before publish.
3. **Forgetting to deploy after publishing the drafts.** Pages are published in STORE but the SERVE-layer Liquid renderer needs `content_deploy_site_production` to push to the edge. Until then, visitors hit the previous deploy's content.
4. **Re-applying the same template twice expecting it to update existing pages.** It won't — slugs conflict, both runs skip. To update, edit the pages directly (`content_update_page`).
5. **Skipping `content_get_site_template` and applying based on the name alone.** Templates have very different shapes — restaurant vs SaaS vs blog. Inspect first to avoid 5 pages of confusing content.

## See also

- [`landing-page.md`](landing-page.md) — author individual pages from scratch (alternative path)
- [`apply-theme.md`](apply-theme.md) — change visual theme only (no content changes)
- [`../marketplace/author-site-template.md`](../marketplace/author-site-template.md) — author your own site template (super_admin)
- [`../marketplace/browse-cro-components.md`](../marketplace/browse-cro-components.md) — add single CRO components on top of an applied template
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — gate flavour (apply defaults to dry_run-on per the Phase 11+12 safe-default for destructive ops)
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*_site_template` tool catalog
