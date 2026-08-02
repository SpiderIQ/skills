# reference/block-types

The ContentBlock model — block-types the default theme renders, accepted `data.*` fields per type, the `css`-field rule, and the most-confused mistakes that produce blank sections instead of 422s. Cited by `content/landing-page.md`, `content/blog-post.md`, and every recipe that touches `blocks[]`.

## TL;DR

- **A page is `{ blocks: [ {id, type, data}, ... ] }`** stored as JSONB. The renderer iterates `blocks`, looks up the right Liquid snippet per `type`, and reads specific `data.*` keys per type.
- **Wrong `data.*` field names render BLANK, not 422.** The "silent-blank-section" trap. Page auditor warns (`render.unused_field_in_default_theme`) but doesn't block. **Always run `template_inspect_block_fields(block_type)` before composing a non-component block.**
- **Component blocks use `component_slug` at the TOP LEVEL**, not `data.slug` (validator 422s loudly — good).
- **Custom component CSS goes in the separate `css` field, NEVER `<style>` inside `html_template`** (Shadow DOM ignores inline styles).

## Shape of a block

```json
{
  "id": "01HXXXXXXXXXXXXXXXXX",
  "type": "hero",
  "data": { "headline": "...", "subheadline": "...", "cta_primary": { "label": "...", "url": "..." } }
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | UUID or short ID. Stable handle for `content_duplicate_block`. |
| `type` | yes | One of the 15 enums below, OR `"component"` for marketplace/library components. |
| `data` | yes (`{}` ok) | Per-type payload. Unknown keys are stored verbatim but don't render (the silent-blank trap). |
| `component_slug` | only when `type: "component"` | TOP-LEVEL, not `data.slug`. |
| `component_version` | optional | Pin a specific semver; default is latest published. |
| `layout` | optional, top-level | Marketplace V2 (`"full"|"contained"|"split"|…`) — at the TOP, NOT under `data`. |
| `data_binding` | optional, top-level | Marketplace V2 dynamic-data binding — at the TOP, NOT under `data`. |

## The 15 default block_types + accepted `data.*` keys

Every key below is **what the default-theme snippet ACTUALLY reads**. Other key names render as empty markup. Source-of-truth probe (call once per session and cache):

```bash
curl -s https://spideriq.ai/api/v1/content/help/block-fields | jq .
```

Or via MCP: `template_inspect_block_fields({ block_type: "hero" })`.

### `hero`

```json
{
  "type": "hero",
  "data": {
    "headline": "Get started with SpiderPublish",
    "subheadline": "Multi-tenant CMS + booking on Cloudflare's edge",
    "cta_primary":   { "label": "Start free trial", "url": "/signup" },
    "cta_secondary": { "label": "Read the docs",    "url": "/docs" },
    "background_image_url": "https://media.spideriq.ai/<tenant>/hero-bg.jpg",
    "style": "centered"
  }
}
```

| ✅ Use | ❌ Silent-blank if you write |
|---|---|
| `headline` | `title` |
| `subheadline` | `subtitle`, `description` |
| `cta_primary.label` / `.url` | `cta_text`, `cta_url` (flat) |
| `background_image_url` | `image`, `bg_url` |

### `features_grid`

```json
{ "type": "features_grid", "data": {
  "headline": "What you get",
  "columns": 3,
  "features": [
    { "icon": "rocket", "title": "Fast",     "description": "Edge-rendered" },
    { "icon": "lock",   "title": "Safe",     "description": "Five-lock defense" },
    { "icon": "scale",  "title": "Scalable", "description": "1 binary, N tenants" }
  ]
}}
```

| ✅ Use | ❌ Silent-blank |
|---|---|
| `features[]` | `items`, `cards` |
| `columns` (int) | `cols`, `count` |

### `cta_section`

```json
{ "type": "cta_section", "data": {
  "headline": "Ready to ship?",
  "description": "Start free, no card.",
  "cta_primary": { "label": "Start free", "url": "/signup" }
}}
```

### `faq`

```json
{ "type": "faq", "data": {
  "headline": "Frequently asked",
  "items": [
    { "question": "Is there a free tier?", "answer": "Yes." },
    { "question": "Do you support custom domains?", "answer": "Yes — see ../content/custom-domain.md." }
  ]
}}
```

### `rich_text` — the most-confused block

```json
{ "type": "rich_text", "data": { "html": "<p>Arbitrary <strong>raw</strong> HTML.</p>" } }
```

OR

```json
{ "type": "rich_text", "data": { "content": { "type": "doc", "content": [ { "type": "paragraph", "content": [ { "type": "text", "text": "Tiptap JSON" } ] } ] } } }
```

| ✅ Use | ❌ 422 / silent |
|---|---|
| `data.html` (raw HTML string) | `data.text` (silent-blank) |
| `data.content` (Tiptap JSON **object**) | `data.content` as a **string** → **422** rejected (F-7 / Rule 65) |

The validator now rejects `data.content` strings loudly post-PR-#841. Older sessions silently rendered blank because the renderer expected an object and got a string.

### `stats_bar`

```json
{ "type": "stats_bar", "data": {
  "stats": [
    { "value": "12k+", "label": "Forms shipped"  },
    { "value": "99.9%", "label": "Renderer uptime" }
  ]
}}
```

### `testimonials`

```json
{ "type": "testimonials", "data": {
  "headline": "Trusted by teams",
  "testimonials": [
    { "quote": "It just works.", "name": "M. Shein", "role": "Founder", "company": "SpiderIQ" }
  ]
}}
```

### `pricing_table`

```json
{ "type": "pricing_table", "data": {
  "headline": "Plans",
  "plans": [
    { "name": "Starter", "price": "$0",  "period": "/mo", "description": "Hobby",
      "features": ["1 tenant", "100 pages"], "featured": false,
      "cta": { "label": "Start", "url": "/signup" } },
    { "name": "Pro",     "price": "$29", "period": "/mo", "description": "Teams",
      "features": ["10 tenants", "Unlimited pages"], "featured": true,
      "cta": { "label": "Upgrade", "url": "/pricing" } }
  ]
}}
```

### `comparison_table`

```json
{ "type": "comparison_table", "data": {
  "headline":     "Us vs them",
  "subheadline":  "What you get with SpiderPublish",
  "eyebrow":      "Comparison",
  "headers":      ["Feature", "SpiderPublish", "Generic CMS"],
  "rows": [
    { "label": "Multi-tenant", "cells": ["Built-in", "Bring your own"] },
    { "label": "Edge-rendered", "cells": ["Yes",     "Behind a CDN"] }
  ],
  "style": "minimal",
  "footnote": "* Edge = Cloudflare's 280+ POPs."
}}
```

`columns` is an alias for `headers` for back-compat.

### `image`

```json
{ "type": "image", "data": {
  "src":     "https://media.spideriq.ai/<tenant>/diagram.png",
  "alt":     "Architecture diagram",
  "caption": "STORE / SERVE / MANAGE layers."
}}
```

### `video_embed`

```json
{ "type": "video_embed", "data": {
  "url":       "https://www.youtube.com/watch?v=XXXXXXXXXXX",
  "video_id":  "XXXXXXXXXXX",
  "provider":  "youtube",
  "caption":   "5-min product walkthrough."
}}
```

### `code_example`

```json
{ "type": "code_example", "data": {
  "title":       "Create a page",
  "description": "Minimum viable call",
  "code":        "content_create_page({ title: \"Hello\" })"
}}
```

### `logo_cloud`

```json
{ "type": "logo_cloud", "data": {
  "headline": "Used by",
  "logos": [
    { "src": "https://media.spideriq.ai/clients/acme.svg",   "alt": "Acme" },
    { "src": "https://media.spideriq.ai/clients/wonka.svg",  "alt": "Wonka" }
  ]
}}
```

### `spacer`

```json
{ "type": "spacer", "data": { "height": 96 } }
```

`height` is in pixels, default 48.

### `component` — library + marketplace components

```json
{
  "type": "component",
  "component_slug":    "sys-hero-split",
  "component_version": "1.2.0",
  "data": { /* per-component props as declared in the component's props_schema */ }
}
```

| ✅ Use | ❌ 422 |
|---|---|
| `component_slug` at TOP LEVEL | `data.slug` → 422 |
| `component_version` at TOP LEVEL (optional) | `data.version` → silently ignored |
| Component props live in `data` | Top-level `props: {}` → silently ignored |

To discover what props a component accepts, call `content_get_component_by_slug({ slug: "<the-slug>" })` and inspect `props_schema`. See [`../components/find-component.md`](../components/find-component.md).

## The `css`-field rule for components

When you create or update a custom component:

```
content_create_component({
  slug: "sys-pretty-card",
  name: "Pretty card",
  html_template: "<div class=\"card\"><h3>{{ title }}</h3><p>{{ body }}</p></div>",
  css: ".card { padding: 2rem; border-radius: 12px; background: var(--surface); }"
})
```

| ✅ Right | ❌ Wrong |
|---|---|
| CSS in the separate `css` field | CSS inside `<style>` tags inside `html_template` |
| Single-class names — no global resets | Body / html selectors (Shadow DOM scoped) |
| Use Tailwind utility classes ONLY if the component's parent page injects Tailwind into the shadow root (rare; default theme doesn't) | Rely on global Tailwind from the host page — Shadow DOM blocks it |

The renderer wraps `html_template` in a Shadow DOM root and injects `css` as a scoped `<style>` inside the root. **Inline `<style>` blocks inside `html_template` are ignored** because Shadow DOM doesn't expose them. This catches authors maybe 10% of the time on first attempt; codify into your component skeleton.

## Anti-patterns (the canonical 6)

1. **`data.content` as a string on `rich_text`.** 422 post-PR-#841. Use `data.html` (string) or `data.content` (Tiptap JSON object). F-7 / Rule 65.
2. **Wrong field names render BLANK, not 422.** `data.title` for hero, `data.items` for features_grid, `data.cta_text` anywhere — the auditor warns (`render.unused_field_in_default_theme`) but the page still publishes. **Run `template_inspect_block_fields({block_type})` before composing any non-component block.**
3. **`{type:'component', data:{slug:'x'}}` → 422.** Top-level `component_slug`. Same for `component_version`.
4. **Marketplace-V2 `{type:'X', data:{layout:'split'}}` → 422.** `layout` and `data_binding` are top-level fields, not nested under `data`.
5. **Inline `<style>` inside a component's `html_template` is silently dropped.** Use the `css` field.
6. **Mutating `blocks[]` between `dry_run` and `confirm_token` invalidates the token.** The token is snapshot-bound. After edits, run dry_run again.

## Live discovery — call once per session

The block-fields catalog is served live from the api-gateway. **Cache it** to avoid per-page round-trips.

```bash
# Public read — no auth
curl -s https://spideriq.ai/api/v1/content/help/block-fields | jq .
```

Or via MCP (no auth needed — public endpoint):

```
template_inspect_block_fields()                          # all block types
template_inspect_block_fields({ block_type: "hero" })    # one block type
```

The MCP tool returns:

- `fields[]` — keys the active snippet reads
- `_aliases` — common mistakes → canonical (e.g. `{"title": "headline"}`)
- `_anti_patterns` — shapes the validator rejects
- `_notes` — free-form caveats

Use this BEFORE composing any non-component block. Costs ~50 tokens; saves the silent-blank trap every time.

## See also

- [`../content/landing-page.md`](../content/landing-page.md) — canonical end-to-end recipe using these block types
- [`../content/blog-post.md`](../content/blog-post.md) — Tiptap JSON body shape (post.body, not block.data.content)
- [`../components/create-component.md`](../components/create-component.md) — Tiers 1-4 component authoring
- [`../components/find-component.md`](../components/find-component.md) — discovering existing components + props
- [`tool-surface.md`](tool-surface.md) — full tool catalog
- catalog/LEARNINGS.md Rules 64 + 65 — the source incidents
