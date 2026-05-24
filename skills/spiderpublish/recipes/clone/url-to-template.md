# recipes/clone/url-to-template

Clone a public URL into a SpiderPublish Liquid template + extracted components. SpiderClone scrapes the source URL, tokenizes the markup into per-section components, uploads images to SpiderMedia, and emits a draft theme + draft pages ready to publish.

## When to use

- A prospect points at a competitor's site ("can you replicate this look?") and you want a working SpiderPublish tenant that matches in <30 minutes.
- A client is migrating from a hosted page-builder (Tilda, Webflow, Lovable, Wix, Squarespace) and you have URLs but not source HTML.
- You're building demos / spec'ing new theme designs by cloning reference sites as a starting point.

If you have **source HTML files** (Tilda export, hand-coded) → use [`tilda-migration.md`](../content/import-tilda-site.md) instead. SpiderClone is the URL-only path.

## Honest framing

SpiderClone is a **best-effort scraper + emitter**, not a perfect-replica tool. Expect:

- 70-90% visual fidelity on first run for simple marketing sites.
- 30-50% on JavaScript-heavy sites (React SPAs, animation-heavy hero sections, scroll-jacked landing pages).
- Manual cleanup after every run — extracted sections become draft components you can iterate on.

It's a **starting-point generator**, not a one-shot finished site.

## Tool surface — current state

The first-party SpiderClone MCP tool surface is **still emerging**. As of 2026-05-24, the production-ready paths are:

1. **REST endpoint** at `POST /api/v1/dashboard/projects/{pid}/clone/from-url` (server-side). <!-- VERIFY: confirm endpoint path — based on inventory `recipes/clone/url-to-template.md` Section A.10 row 45 referencing `content_clone_*` tool family with confirm-existence-in-kitchen-sink note. -->
2. **CLI command**: `spideriq clone from-url <url>`. <!-- VERIFY: command surface — based on @spideriq/cli inventory; may be named differently. -->
3. **MCP tool**: not yet exposed in `@spideriq/mcp` kitchen-sink as of 2026-05-24. <!-- VERIFY: grep `packages/mcp-tools/src/publish/` for `clone_from_url` or similar; if absent, this recipe stays REST/CLI-only until the MCP wrapper lands. -->

This recipe shows the REST path. When the MCP tool lands, the structure here transfers directly — same params, same flow.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Source URL reachable** from the SpiderPublish scraper (i.e. not behind auth, not geo-blocked from CF's edge).
3. **SpiderMedia R2 quota** — the cloner uploads every extracted image. Large sites can hit tenant quota; check `get_media_stats()` first.
4. **`spideriq.json` bound to the destination tenant.** Cloned drafts land in this tenant, not the source.

## The 4-step path

```
1. POST /clone/from-url     — kick off the scrape + emit
2. (poll for completion)     — clone is async; usually 30-120s
3. (review draft components + pages)  — content_list_components + content_list_pages
4. content_publish_component / content_publish_page + content_deploy_site
```

### 1. Kick off the clone

```bash
curl -X POST "https://spideriq.ai/api/v1/dashboard/projects/$PID/clone/from-url" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "source_url": "https://example-competitor.com/",
    "include_paths": ["/", "/features", "/pricing", "/about"],
    "extract_strategy": "section",
    "upload_images_to_r2": true
  }'
# → { job_id: "clone_...", status: "queued", estimated_seconds: 60 }
```

**Params:**

| Field | Notes |
|---|---|
| `source_url` | The starting URL. Required. |
| `include_paths` | Array of paths to crawl from the source domain (default: just `/`). Use to constrain to a few key pages instead of the whole site. |
| `extract_strategy` | `"section"` = one component per visible section (recommended). `"whole_page"` = one component per page (less granular, harder to iterate). |
| `upload_images_to_r2` | When `true`, every `<img src="...">` is fetched and uploaded to your SpiderMedia bucket. Source URLs rewritten to `https://media.cdn.spideriq.ai/...`. Skip with `false` only if you're testing — link-rot from the source CDN breaks the site months later. |

<!-- VERIFY: confirm `clone_from_url` endpoint shape. Based on research-spiderpublish-content-inventory.md Section A.10 — actual signature may differ. -->

### 2. Poll for completion

```bash
curl "https://spideriq.ai/api/v1/dashboard/projects/$PID/clone/jobs/clone_..." \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET"
# → {
#     job_id: "clone_...",
#     status: "running" | "succeeded" | "failed",
#     progress: { pages_scraped: 4, components_extracted: 17, images_uploaded: 23 },
#     emitted: {
#       theme_name: "cloned-from-example",
#       components: [ { slug: "home-hero", category: "hero", status: "draft" }, ... ],
#       pages:      [ { slug: "home", template: "default", status: "draft" }, ... ]
#     },
#     errors: []   # populated if scrape partially failed
#   }
```

Typical timing: 30-120s for a 5-page site, longer for image-heavy ones. The cloner emits incrementally — `components` and `pages` populate as work progresses.

`emitted.theme_name` is the new theme. You don't need to `template_apply_theme` it explicitly — the cloned pages already reference its templates. But you CAN apply it as the tenant's default if you want non-cloned pages to also use it.

### 3. Review what landed

```
# List the extracted components
content_list_components({ status: "draft", limit: 50 })
// → [
//   { slug: "home-hero",       category: "hero",     status: "draft", ... },
//   { slug: "home-features",   category: "features", status: "draft", ... },
//   { slug: "pricing-table",   category: "pricing",  status: "draft", ... },
//   ...
// ]

# Inspect one
content_get_component_by_slug({ slug: "home-hero" })
// → { html_template, css, props_schema, default_props, ... }
```

Read each component. Things to expect:

| Often correct | Often needs editing |
|---|---|
| HTML structure | Animations (CSS @keyframes, JS-driven) |
| CSS layout (flexbox, grid) | Interactive JS (carousels, modals — emitted as static) |
| Image URLs (now pointing at SpiderMedia) | Font references (clone may miss `@font-face` declarations) |
| Static text | Dynamic text (CMS-fed content from the source site) |
| Color palette | Hover-states (rarely captured) |

For non-trivial cleanup, edit the component in the Content Studio dashboard (better diffing) or use `content_update_component` for targeted patches.

```
content_list_pages({ status: "draft", limit: 50 })
// → [
//   { slug: "home",     status: "draft", blocks: [ {type: "component", component_slug: "home-hero", ...}, ... ] },
//   { slug: "features", status: "draft", blocks: [...] },
//   ...
// ]
```

Each page's `blocks` reference the extracted components by `component_slug`. You can `content_update_page` to rearrange, swap components, or drop sections.

### 4. Publish + deploy

```
# For each component
content_publish_component({ component_id: "comp_..." })
content_publish_component({ component_id: "comp_...", confirm_token: "cft_..." })

# For each page
content_publish_page({ page_id: "<page-uuid>" })
content_publish_page({ page_id: "<page-uuid>", confirm_token: "cft_..." })

# Then deploy
content_deploy_readiness()
content_deploy_site_preview()   # eyeball the preview URL
content_deploy_site_production({ confirm_token: "cft_..." })
```

Site is live in 2-5s on the tenant's primary domain.

## Verify

```
content_visual_check({
  page_url: "https://<tenant>/",
  viewport: "desktop"
})
```

Compare the screenshot side-by-side with the source URL. Typical differences after a clone+publish:

- Fonts: source uses Inter, clone falls back to system-ui. Fix: update `content_settings.css_variables` with the right `@font-face` declarations + font URLs.
- Animations: source has fade-in scroll triggers, clone is static. Fix: upgrade the component to Tier 3 (add GSAP dependency).
- Hover/focus states: source has them, clone may miss. Fix: add `:hover` / `:focus` rules to the component's `css` field.
- Form embeds: source has a HubSpot/Typeform iframe, clone embeds a static placeholder. Fix: create a SpiderPublish form (`form_create_from_template` or `build-form.md`) and swap the placeholder block.

## Iterate

The healthy loop after a clone:

```
1. clone (one-shot, 30-120s)
2. review → identify the 3-5 worst sections
3. content_update_component on each
4. content_deploy_site_production
5. visual_check, compare to source
6. repeat 3-5 until "good enough"
```

Don't try to make the clone 100% pixel-perfect — at some point it's faster to author from scratch using the clone as a structural reference.

## Anti-patterns

1. **Treating the cloned output as final.** It's a starting point. Plan for 30-60 min of manual cleanup per page.
2. **Skipping `upload_images_to_r2: true`.** Source CDNs rate-limit + go down + change URLs. Your tenant breaks 6 months later if you skip this.
3. **Cloning auth-walled or geo-blocked URLs.** Scraper can't reach them. Will return `errors: [{url, status: 403}]`. Either provide the HTML (use [`tilda-migration.md`](../content/import-tilda-site.md)) or pick a different URL.
4. **Cloning React/Vue SPAs.** The scraper renders with a headless browser, but heavy client-side state often produces blank-canvas captures. Test with a small `include_paths` first; if quality is bad, the source is SPA-shaped → reach for [`tilda-migration.md`](../content/import-tilda-site.md) or hand-author.
5. **Cloning into a production tenant directly.** Always test in a fresh tenant first. The clone creates dozens of draft components + pages — easy to pollute a production tenant. Use a `cloning-sandbox` tenant, iterate there, then copy the "good" components into production via `content_create_component` once you're happy.
6. **Publishing every cloned component without review.** Bad sections get published too. Triage first: which sections are usable as-is, which need iteration, which to drop entirely.

## See also

- [`../content/import-tilda-site.md`](../content/import-tilda-site.md) — HTML-source path (Tilda exports, Webflow, hand-coded) — preferred over URL-clone when you have source files
- [`../components/create-component.md`](../components/create-component.md) — author a component from scratch (clone's last resort)
- [`../content/landing-page.md`](../content/landing-page.md) — block-based authoring (when the clone needs a from-scratch rebuild)
- [`../content/apply-theme.md`](../content/apply-theme.md) — apply the cloned theme as the tenant default
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the two-phase publish + deploy
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*` component + page tools
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
