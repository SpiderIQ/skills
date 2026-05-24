# recipes/clone/import-tailwind

Take a Tailwind-built page (a `tailwind.config.js` + HTML markup with `class="…"` strings) and turn it into a SpiderPublish theme — design-tokens applied via `template_apply_theme` + draft pages with extracted components. The semi-manual sibling of [`url-to-template.md`](url-to-template.md) (URL scrape) and [`../content/import-tilda-site.md`](../content/import-tilda-site.md) (inline-style port).

## When to use

- A client built their MVP in Tailwind + plain HTML (or copy-pasted a Tailwind UI Kit snippet) and you want to migrate without rebuilding.
- You have a Figma → Tailwind code-gen export and want to land it as a SpiderPublish theme + pages.
- An agency hands over a Tailwind starter and you want first-pass tenant assets in a day.
- Pattern: "here's a tailwind.config.js + some `*.html` — make a SpiderPublish tenant out of it."

## Honest framing

There is **no first-party `tailwind_to_template` MCP tool** as of 2026-05-24. This is a structured manual flow that uses three existing primitives:

1. **`template_apply_theme`** — apply your extracted CSS-token map to the tenant theme.
2. **`content_create_component`** — register each unique Tailwind-class block (hero, card, CTA) as a component.
3. **`content_create_page`** — assemble pages from those components.

You do the **Tailwind → tokens** extraction client-side (a small Node script reading `tailwind.config.js`); the tools land the result.

## Prerequisites

1. **Tenant scope verified.** `./scripts/verify-tenant-scope.sh` exit 0.
2. **Source files on disk:** `tailwind.config.js` + a folder of `*.html` files (one per page).
3. **Node** to run the extraction script.
4. **`@spideriq/cli` installed** (for the registration steps).
5. **PAT** scoped to the destination tenant.

## Step 1 — Extract tokens from `tailwind.config.js`

Tailwind's `theme.extend` block IS your design-token source. A small Node script reads it and emits a SpiderPublish-friendly token map:

```javascript
// scripts/tailwind-to-tokens.mjs
import { default as tailwindConfig } from "../tailwind.config.js";

const colors = tailwindConfig.theme?.extend?.colors ?? {};
const fonts  = tailwindConfig.theme?.extend?.fontFamily ?? {};
const radius = tailwindConfig.theme?.extend?.borderRadius ?? {};

const tokens = {};
for (const [name, value] of Object.entries(colors)) {
  if (typeof value === "string") {
    tokens[`--color-${name}`] = value;
  } else if (typeof value === "object") {
    for (const [shade, hex] of Object.entries(value)) {
      tokens[`--color-${name}-${shade}`] = hex;
    }
  }
}
for (const [name, stack] of Object.entries(fonts)) {
  tokens[`--font-${name}`] = Array.isArray(stack) ? stack.join(", ") : stack;
}
for (const [name, value] of Object.entries(radius)) {
  tokens[`--radius-${name}`] = value;
}

console.log(JSON.stringify(tokens, null, 2));
```

Run it:

```bash
node scripts/tailwind-to-tokens.mjs > tokens.json
```

Produces:

```json
{
  "--color-primary-500": "#3b82f6",
  "--color-primary-600": "#2563eb",
  "--color-gray-50": "#f9fafb",
  "--font-sans": "Inter, ui-sans-serif, system-ui",
  "--radius-lg": "0.5rem",
  ...
}
```

## Step 2 — Apply the theme

Use `template_apply_theme` to land the token map into the tenant's `content_settings`:

```
# Dry-run first (template_apply_theme is safe-default gated)
template_apply_theme({
  theme_slug: "tailwind-imported",
  tokens:     {<the tokens.json contents>}
})
# → { dry_run: true, preview: {...}, confirm_token: "cft_..." }

# Confirm
template_apply_theme({
  theme_slug:    "tailwind-imported",
  tokens:        {<same>},
  confirm_token: "cft_..."
})
```

This becomes the active theme; every page references the same `--color-primary-500` etc.

## Step 3 — Identify unique sections in your HTML

A Tailwind HTML file is usually a sequence of `<section class="...">` blocks. Each section becomes a SpiderPublish component:

```html
<!-- pages/landing.html -->
<section class="bg-gradient-to-br from-primary-500 to-violet-600 py-24">
  <div class="max-w-4xl mx-auto text-center text-white">
    <h1 class="text-5xl font-bold">{{headline}}</h1>
    <p class="mt-4 text-xl opacity-90">{{subhead}}</p>
    <a class="mt-8 inline-block bg-white text-primary-600 rounded-lg px-8 py-4">{{cta_label}}</a>
  </div>
</section>

<section class="bg-gray-50 py-16">
  <!-- features grid -->
</section>
```

Group by visual identity:
- `tw-hero-gradient` — the section above
- `tw-features-grid` — the next section
- `tw-cta-band` — third section
- etc.

Each unique pattern = one component. Identical-looking sections across pages reuse the same component.

## Step 4 — Register each as a component

For each unique section, extract:
- `html_template` — the section HTML (with `{{...}}` Liquid placeholders for the dynamic bits)
- `css` — empty (Tailwind classes carry the styling)
- `props_schema` — JSON Schema for the placeholders (headline, subhead, cta_label, etc.)
- `default_props` — sensible defaults so the section renders standalone

```
content_create_component({
  slug: "tw-hero-gradient",
  category: "hero",
  html_template: "<section class=\"bg-gradient-to-br ...\">...</section>",
  css: "",
  props_schema: {
    type: "object",
    properties: {
      headline:  { type: "string" },
      subhead:   { type: "string" },
      cta_label: { type: "string" },
      cta_href:  { type: "string", format: "uri" }
    },
    required: ["headline", "cta_label", "cta_href"]
  },
  default_props: {
    headline:  "Your headline here",
    subhead:   "Your subhead here",
    cta_label: "Get started",
    cta_href:  "/signup"
  },
  agent_meta: {
    when_to_use: "Top of marketing pages where you want a gradient hero with a single CTA",
    when_not_to_use: "Anywhere needing a video or image background"
  }
})
```

## Step 5 — Assemble pages from registered components

```
content_create_page({
  slug: "landing",
  title: "Landing Page",
  template: "default",
  blocks: [
    {
      type: "component",
      component_slug: "tw-hero-gradient",
      props: { headline: "Real headline here", cta_label: "Sign up", cta_href: "/signup" }
    },
    { type: "component", component_slug: "tw-features-grid", props: {...} },
    { type: "component", component_slug: "tw-cta-band",      props: {...} }
  ]
})
```

## Step 6 — Tailwind CSS itself

The Tailwind utility classes need to be ON THE PAGE for the components to render right. Two options:

| Option | When | How |
|---|---|---|
| **CDN Tailwind** | Quick start, prototyping | Add `<script src="https://cdn.tailwindcss.com"></script>` to the template `<head>` via `template_upsert` |
| **Compiled Tailwind CSS** | Production | Run `tailwindcss -i src/input.css -o dist/output.css` → upload to SpiderMedia → `<link rel="stylesheet" href="<r2_url>">` in the template `<head>` |

CDN is fine for the first deploy; ship compiled CSS before going live so you don't fetch ~3 MB of Tailwind runtime on every page load.

## Step 7 — Deploy

Follow [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md):

```
content_deploy_readiness()
content_deploy_site_preview()
content_deploy_site_production({ confirm_token })
```

## Steps — full flow

```
1. (write + run scripts/tailwind-to-tokens.mjs)   — extract tokens
2. template_apply_theme({ tokens, ... })          — land the tokens
3. (audit HTML for unique sections)
4. content_create_component(...) × N              — register each unique section
5. content_create_page(...) × M                   — assemble pages
6. (upload Tailwind CSS to SpiderMedia OR add CDN script to template)
7. content_deploy_site_preview() → ...production() — push live
```

## Gotchas

- **Tailwind utility names ≠ SpiderPublish token names.** `bg-primary-500` (TW) → `var(--color-primary-500)` (SP). The token map handles values; the markup still references TW class names. Don't try to rewrite TW classes to CSS-var names — keep the markup as-is and ship Tailwind CSS.
- **Hand-rewriting Tailwind classes to CSS-vars breaks utility tooling.** If the next person opens the markup expecting Tailwind, they'll find half-rewritten CSS. Leave the classes; ship Tailwind CSS.
- **Tailwind `@apply` directives don't work** if you're shipping only the runtime CDN — they need build-time Tailwind. Compiled-CSS path required for `@apply` usage.
- **`tailwind.config.js` `content` paths** are meaningless in SpiderPublish (no build step). The extraction script ignores them. Tokens only.
- **Components with the same TW classes can still differ semantically.** Two hero sections with identical class strings might mean different things (one is a feature row, one is a hero); name them by INTENT not by classes.
- **Custom plugins (`@tailwindcss/typography`, custom utilities) won't extract cleanly.** Manual port for those: read the plugin source, add the resulting classes to the compiled CSS bundle.

## Verify

```
# After theme apply
template_get_config()
# → confirm the tokens you applied are in settings.theme_tokens

# After page deploy
content_visual_check({
  page_url: "https://<tenant>/<page-slug>",
  viewport: "desktop"
})
# → confirm Tailwind classes are rendering (look for the gradient hero in body_text_preview-adjacent fields)
```

## Anti-patterns

- **Trying to use SpiderClone for a Tailwind site you have source for.** SpiderClone scrapes the rendered output; you'd lose the original utility classes. If you have source, use this recipe.
- **Hand-translating every Tailwind class to inline CSS.** Defeats the purpose. Ship Tailwind CSS as a stylesheet; let the classes work.
- **Registering one component per section without grouping.** 40 sections might collapse to 8 unique patterns. Group by visual identity first.
- **Forgetting to ship the Tailwind CSS itself.** Page renders unstyled; classes are no-ops without the stylesheet.
- **Skipping `template_apply_theme` and relying on Tailwind's color palette.** SpiderPublish components elsewhere (forms, dashboards) read tokens from `--color-*`. Without applying them, those surfaces stay default-themed.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "import a tailwind site into SpiderPublish"
# Top-1 should be: recipes/clone/import-tailwind.md
```

## See also

- [`url-to-template.md`](url-to-template.md) — when you have a URL but no source code
- [`../content/import-tilda-site.md`](../content/import-tilda-site.md) — for inline-`<style>` legacy HTML (Tilda, Webflow exports)
- [`../content/apply-theme.md`](../content/apply-theme.md) — applying a pre-built theme (not from Tailwind)
- [`../components/create-component.md`](../components/create-component.md) — the component-registration primitive used in Step 4
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the gated `template_apply_theme` flow
