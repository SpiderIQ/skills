# Templates & deploy — themes, two-phase deploy, rollback, preview

Theme/template operations go through `/api/v1/dashboard/templates/...` and the deploy pipeline
through `/api/v1/dashboard/content/deploy...` (Bearer PAT). The full two-phase
`dry_run → confirm_token` gate and the five-lock tenant defense are documented once in
[`deploy-protocol.md`](deploy-protocol.md) — read it before any production deploy. Always run
`content_deploy_readiness` first (see [`audit.md`](audit.md)).

**Read when:** applying a theme, applying a curated starter site, previewing a deploy without
going live, or rolling back a bad deploy.


---

## Apply Theme

Apply a pre-built theme to a tenant's site — copies all theme templates (layout, sections, snippets) to the tenant's per-tenant KV. Site visually changes after deploy. Phase 11+12 gated (defaults to dry_run=true).

### When to use

- A tenant is on the default starter theme and wants to switch to a curated alternative (`vayapin`, `agency-bold`, `editorial`, etc. — see `template_list_themes()` for the live catalog).
- You've authored a new theme in `apps/liquid-renderer/themes/<name>/` and want to apply it to a tenant for testing.
- You're rolling out a brand refresh and need to swap themes site-wide.

If you only want to **override one section** (header, footer) without swapping the whole theme → [`section-override.md`](content.md#section-override). If you want a different *layout chrome* (header + footer present? edge-to-edge main?) without a theme swap → use `content_apply_layout_preset({ preset: "blank" })` — see [`section-override.md`](content.md#layout-presets).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You know which theme.** Call `template_list_themes()` to see the catalog. Theme names are slugs (`default`, `vayapin`, …).
3. **Backups of any custom templates.** `template_apply_theme` OVERWRITES every template path the new theme ships. If you've customized `layout/theme.liquid` or any `sections/*.liquid` and want to keep those overrides: export them first (`template_list()` + `template_get({path})`), apply the theme, then re-apply your overrides via `template_upsert`.

### The 4-call path

```
1. template_list_themes              — see available themes
2. template_apply_theme              — dry_run by default; returns preview + confirm_token
3. template_apply_theme(confirm_token: ...)  — actually apply
4. content_deploy_site_production    — push the new templates to the edge
```

Plus a visual-check at the end.

#### 1. List themes

```
template_list_themes()
// → [
//   { name: "default",   description: "Standard SaaS chrome — header, hero, features, footer", templates_count: 29 },
//   { name: "vayapin",   description: "Restaurant industry — bg-video hero, big-photo sections", templates_count: 35 },
//   { name: "editorial", description: "Magazine / law firm — serif headings, monochrome", templates_count: 27 }
// ]
```

Pick by name. If the tenant has a specific industry-shaped theme they want, grep by description. If you want to see what files a theme ships, `template_list({theme: "<name>"})` returns the file paths.

#### 2. Preview (dry_run defaults to true)

```
template_apply_theme({ theme: "vayapin" })
// → {
//     dry_run: true,
//     preview: {
//       theme: "vayapin",
//       templates_to_write: ["layout/theme.liquid", "sections/header.liquid", ...],
//       templates_to_overwrite: ["sections/header.liquid"],   // existing tenant overrides
//       templates_to_create:    ["sections/restaurant-hero.liquid", ...]
//     },
//     confirm_token: "cft_...",
//     expires_at: "2026-05-24T...",
//     snapshot_hash: "sha256:..."
//   }
```

**Read `templates_to_overwrite` carefully.** Anything you customized that's about to be reset shows up here. If you want to preserve those overrides:

1. `template_get({path: "sections/header.liquid"})` — get the current customization
2. Save the result somewhere (a file, a scratchpad)
3. Apply the theme (step 3)
4. `template_upsert({path: "sections/header.liquid", content: <saved>, theme: "vayapin"})` — re-apply your override after the new theme is in place

This is the "preserve customizations across a theme swap" recipe; the gate gives you the heads-up via `templates_to_overwrite`.

#### 3. Confirm + apply

```
template_apply_theme({ theme: "vayapin", confirm_token: "cft_..." })
// → { applied: true, theme: "vayapin", templates_written: 35, version_id: 12 }
```

The new theme's templates are now in the tenant's per-tenant KV. **The visible site has NOT changed yet** — the renderer reads templates from KV at deploy time, not at request time (templates are cached). Step 4 pushes the change live.

#### 4. Deploy

```
content_deploy_readiness()
// → { ready: true, ... }

content_deploy_site_preview()
// → { preview_url: "https://preview-XXX.sites.spideriq.ai", confirm_token: "cft_...", ... }
```

Eyeball `preview_url` — the new theme is rendering against the tenant's existing content (settings, pages, posts). If anything looks wrong, you can re-apply your saved overrides BEFORE confirming production.

```
content_deploy_site_production({ confirm_token: "cft_..." })
// → { status: "live", version_id: 49 }
```

Site is live in ~2-5s on the primary domain.

### Verify

```
content_visual_check({
  page_url: "https://<tenant>/",
  viewport: "desktop"
})
```

Check:
- `screenshot_url` shows the new theme's visual identity.
- `body_text_preview` still contains your home page's content (the theme is just the rendering shell).
- `console_errors` is empty.

If the theme uses Tier 3 components (CDN dependencies like GSAP, Chart.js), spot-check a page that uses them — the renderer's hydration runner needs the deps to resolve before the component animates / renders.

### Roll back

```
# Option A — re-apply the previous theme (same flow)
template_apply_theme({ theme: "default" })
template_apply_theme({ theme: "default", confirm_token: "cft_..." })
content_deploy_site_production({ confirm_token: "cft_..." })

# Option B — restore a specific deploy version
# (no first-party MCP yet; use the dashboard's deploy history or REST)
```

The theme swap is "just" a bulk `template_upsert` of every file the theme ships. Rolling back is a re-apply of the previous theme + deploy. Tenant content (pages, posts, components) is unaffected by theme swaps — only templates change.

### Anti-patterns

1. **Skipping the dry_run.** `template_apply_theme` defaults to `dry_run: true` for a reason — `templates_to_overwrite` tells you what customizations you're about to lose. Read it.
2. **Forgetting to deploy after apply.** The KV write doesn't push to the edge. Run `content_deploy_site_production` after every `template_apply_theme(confirm_token)`.
3. **Theme-swapping a high-traffic site mid-day.** Even with 2-5s deploy, the cache invalidation can produce a brief blank-page window. Schedule for off-hours, OR use `content_deploy_site_preview` to eyeball and warm the cache first.
4. **Assuming `template_apply_theme` migrates content too.** It only writes templates (Liquid files). Pages, posts, settings, navigation are untouched. If you also want to apply a curated CONTENT set, that's `content_apply_site_template` — different tool, different gate (also dry_run-default).
5. **Customizing templates AFTER `template_apply_theme` without re-running the dry_run.** Every theme apply is a snapshot of the source theme — if you customize, then later re-apply (or apply a different theme), your customizations will be overwritten. Keep customizations in a separate scratchpad / repo, and re-apply via `template_upsert` after every theme swap.

### See also

- [`section-override.md`](content.md#section-override) — override one section without a full theme swap
- [`apply-site-template.md`](#) — apply a curated *content* set (pages + components + settings) — queued v0.4.0
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the two-phase deploy after apply
- [`../reference/tool-surface.md`](tool-surface.md) — full `template_*` tool catalog
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth
- catalog/CLAUDE.md → "Liquid Renderer Worker" — per-tenant KV mechanics


---

## Apply Site Template

Clone a curated starter site (the marketplace's "site template" assets) into the current tenant — N pages + nav menus + whitelisted theme settings, all as drafts. Phase 11+12 gated.

### When to use

- A tenant just got provisioned and you want them to have something more interesting than a blank "Home" page on day 1.
- The client picked a template from the marketplace gallery and you're materializing it.
- You're A/B-testing different starter sites without rebuilding from blocks each time.
- A new agency client wants a "lawyer" / "restaurant" / "SaaS" starter that matches their vertical.

If you want to author your OWN site template to publish to the marketplace → [`../marketplace/author-site-template.md`](marketplace.md#author-site-template). If you want to swap the visual theme of an existing site → [`apply-theme.md`](templates-deploy.md#apply-theme). If you want a single section, not a whole site → use `page_insert_section` ([`../marketplace/browse-cro-components.md`](marketplace.md#browse-cro-components)).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Target tenant has minimal existing content.** Apply-site-template doesn't OVERWRITE existing pages — it ADDS new drafts. If the tenant already has 50 published pages, you'll end up with 50 + N pages. Best on fresh or near-fresh tenants.
3. **Template slug known.** Discover with `content_list_site_templates` (filters: `industry`, `use_case`, `tag`, `is_featured`).

### The 4-call path

```
1. content_list_site_templates           — browse the catalog
2. content_get_site_template             — inspect what's about to land
3. content_apply_site_template            — dry_run + confirm
4. content_publish_page / content_deploy_site — review + publish + deploy
```

#### 1. Browse

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

#### 2. Inspect

```
content_get_site_template({ slug: "trattoria-italiana" })
// → { ... full record including source_page_blocks for each page ... }
```

`source_page_blocks` is the actual block structure that will materialize into each page. Read it to know what components/blocks the visitor will see. Useful if you want to confirm fit before applying.

#### 3. Apply (dry_run + confirm)

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

#### 4. Review + publish + deploy

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

### What the template actually copies

| Copied | Not copied |
|---|---|
| Source pages → drafts in target tenant | Posts, docs, redirects, custom domains |
| Whitelisted theme settings (primary_color, body_text_color, site_name, logo_url, …) | All other settings (analytics_id, webhook_*, encrypted secrets) |
| Nav menus for the template's declared locations | Other nav locations (docs_sidebar usually) |
| Image URLs in blocks (still pointing at SpiderMedia CDN) | Images themselves (not re-uploaded; references shared with source tenant) |

Whitelist semantics protect tenant secrets — even if the source template had `analytics_id`, it's NOT copied.

### Iterate — apply multiple templates

You can apply MULTIPLE templates to one tenant if they don't conflict on page slugs:

```
content_apply_site_template({ slug: "trattoria-italiana", confirm_token: "..." })   # adds home, menu, about, reservations, contact
content_apply_site_template({ slug: "blog-starter", confirm_token: "..." })          # adds blog landing + first 3 posts (uses different slugs)
```

If two templates declare the same slug (`home`), the second one's `home` will land as `pages_already_exist: ["home"]` and be skipped. Resolve by renaming the first one's `home` to something else BEFORE applying the second.

### Verify

After deploy:

```
content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
# Check screenshot matches the template's preview_url eyeballed earlier.
```

### Rollback

The applied template is "just" a bulk page-create + nav-update + settings-merge. To roll back:

- Delete the created pages: `content_delete_page` (safe-default dry_run=true).
- Reset nav: `content_update_navigation({ location, items: [...previous] })`.
- Reset settings: `content_update_settings({ settings: { ...previous } })`.

There's no single "rollback this template apply" tool today — each side-effect rolls back separately. For destructive rollback on a production tenant, prefer "branch the tenant before apply" via `content_export_page` snapshots.

### Anti-patterns

1. **Applying a site template to a tenant with 50+ existing published pages.** The drafts land alongside, the nav gets replaced. Visitors see a confusing mix. Apply on FRESH tenants only, or move existing pages aside first.
2. **Publishing drafts without reviewing them.** Templates ship with placeholder copy ("Lorem ipsum welcome to our restaurant"). Review + customize before publish.
3. **Forgetting to deploy after publishing the drafts.** Pages are published in STORE but the SERVE-layer Liquid renderer needs `content_deploy_site_production` to push to the edge. Until then, visitors hit the previous deploy's content.
4. **Re-applying the same template twice expecting it to update existing pages.** It won't — slugs conflict, both runs skip. To update, edit the pages directly (`content_update_page`).
5. **Skipping `content_get_site_template` and applying based on the name alone.** Templates have very different shapes — restaurant vs SaaS vs blog. Inspect first to avoid 5 pages of confusing content.

### See also

- [`landing-page.md`](content.md#landing-page) — author individual pages from scratch (alternative path)
- [`apply-theme.md`](templates-deploy.md#apply-theme) — change visual theme only (no content changes)
- [`../marketplace/author-site-template.md`](marketplace.md#author-site-template) — author your own site template (super_admin)
- [`../marketplace/browse-cro-components.md`](marketplace.md#browse-cro-components) — add single CRO components on top of an applied template
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — gate flavour (apply defaults to dry_run-on per the Phase 11+12 safe-default for destructive ops)
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*_site_template` tool catalog

---

## Start from a Page Template (adapt, don't generate)

A **page template** is a single-page sibling of the site template above — one
ready-made page (opt-in, thank-you, VSL, webinar, sales, pricing, coming-soon,
404) you **clone and adapt**, instead of authoring Liquid blocks from scratch.

> **This is the DEFAULT for any landing/opt-in/thank-you/VSL request.** An LLM
> adapts a working, structured page (swap copy, images, colors) far more
> reliably than it generates one blind. Reach for page templates FIRST; fall
> back to `createPage` ([`content.md#landing-page`](content.md#landing-page))
> only when nothing in the catalog fits.

Same backing table + apply machinery as site templates — a page template is just
a site template with `is_single_page=true` and exactly ONE source page. So it
clones ONE draft page (no nav replace, no multi-page sprawl).

### When to use vs. the alternatives

| You want… | Use |
|---|---|
| A whole multi-page starter site | `listSiteTemplates`→`applySiteTemplate` (above) |
| **One ready-made page to adapt** | **`listPageTemplates`→`applyPageTemplate` (this recipe)** |
| A page built block-by-block from scratch | `createPage` + `insertSection` |
| One section dropped onto an existing page | `listMarketplaceComponents`→`insertSection` |

### The path

```
1. content_list_page_templates          — browse the single-page catalog
2. content_get_page_template            — inspect the one page about to land
3. content_apply_page_template          — dry_run + confirm (clones 1 draft page)
4. content_update_page                  — ADAPT: replace placeholder copy/images/colors
5. content_publish_page → deploy        — publish the draft, then deploy to the edge
```

#### 1. Browse

```
content_list_page_templates({
  use_case: "opt-in",        # opt-in | thank-you | vsl | webinar | sales | pricing | coming-soon | 404
  is_featured: true
})
// → [ { slug: "opt-in-minimal", name: "Opt-In — Minimal",
//       use_case: "opt-in", source_page_slugs: ["opt-in"],   # exactly ONE
//       preview_thumbnail_url: "https://media.spideriq.ai/...", agent_meta: {...} }, ... ]
```

This is the same `/content/site-templates` catalog narrowed to
`is_single_page=true` — every row has exactly one `source_page_slugs` entry.

#### 2. Inspect

```
content_get_page_template({ slug: "opt-in-minimal" })
// → full record incl. the single page's block structure — confirm fit before applying.
```

#### 3. Apply (dry_run + confirm)

```
content_apply_page_template({ slug: "opt-in-minimal", dry_run: true })
// → { dry_run: true, preview: { pages_to_create: ["opt-in"] }, confirm_token: "cft_...", expires_at: "..." }

content_apply_page_template({ slug: "opt-in-minimal", confirm_token: "cft_..." })
// → { pages_created: [{ id: "page_...", slug: "opt-in", status: "draft" }] }
```

The cloned page lands at `status: draft`. If the slug conflicts with an existing
page it's reported in `pages_already_exist` and skipped — rename the existing one
first.

#### 4. ADAPT (the whole point)

```
content_get_page({ page_id: "page_...", audit_level: "warnings" })
content_update_page({ page_id, blocks: [ ...the template's blocks with YOUR copy/images... ] })
```

Replace the template's placeholder headline, body, CTA target, and images with
the brand's real content. Keep the structure; change the words.

#### 5. Publish + deploy

```
content_publish_page({ page_id: "page_..." })            # dry_run → confirm
content_deploy_site_preview() → content_deploy_site_production({ confirm_token })
content_visual_check({ page_url: "https://<tenant>/opt-in", viewport: "desktop" })   # Agent Trust 5.1
```

### Anti-patterns

1. **Generating a landing page from scratch when a template fits.** Slower and
   far more error-prone than cloning + adapting. Check `listPageTemplates` first.
2. **Publishing the clone without adapting it.** It ships with placeholder copy.
   Always `content_update_page` before publish.
3. **Forgetting to deploy.** Publish flips the STORE flag; the live site only
   changes on `content_deploy_site_production`.
4. **Treating it as a multi-page apply.** A page template clones exactly ONE
   page — for a whole site use `applySiteTemplate`.

### See also

- [`content.md#landing-page`](content.md#landing-page) — author a page from scratch (only when no template fits)
- [Apply Site Template](#apply-site-template) — the whole-site sibling
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*_page_template` tool catalog


---

## Deploy Preview Only

Push the current STORE state to a **temporary preview URL** (`preview-<token>.sites.spideriq.ai`) without touching production. Use it to eyeball a change before consuming the production confirm_token.

### When to use

- About to deploy a high-risk change (theme swap, mass restore, new template) — preview first.
- Sharing a "before you confirm" URL with the client for sign-off.
- CI pipeline: build PR → preview deploy → run smoke tests → only then promote to production.
- Pattern: "I want to see what visitors WILL see, without them seeing it yet."

### The one call

```
content_deploy_site_preview()
# → {
#     preview_url:    "https://preview-cft01HXX.sites.spideriq.ai",
#     confirm_token:  "cft_01HXXXXXXXXXXXXXXXXX",
#     expires_at:     "2026-05-24T14:35:00Z",        # 5 minutes from now
#     preview: {
#       pages: 12,
#       components: 24,
#       settings_diff: { changed_keys: [...] },
#       templates_diff: { changed_files: [...] }
#     },
#     snapshot_hash:  "sha256:..."
#   }
```

Phase 11+12 Stage 2 — issues a preview URL + confirm_token without deploying. The preview URL points at a one-off Worker that serves the snapshot you'd land in production.

### Two ways to consume the preview

#### Option A — Promote to production

If the preview looks right, consume the token:

```
content_deploy_site_production({
  confirm_token: "cft_01HXXXXXXXXXXXXXXXXX"
})
# → { status: "live", version_id: 49, deployed_at: "..." }
```

That's the canonical Phase 11+12 happy path — preview → confirm → live.

#### Option B — Discard

Let the token expire (5 minutes — the deploy pipeline TTL is short). The preview URL stays accessible for the duration of the cache (~30 min), but no production change happens. Useful when:

- The preview revealed a bug; fix it in STORE, then `content_deploy_site_preview` again for a fresh token.
- You're sharing the preview link with the client and waiting for sign-off; if sign-off comes after 5 min, re-run preview for a fresh token before promoting.

### Steps — typical "share for sign-off" flow

```
1. (make whatever STORE edits — pages, components, settings)
2. content_deploy_readiness()                       — confirm no blocking issues
3. content_deploy_site_preview()                     — get preview_url + confirm_token
4. (send preview_url to the client / stakeholder)
5. (wait for sign-off)
6. content_deploy_site_preview()                     — fresh token if the original expired
7. content_deploy_site_production({ confirm_token })  — go live
8. content_visual_check({ page_url: "<production-url>" })
                                                     — verify the production deploy
```

### Steps — typical CI flow

```bash
# After PR merge → trigger CI build → for each tenant:
PREVIEW=$(spideriq content deploy preview --json | jq -r '.preview_url')
TOKEN=$(spideriq content deploy preview --json | jq -r '.confirm_token')

# Run smoke tests against the preview
spideriq content visual-check --page-url "$PREVIEW/landing" --viewport desktop || exit 1
spideriq content visual-check --page-url "$PREVIEW/landing" --viewport mobile  || exit 1

# Promote
spideriq content deploy production --confirm-token "$TOKEN"
```

(`spideriq content deploy preview --json` is the CLI wrapper for `content_deploy_site_preview`.)

### What lands in the preview

Everything in STORE that WOULD land in production:

- Latest published page versions (drafts NOT included unless previously published)
- Latest published component versions
- Current theme tokens + template Liquid files
- Current `content_settings` (SEO defaults, brand colors, analytics tags)
- Current `content_domains` config (but the preview URL is `preview-<token>.sites.spideriq.ai`, NOT the primary domain)

What does NOT differ between preview and production:

- DB rows (both read from the same `content_pages` / `content_components` tables)
- API endpoints (forms POST to the same `/api/v1/booking/<id>/submit`)
- Tenant data (form responses, IDAP records — same tables)

This means a preview deploy showing a form: that form is the real form. Test submissions land in the real responses table. Use [`../booking/test-form-submission.md`](forms-booking.md#test-form-submission)'s `?test=true` discipline.

### Gotchas

- **`expires_at` is 5 minutes** — deploy pipeline TTL is the strictest of the gate flavours. If your sign-off cycle is longer, expect to re-run preview for a fresh token.
- **Preview URL is publicly accessible** — anyone with the URL can hit it. Don't share preview URLs that include sensitive draft copy via email/Slack channels with broad membership.
- **CF cache holds the preview** for ~30 min after first hit. If you re-deploy preview with a different snapshot, the URL changes (new token), so cache doesn't conflict.
- **`content_visual_check` against the preview URL works** — same Playwright sidecar. Use it pre-promote to catch silent-200 failures.
- **`content_deploy_readiness` should still run** — preview deploys can succeed against a tenant with blocking-readiness issues (missing primary domain, etc.); production deploys reject. Don't be surprised when preview works and production rejects.
- **Forms in preview submit to the real flow** — test submissions land in the real responses table. Use a sandbox tenant for high-volume preview testing.
- **Multiple back-to-back previews** = multiple unused tokens. They expire after 5 min; no cleanup needed, but don't be alarmed.

### Verify

```
# After preview deploy
curl -sI "<preview_url>"
# HTTP/2 200
# server: cloudflare

# After promote
content_deploy_status()
# → latest.version_id should be the new production version
#   latest.status should be "live"

content_visual_check({
  page_url: "https://<tenant-domain>/<key-page>",
  viewport: "desktop"
})
# → confirm production now shows what preview showed
```

### Anti-patterns

- **Skipping preview on high-risk deploys** ("I'm sure"). Theme swaps, mass restores, template edits — always preview. The 5 minutes you save by skipping is gone the moment you have to roll back ([`rollback-deploy.md`](templates-deploy.md#rollback-deploy)).
- **Holding a preview token for >5 minutes** and being surprised by 410. The TTL is short by design — fresh-token re-runs are cheap.
- **Sharing preview URLs in public channels** with sensitive draft content. The URL is unauthenticated.
- **Treating preview as "doesn't count."** Form submissions on the preview URL land in REAL responses. IDAP fills, analytics events — all real.
- **Running `content_deploy_site_production` with no prior preview** for a change that touches multiple pages. The legacy `content_deploy_site({ dry_run: true })` also returns a confirm_token, but the preview URL only comes from `content_deploy_site_preview`. Use the split tool when you actually want to look at the preview.
- **Promoting without `content_visual_check` against the preview URL first.** That's the whole point of the preview.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "preview a deploy without going live"
# Top-1 should be: recipes/deploy/deploy-preview-only.md
```

### See also

- [`rollback-deploy.md`](templates-deploy.md#rollback-deploy) — the recovery path when preview didn't catch it
- [`../audit/deploy-readiness.md`](audit.md#deploy-readiness) — pre-deploy checklist; run BEFORE preview
- [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) — verify the preview URL renders correctly
- [`../content/custom-domain.md`](integrations.md#custom-domain) — production URL setup (preview URL is always `*.sites.spideriq.ai`, never the custom domain)
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — full gate semantics + ConfirmTokenError map


---

## Rollback Deploy

A bad deploy hit production and visitors see broken pages. Roll back — **fast, safely, and with an audit trail**. The mechanic is per-page version restore + redeploy; there's no "undo deploy" big red button.

### When to use

- A `content_deploy_site_production` call landed and visitors are reporting broken pages.
- A theme apply pushed the wrong colours / fonts and you need yesterday's look back.
- A migration script touched 20 pages with a typo and you need them all reverted.
- An automation overwrote SEO titles and search rankings are about to drop.

### Honest framing — no single "undo deploy" tool

SpiderPublish doesn't have a `content_rollback_deploy({ to_version_id })` tool. A deploy is a multi-step pipeline (KV write → CF Worker recreate); rolling it back means **restoring the underlying pages + components to their previous versions, then redeploying**. That's three primitives:

| Primitive | What it does |
|---|---|
| `content_list_page_versions({ page_id })` | Find the version BEFORE the bad deploy |
| `content_restore_page_version({ page_id, version_number })` | Bring back that snapshot as a new draft |
| `content_deploy_site_production({ confirm_token })` | Push the restored state live |

For a multi-page rollback, loop over the affected pages.

### Prerequisites

- A PAT scoped to the tenant.
- The deploy timestamp (or `version_id` from `content_deploy_status`) so you know what time the bad deploy happened.
- Optionally: list of pages affected (if it's not "everything").

### Step 1 — Identify the bad deploy

```
content_deploy_status()
# → {
#     latest: { version_id: 48, deployed_at: "2026-05-24T14:32:00Z", status: "live" },
#     history: [
#       { version_id: 47, deployed_at: "2026-05-24T13:01:00Z", status: "superseded" },
#       { version_id: 46, deployed_at: "2026-05-23T09:15:00Z", status: "superseded" },
#       ...
#     ]
#   }
```

If the bad deploy is `48`, you want to land the state from `47` (the previous good deploy).

### Step 2 — Decide the scope

**Option A — Single page is broken:** restore just that page, redeploy.

**Option B — Everything is broken** (theme apply, settings update, mass migration): identify ALL affected pages.

```
content_list_pages({ limit: 500 })
# → for each, content_list_page_versions to see if it was modified in the bad-deploy window
```

The bad-deploy window is `[history[0].deployed_at, latest.deployed_at]`. Any page version landed in that window is suspect.

### Step 3 — Restore each affected page

For one page:

```
# Find the version BEFORE the bad change
content_list_page_versions({ page_id: "<uuid>" })
# → [
#     { version_number: 12, snapshot_created_at: "2026-05-24T14:25:00Z" },   # bad
#     { version_number: 11, snapshot_created_at: "2026-05-23T16:40:00Z" },   # last good
#     ...
#   ]

# Restore (safe-default gated)
content_restore_page_version({ page_id: "<uuid>", version_number: 11 })
# → { dry_run: true, preview: {...}, confirm_token: "cft_..." }

# Confirm
content_restore_page_version({ page_id: "<uuid>", version_number: 11, confirm_token: "cft_..." })
# → restored as draft (new version_number 13 in the audit chain: 11 → 12 → 13)

# Publish so it'll deploy
content_publish_page({ page_id: "<uuid>" })
# → safe-default gated; preview + confirm
```

For a multi-page rollback, loop:

```python
for page_id in affected_pages:
    versions = content_list_page_versions(page_id)
    # find last version with snapshot_created_at < bad_deploy_at
    target = next(v for v in versions if v.snapshot_created_at < bad_deploy_at)

    # dry-run
    preview = content_restore_page_version(page_id, target.version_number)
    # confirm
    content_restore_page_version(page_id, target.version_number, confirm_token=preview.confirm_token)
    # publish (also gated)
    publish_preview = content_publish_page(page_id)
    content_publish_page(page_id, confirm_token=publish_preview.confirm_token)
```

### Step 4 — Theme / settings rollback (if applicable)

If the bad deploy included a theme change or `content_update_settings`:

```
# For theme: re-apply the previous theme by slug
template_apply_theme({ theme_slug: "<previous-theme-slug>" })
# → dry_run; confirm

# For settings: PATCH back to the previous values
content_update_settings({ settings: { default_meta_title: "<previous>", ... } })
# → safe-default gated
```

### Step 5 — Redeploy

Once all pages + theme + settings are restored, redeploy:

```
content_deploy_readiness()
# → confirm no blocking issues (e.g. the bad version didn't leave settings in a half-state)

content_deploy_site_preview()
# → { preview_url, confirm_token, ... }

# Eyeball the preview URL — confirm the restore actually landed visually

content_deploy_site_production({ confirm_token: "cft_..." })
# → { status: "live", version_id: 49 }
```

You now have **`version_id: 49`** that contains the state of `version_id: 47`. The bad deploy (`48`) is in the history, marked superseded, but its rows aren't gone — re-restorable if needed.

### Step 6 — Verify with visual-check

Don't trust a 200. Run [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page):

```
content_visual_check({
  page_url: "https://<tenant>/<key-page>",
  viewport: "desktop"
})
# → confirm the rolled-back content actually shows
```

For form-bearing pages: `dom.shadow_hosts.includes("spideriq-form")`, NOT `body_text_preview` — Rule 62, [`../reference/booking-model.md`](booking-model.md).

### Gotchas

- **There is no `undo_deploy` tool.** Rollback = restore pages + redeploy. Anyone looking for "the rollback button" needs this recipe.
- **Restore lands as draft.** You MUST `content_publish_page` after, then `content_deploy_site_production`. Three gated steps per page; budget time.
- **Theme apply rollback re-applies the previous theme**, but the previous theme's tokens may have been mutated since. Capture the actual previous tokens via `template_get_config` BEFORE the bad theme apply if you can; otherwise you're restoring "the slug that was active" not "the exact tokens."
- **Component rollback is its own primitive.** If the bad deploy included `content_update_component` mutations, also use `component_rollback({ slug, target_version })` — see [`../components/rollback-component.md`](components.md#rollback-component).
- **CF Worker cache** holds the bad bundle for ~30s after deploy. Visitors who load during the cache window still see the bad version. `content_visual_check` from a fresh edge does NOT hit cache; eyeball from a real browser to confirm cache purge.
- **Some clients receive instant push notifications / emails based on page state.** A rollback may trigger a "back to old version" notification cycle. Audit your automations before rolling back live.
- **Database-side, the bad version is preserved.** This is intentional — re-restorable, audit-loggable. Don't try to "delete" the bad version row.

### Verify

```
# Page-level
content_get_page({ page_id })
# → confirm blocks[] match what you expected from the restored version

# Site-level
content_deploy_status()
# → latest.version_id should be your new rollback deploy (e.g. 49)

# Live verification
curl -sI "https://<tenant>/<key-page>" | grep -E "etag|last-modified"
# → confirm the response is from the new deploy

content_visual_check({ page_url: "..." })
# → confirm rolled-back content renders
```

### Anti-patterns

- **Trying to "undeploy" by deleting the deploy version row.** The row IS the audit chain. Restore + redeploy preserves history.
- **Skipping the dry_run on `content_restore_page_version`.** Safe-default gated for a reason — the dry_run shows you EXACTLY what's coming back. Skip it and you might restore the wrong version on the wrong page (Lock 5 catches the wrong-tenant case but not wrong-page).
- **Rolling back without first identifying scope.** If a theme apply broke 50 pages and you restore one, the other 49 still look broken. List + filter affected pages first.
- **Forgetting the `content_publish_page` step.** Restore creates a draft; visitors still see the bad live version until you publish + redeploy.
- **Redeploying without `content_visual_check`.** A 200 from `content_deploy_site_production` means "request accepted." Visual check confirms visitors actually see the restored content.
- **Rolling back during peak traffic without notifying stakeholders.** Even a clean rollback may show the wrong content for ~30s during cache transition. Coordinate.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "roll back a bad deploy"
# Top-1 should be: recipes/deploy/rollback-deploy.md
```

### See also

- [`../content/restore-page-version.md`](content.md#restore-page-version) — the per-page primitive used in Step 3
- [`../components/rollback-component.md`](components.md#rollback-component) — when the bad change was inside a component, not on a page
- [`deploy-preview-only.md`](templates-deploy.md#deploy-preview-only) — use this BEFORE production deploys to catch the issue early
- [`../audit/deploy-readiness.md`](audit.md#deploy-readiness) — pre-deploy checklist to prevent needing a rollback
- [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) — post-rollback verification
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the full gate + token semantics
