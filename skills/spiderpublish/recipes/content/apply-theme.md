# recipes/content/apply-theme

Apply a pre-built theme to a tenant's site — copies all theme templates (layout, sections, snippets) to the tenant's per-tenant KV. Site visually changes after deploy. Phase 11+12 gated (defaults to dry_run=true).

## When to use

- A tenant is on the default starter theme and wants to switch to a curated alternative (`vayapin`, `agency-bold`, `editorial`, etc. — see `template_list_themes()` for the live catalog).
- You've authored a new theme in `apps/liquid-renderer/themes/<name>/` and want to apply it to a tenant for testing.
- You're rolling out a brand refresh and need to swap themes site-wide.

If you only want to **override one section** (header, footer) without swapping the whole theme → [`section-override.md`](section-override.md). If you want a different *layout chrome* (header + footer present? edge-to-edge main?) without a theme swap → use `content_apply_layout_preset({ preset: "blank" })` — see [`section-override.md`](section-override.md#layout-presets).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You know which theme.** Call `template_list_themes()` to see the catalog. Theme names are slugs (`default`, `vayapin`, …).
3. **Backups of any custom templates.** `template_apply_theme` OVERWRITES every template path the new theme ships. If you've customized `layout/theme.liquid` or any `sections/*.liquid` and want to keep those overrides: export them first (`template_list()` + `template_get({path})`), apply the theme, then re-apply your overrides via `template_upsert`.

## The 4-call path

```
1. template_list_themes              — see available themes
2. template_apply_theme              — dry_run by default; returns preview + confirm_token
3. template_apply_theme(confirm_token: ...)  — actually apply
4. content_deploy_site_production    — push the new templates to the edge
```

Plus a visual-check at the end.

### 1. List themes

```
template_list_themes()
// → [
//   { name: "default",   description: "Standard SaaS chrome — header, hero, features, footer", templates_count: 29 },
//   { name: "vayapin",   description: "Restaurant industry — bg-video hero, big-photo sections", templates_count: 35 },
//   { name: "editorial", description: "Magazine / law firm — serif headings, monochrome", templates_count: 27 }
// ]
```

Pick by name. If the tenant has a specific industry-shaped theme they want, grep by description. If you want to see what files a theme ships, `template_list({theme: "<name>"})` returns the file paths.

### 2. Preview (dry_run defaults to true)

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

### 3. Confirm + apply

```
template_apply_theme({ theme: "vayapin", confirm_token: "cft_..." })
// → { applied: true, theme: "vayapin", templates_written: 35, version_id: 12 }
```

The new theme's templates are now in the tenant's per-tenant KV. **The visible site has NOT changed yet** — the renderer reads templates from KV at deploy time, not at request time (templates are cached). Step 4 pushes the change live.

### 4. Deploy

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

## Verify

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

## Roll back

```
# Option A — re-apply the previous theme (same flow)
template_apply_theme({ theme: "default" })
template_apply_theme({ theme: "default", confirm_token: "cft_..." })
content_deploy_site_production({ confirm_token: "cft_..." })

# Option B — restore a specific deploy version
# (no first-party MCP yet; use the dashboard's deploy history or REST)
```

The theme swap is "just" a bulk `template_upsert` of every file the theme ships. Rolling back is a re-apply of the previous theme + deploy. Tenant content (pages, posts, components) is unaffected by theme swaps — only templates change.

## Anti-patterns

1. **Skipping the dry_run.** `template_apply_theme` defaults to `dry_run: true` for a reason — `templates_to_overwrite` tells you what customizations you're about to lose. Read it.
2. **Forgetting to deploy after apply.** The KV write doesn't push to the edge. Run `content_deploy_site_production` after every `template_apply_theme(confirm_token)`.
3. **Theme-swapping a high-traffic site mid-day.** Even with 2-5s deploy, the cache invalidation can produce a brief blank-page window. Schedule for off-hours, OR use `content_deploy_site_preview` to eyeball and warm the cache first.
4. **Assuming `template_apply_theme` migrates content too.** It only writes templates (Liquid files). Pages, posts, settings, navigation are untouched. If you also want to apply a curated CONTENT set, that's `content_apply_site_template` — different tool, different gate (also dry_run-default).
5. **Customizing templates AFTER `template_apply_theme` without re-running the dry_run.** Every theme apply is a snapshot of the source theme — if you customize, then later re-apply (or apply a different theme), your customizations will be overwritten. Keep customizations in a separate scratchpad / repo, and re-apply via `template_upsert` after every theme swap.

## See also

- [`section-override.md`](section-override.md) — override one section without a full theme swap
- [`apply-site-template.md`](#) — apply a curated *content* set (pages + components + settings) — queued v0.4.0
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the two-phase deploy after apply
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — full `template_*` tool catalog
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
- catalog/CLAUDE.md → "Liquid Renderer Worker" — per-tenant KV mechanics
