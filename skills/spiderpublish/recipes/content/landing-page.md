# recipes/content/landing-page

Author + publish a marketing landing page from scratch — hero, features, social proof, CTA, deploy. This is the **canonical** block-based authoring recipe; every other content recipe cascades from here.

## When to use

- A tenant needs a new marketing landing page on their SpiderPublish site (`/`, `/features`, `/pricing`, a campaign URL like `/launch`).
- You want to compose the page from the bundled block types — no custom components needed.
- You're new to SpiderPublish authoring and need the end-to-end shape, including: block-field hygiene, dry_run preview, publish, deploy, visual verify.

If you want to *insert one marketplace section into an existing page* → [`landing-page-with-components.md`](#) (queued for v0.4.0) or just use `page_insert_section` + `content_get_component_by_slug`. If you want to *clone a curated starter site* → use `content_apply_site_template` instead.

## Prerequisites

1. **Tenant scope verified.** Run the script and paste output:
   ```bash
   ./scripts/verify-tenant-scope.sh
   ```
   Exit 0 → safe. Anything else → fix per [`../../_shared/auth.md`](../../_shared/auth.md) before continuing.
2. **Discovery endpoints cached.** Fetch once per session:
   ```bash
   curl -s https://spideriq.ai/api/v1/content/help/block-fields | jq 'keys'
   ```
   Or via MCP: `template_inspect_block_fields()` — see [`../reference/block-types.md`](../reference/block-types.md).
3. **MCP server reachable.** `@spideriq/mcp-publish` (87 tools, atomic) OR `@spideriq/mcp` (134+ kitchen-sink) — see [`../reference/tool-surface.md`](../reference/tool-surface.md).

## The 5-call path

```
1. (optional) template_inspect_block_fields     — confirm field names per block
2. content_create_page                          — create the draft with blocks (or pass dry_run=true)
3. content_get_page  (audit_level: "warnings")  — read auditor output for silent-blank traps
4. content_publish_page                         — draft → published (defaults to dry_run=true)
5. content_deploy_site_production (or _site)   — push to CF edge; site live in ~2-5s
```

Plus one verification step at the end (`content_visual_check`). Estimated ~30 min for a 4-block page including iteration.

### 1. Inspect block fields (optional but recommended)

Skip this if you're using only `hero` + `features_grid` + `cta_section` — they're committed-to-memory shapes. For anything else (`comparison_table`, `pricing_table`, the `rich_text` content-vs-html footgun), inspect first:

```
template_inspect_block_fields({ block_type: "comparison_table" })
// → { fields: [...], _aliases: {...}, _anti_patterns: [...], _notes: "..." }
```

The `_aliases` map (e.g. `{"title": "headline"}`) catches the most-common typos before you hit the silent-blank trap.

### 2. Create the page (draft)

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
- `slug` is flat — `^[a-z0-9][a-z0-9-]*$`. No `/`. Nested URLs not supported here; docs use `parent_id` chains (see [`docs-page.md`](docs-page.md)).
- `template` selects which `templates/<name>.liquid` renders. `default` is fine for most landing pages. Use `landing` for header-only chrome, `blank` for full-canvas, or your own custom template name. **NOT** `forms-standalone` / `booking-standalone` — those are server-side-picked for `/f/<id>` (see Rule 65).
- Phase 11+12 is **opt-in** here. The call above mutates immediately. Pass `dry_run: true` to preview:

  ```
  content_create_page({ ..., dry_run: true })
  // → { preview, confirm_token: "cft_...", expires_at, snapshot_hash }
  ```

  Then call again with `{ ..., confirm_token: "cft_..." }` to confirm. See [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md).

### 3. Audit the draft (free)

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

### 4. Publish (draft → published)

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

The publish creates a version snapshot in `content_page_versions` — you can roll back with `content_restore_page_version` if needed. See [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) for the gate semantics.

### 5. Deploy the site

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

## Verify (don't trust the 200)

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

**If the page contains a form block** (`{type: "component", component_slug: "spideriq-form-embed", ...}`) or you visual-check a form-rendering URL: assert on `dom.shadow_hosts.includes("spideriq-form")`, NEVER on `body_text_preview` (cross-origin iframe is opaque). Rule 62 — see [`../reference/booking-model.md`](../reference/booking-model.md#visual-check).

## Iterate (the realistic loop)

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

## Anti-patterns

1. **Wrong `data.*` field names render BLANK, not 422.** `data.title` on hero, `data.items` on features_grid, `data.cta_text` anywhere → page publishes silently broken. **Always run `template_inspect_block_fields(block_type)` first** OR read [`../reference/block-types.md`](../reference/block-types.md). F-7 / Rule 65.
2. **`{type:'rich_text', data:{content:'<string>'}}` → 422.** Use `data.html` (string) or `data.content` (Tiptap JSON **object**). PR-#841 made this loud.
3. **`{type:'component', data:{slug:'x'}}` → 422.** `component_slug` is TOP-LEVEL on the block, not under `data`.
4. **`template: "forms-standalone"` / `"booking-standalone"` on a content page.** Those are server-side-picked by the `/f/<id>` route from the flow's `kind`. Setting them on a normal page binds a chrome that probably isn't what you want. Use `default`, `blank`, `landing`, or a custom template name. Rule 65.
5. **Skipping `content_deploy_readiness` before deploy.** Deploy will 4xx if blocking items aren't resolved; readiness probe gives you the list cheaply.
6. **Asserting on `body_text_preview` when the page has a form block.** Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.

## See also

- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the two-phase pipeline + ConfirmTokenError envelopes
- [`../reference/block-types.md`](../reference/block-types.md) — every block-type + `data.*` field + alias map
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — MCP package picker + discovery endpoints
- [`../reference/booking-model.md`](../reference/booking-model.md) — `kind='form'` URL surface + Rule 62 visual-check
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth + tenant binding
- [`apply-theme.md`](apply-theme.md) — change the visual identity site-wide
- [`navigation.md`](navigation.md) — add this page to the header / footer menu
- [`landing-page-with-components.md`](landing-page-with-components.md) — compose with marketplace sections (v0.4.0)
- [`preview-iteration.md`](preview-iteration.md) — fast preview loop without full deploy
