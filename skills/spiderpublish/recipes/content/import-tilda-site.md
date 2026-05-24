# recipes/tilda-migration

Port a Tilda (or Webflow / Lovable / hand-coded) site to SpiderPublish as Shadow-DOM components, one section at a time, using the opt-in `auto_extract_css` flag so inline `<style>` blocks don't blow up.

## When to use

- You have legacy HTML that embeds `<style>` blocks in every section (the Tilda / Webflow pattern).
- You want every section to render isolated via Shadow DOM so migrations don't introduce CSS spillage.
- You're migrating 10–60 pages and want a repeatable script-per-section flow.

**Not for:** hand-authored components where you want the explicit-over-magical contract. Default behavior still rejects inline `<style>` with a 400 — this recipe is the opt-in escape hatch.

## Proven references

| Client | Domain | Notes |
|---|---|---|
| SMS-Chemicals | sms-chemicals.com | First full Tilda → SpiderPublish port. Referenced below. |
| Di-Atomic | di-atomic.com | 33 pages, large component library; hit the silent-accept bug + duplicate-component-variant trap. |
| Onyx Radiance | onyx-radiance.com | From-scratch rebuild; pioneered the category='header'\|'footer' auto-skip pattern. |

## Steps

### 1. Export the source HTML

- **Tilda:** download `.zip` from the Tilda dashboard, or use the Tilda API with `TILDA_PUBLIC_KEY` / `TILDA_PRIVATE_KEY`.
- **Webflow / Lovable / hand-coded:** extract each page section into its own HTML file. A section = a logical block (hero, features, CTA, pricing, footer, …).

You want one HTML file per component-to-be.

### 2. Upload images to SpiderMedia

Don't leave `src="…"` pointing at `static.tildacdn.one` or other external hosts — edge caching won't help, rate limits will bite you, and link-rot breaks your site months later. One call:

```bash
# MCP
upload_local_directory(local_dir="./tilda-export/images/", folder="tilda-migration/")
# or CLI
npx @spideriq/cli media upload ./tilda-export/images/ --folder tilda-migration/
```

Then rewrite every `src`/`href` in your exported HTML to point at `https://media.cdn.spideriq.ai/…`.

### 3. Create each section as a component with `auto_extract_css=true`

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

Runnable end-to-end: [examples/tilda-migrate.sh](../../../examples/tilda-migrate.sh).

### 4. Mark headers/footers with `category` so native chrome auto-skips

If the page will have a custom header or footer component, create it with `category: "header"` or `"footer"`:

```json
{ "slug": "acme-header", "category": "header", "html_template": "<header>...</header>", "css": "..." }
```

When any page block resolves to a component with `category='header'`, the renderer suppresses the native `{% section 'header' %}`. No `nukeUI()` polling JS, no `template='blank'` fallback, no conditional `copyright_text` scripts. Same rule for footers.

### 5. Publish the component

```bash
POST /components/{id}/publish?dry_run=true   → confirm_token
POST /components/{id}/publish?confirm_token=cft_…  → published
```

### 6. Create the page with canonical block payload

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

### 7. Publish + deploy

```bash
# Per-page
POST /pages/{id}/publish?dry_run=true  → confirm_token  → consume

# Site-wide, when all pages are in
content_deploy_site_preview()           → review preview_url
content_deploy_site_production(confirm_token=...)  → live in ~2-5 s
```

Use `--yolo` on the CLI (`spideriq content deploy --yolo`) if you're iterating on copy and don't need the preview step.

## Anti-patterns that cost hours

| Don't | Why | Do |
|---|---|---|
| POST HTML with inline `<style>` and no `auto_extract_css=true` | 400: "Found `<style>` block… Component CSS must live in the `css` field" | Pass `auto_extract_css: true` |
| Leave external `<link rel="stylesheet">` inside `html_template` | Shadow DOM silently ignores it — blank section | Inline the CSS (download, concat, put in `css` field) |
| Use `slug: "product/pillowcase"` | 422 at creation (since 2026-04-24) | Flat slug `product-pillowcase` |
| Write `nukeUI()` JavaScript to hide double chrome | Polling setInterval → FOUC + CPU burn | Create header with `category: "header"` — renderer auto-suppresses native |
| Pass `data: {slug: "x"}` on a component block | 422 since 2026-04-24 | `component_slug: "x"` at the block's top level |
| `filename="..."` without `preserve_filename: true` on bulk media upload | Prefixed `YYYYMMDD_HHMMSS_` in the key → your relative image URLs break | `preserve_filename: true` (auto-enabled by `upload_local_directory` for `scroll-sequences/*`) |
| Loop `component_update` + N × `content_update_page` to change a shared component | 10+ calls, risk of partial update | `component_update_and_propagate(slug, ...)` — one call |

## Cleanup after ship

```bash
# Verify no broken links survived the migration
content_audit_links()
```

If `broken[]` has entries that are legacy `/old/…` paths you don't want to preserve, create `content_redirect` rows (301s) to the new locations.

## See also

- [recipes/component-update-and-propagate](../component-update-and-propagate/) — for site-wide header/footer changes post-migration
- [recipes/link-audit](../link-audit/) — the post-migration check
- [recipes/bulk-media-upload](../bulk-media-upload/) — for moving the Tilda image assets in one call
- [examples/tilda-migrate.sh](../../../examples/tilda-migrate.sh) — runnable end-to-end
- [LEARNINGS.md → Apr 2026 Triage](../../../LEARNINGS.md#apr-2026-triage) — the silent-failure modes this recipe closes
