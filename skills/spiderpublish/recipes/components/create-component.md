# recipes/components/create-component

Author a new library component — Tier 1 static, Tier 2 interactive (vanilla JS), Tier 3 with CDN deps, or Tier 4 framework (React/Vue/Svelte) bundled via esbuild.

## When to use

- A tenant has a custom UI pattern that recurs across pages — pull it into a reusable component.
- You're adding marketplace assets (set `is_global: true` from the marketplace authoring brand `cli_spideriq_templates`).
- You need behaviour the bundled block types don't cover (animation, charts, framework-specific UI).

Pick the right Tier based on what the component does — see "The four tiers" below.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Decide the tier.** Wrong tier = wasted work. Tier 1 is the default; go higher only when you need to.
3. **(Tier 3 only)** Check `content_list_cdn_allowlist()` — your dep keys must be in the allowlist, or `content_create_component` 422s.
4. **(Tier 4 only)** Know the framework (`react` | `vue` | `svelte`). The build pipeline reads your `source_code` and produces an R2-hosted bundle.

## The four tiers

| Tier | `kind` | `js_runtime` | What you ship | Use for |
|---|---|---|---|---|
| **1 — Static** | `static` | none | `html_template` + `css` (no JS) | Hero, CTA, FAQ, pricing — anything purely presentational with props |
| **2 — Interactive** | `interactive` | vanilla | + `js` (scoped to shadow root) | Carousel, modal, accordion, hover-states — interactivity without external libs |
| **3 — Rich** | `interactive` | vanilla | + `dependencies[]` (allowlisted CDN libs) | GSAP scroll-sequences, Chart.js charts, leaflet maps — needs an external library |
| **4 — Framework** | `dynamic` | `react`/`vue`/`svelte` | + `framework` + `source_code` | Complex stateful components — chat widgets, admin panels, multi-step flows where vanilla JS becomes painful |

**Don't pick Tier 4 just because you know React.** Tier 1/2 handle 80% of cases with less overhead. Tier 4 means an esbuild round-trip per save, larger bundles, and the renderer pays an extra mount-time cost.

## Tier 1 — Static component

```
content_create_component({
  slug:  "sys-pretty-card",
  name:  "Pretty card",
  category: "custom",
  html_template: `
<div class="card">
  <h3>{{ title }}</h3>
  <p>{{ body }}</p>
  {% if cta %}<a href="{{ cta.url }}" class="cta">{{ cta.label }}</a>{% endif %}
</div>`,
  css: `
.card { padding: 2rem; border-radius: 12px; background: var(--surface); }
.card h3 { font-size: 1.25rem; margin: 0 0 0.5rem; }
.card p { color: var(--neutral-400); margin: 0; }
.cta { display: inline-block; margin-top: 1rem; padding: 0.5rem 1rem; background: var(--primary); color: var(--primary-contrast); border-radius: 8px; text-decoration: none; }
`,
  props_schema: {
    type: "object",
    properties: {
      title: { type: "string", description: "Card title" },
      body:  { type: "string", description: "Card body text" },
      cta: {
        type: "object",
        properties: {
          label: { type: "string" },
          url:   { type: "string" }
        }
      }
    },
    required: ["title", "body"]
  },
  default_props: {
    title: "A pretty card",
    body:  "With a body and an optional CTA.",
    cta:   { label: "Learn more", url: "/about" }
  },
  description: "Generic content card with optional CTA. Tier 1 — pure props in, HTML out.",
  version: "1.0.0",
  tags: ["card", "content"]
})
// → { id: "comp_...", slug: "sys-pretty-card", status: "draft", version: "1.0.0" }
```

**Key rules:**

- `slug`, `name`, `html_template` are REQUIRED.
- **CSS in the separate `css` field, NEVER inline `<style>` in `html_template`.** Shadow DOM ignores inline styles — silent-no-render. (See [`../reference/block-types.md`](../reference/block-types.md#the-css-field-rule-for-components).)
- `props_schema` is JSON Schema. The renderer validates props against it at insert time (well — server-side via `page_insert_section`).
- `default_props` provides example values; the dashboard uses them as the initial props when a user inserts the component.
- `status` lands at `draft`. `content_publish_component` to flip to `published` (with dry_run gate).
- Phase 11+12 is **opt-in** on `content_create_component`. Pass `dry_run: true` for preview.

## Tier 2 — Interactive component (add `js`)

```
content_create_component({
  slug:  "click-counter",
  name:  "Click counter",
  category: "custom",
  html_template: `
<div class="counter">
  <p>You clicked <span class="count">0</span> times.</p>
  <button class="btn">Click me</button>
</div>`,
  css: `
.counter { padding: 2rem; }
.btn { background: var(--primary); color: var(--primary-contrast); border: none; padding: 0.5rem 1rem; border-radius: 8px; cursor: pointer; }
`,
  js: `
// Function receives (root, props). `root` is the shadowRoot.
function init(root, props) {
  let count = 0;
  const span = root.querySelector('.count');
  const btn  = root.querySelector('.btn');
  btn.addEventListener('click', () => {
    count += 1;
    span.textContent = count;
  });
}
init(root, props);
`,
  props_schema: { type: "object", properties: {} }
})
```

The `js` field is executed inside the shadow root with `root` (the `shadowRoot`) and `props` in scope. No `document.querySelector` — use `root.querySelector` to avoid leaking selectors into the host page.

## Tier 3 — Rich component (CDN deps)

```
# First — check what's allowlisted
content_list_cdn_allowlist()
// → [
//   { key: "gsap",                name: "GSAP",                url: "https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js" },
//   { key: "gsap/ScrollTrigger",  name: "GSAP ScrollTrigger",  url: "..." },
//   { key: "chartjs",             name: "Chart.js",            url: "https://cdn.jsdelivr.net/npm/chart.js@4.4.6/dist/chart.umd.min.js" },
//   ...
// ]

content_create_component({
  slug:  "scroll-fade-card",
  name:  "Scroll-fade card",
  category: "custom",
  html_template: `<div class="card">{{ body }}</div>`,
  css: `.card { opacity: 0; transition: opacity 0.5s; }`,
  js: `
// At hydration time, window.gsap + window.ScrollTrigger are already loaded
// (the renderer's hydration-runner waits for declared deps before invoking init).
gsap.registerPlugin(ScrollTrigger);
const card = root.querySelector('.card');
ScrollTrigger.create({
  trigger: card, start: "top 80%",
  onEnter: () => gsap.to(card, { opacity: 1 })
});
`,
  dependencies: ["gsap", "gsap/ScrollTrigger"],
  props_schema: { type: "object", properties: { body: { type: "string" } } }
})
```

**Tier 3 caveats:**

- Every key in `dependencies[]` must be in `content_list_cdn_allowlist`. The endpoint 422s on unknown keys.
- The renderer injects `<script async src="...">` for each dep in `<head>`. The hydration runner polls `window.<global>` before invoking your `js`. (See `apps/liquid-renderer/src/hydration-runner.ts` — `DEP_TO_GLOBAL` map.)
- Bundle cost: each dep is fetched by the visitor's browser once per session, browser-cached at the CDN edge. Don't add deps "just in case" — every one adds a network round-trip on first paint.

## Tier 4 — Framework component (React/Vue/Svelte)

```
content_create_component({
  slug:  "react-chat-widget",
  name:  "Chat widget (React)",
  category: "custom",
  framework: "react",
  source_code: `
import React, { useState } from 'react';

export default function ChatWidget({ greeting }) {
  const [messages, setMessages] = useState([{ from: "bot", text: greeting }]);
  return (
    <div className="chat">
      {messages.map((m, i) => <div key={i} className={m.from}>{m.text}</div>)}
    </div>
  );
}
`,
  html_template: `<div data-react-mount></div>`,  // mount point inside shadow root
  css: `.chat { padding: 1rem; } .bot { color: var(--neutral-400); }`,
  props_schema: {
    type: "object",
    properties: { greeting: { type: "string", default: "Hi!" } }
  }
})
// → { id: "comp_...", build_status: "queued", ... }
# Poll for build:
content_get_build_status({ component_id: "comp_..." })
// → { build_status: "succeeded", bundle_url: "https://media.spideriq.ai/component-bundles/<slug>@<version>.mjs" }
```

The pipeline: server reads `source_code` → esbuild bundles → uploads to R2 → updates `bundle_url` on the row → flips `build_status` to `succeeded`.

**Tier 4 caveats:**

- Initial build takes 5-30s. Poll `content_get_build_status` until `build_status: "succeeded"`. On `"failed"`, read `build_error`.
- Re-build on every code change: `content_rebuild_component({ component_id })` triggers a fresh build.
- Bundle size matters — the renderer ships the bundle as a `<script type="module">` per page render. Heavy bundles hurt first-paint.

## After create — publish + use

```
content_publish_component({ component_id: "comp_..." })
// → defaults to dry_run=true
content_publish_component({ component_id: "comp_...", confirm_token: "cft_..." })
// → { status: "published", version: "1.0.0" }
```

Now insert into a page block:

```
content_update_page({
  page_id: "<page-uuid>",
  blocks: [
    ...,
    {
      id: "blk_custom",
      type: "component",
      component_slug: "sys-pretty-card",
      data: { title: "Hello", body: "World" }
    }
  ]
})
```

See [`../content/landing-page.md`](../content/landing-page.md) for the page-authoring loop and [`../reference/block-types.md`](../reference/block-types.md) for the `type: "component"` block shape.

## Authoring hints (P5 — surfaced to other agents)

Help future agents avoid mistakes:

```
content_create_component({
  ...,
  authoring_hints: {
    preferred_path: "Use video_to_scroll_sequence MCP tool, not manual insert",
    common_mistakes: [
      "Setting data.frames manually — use the SpiderVideo pipeline instead",
      "Mounting <video> tags in html_template — use the canvas-based pipeline"
    ],
    must_set: ["frame_count", "frame_url_template"],
    must_not_set: ["mounted", "current_frame"]   // managed internally
  }
})
```

When another agent inserts your component, these hints appear on the `_rules` envelope alongside the dry_run preview. Codified per Rule 60.

## Anti-patterns

1. **Inline `<style>` in `html_template`.** Shadow DOM ignores it. Use the `css` field.
2. **Picking Tier 4 because "React is easier."** Tier 1/2 covers 80% of components with no build step, no bundle hosting, no rebuild loop. Reach for Tier 4 only when state management or component composition gets painful.
3. **`dependencies: ["my-cool-lib"]` where the key isn't in `content_list_cdn_allowlist`.** 422. Either request the lib be added (separate ops process) or inline the JS in your `js` field.
4. **Setting `version: "<custom>"` outside of semver.** The component_propagation pipeline expects semver — bumps via `component_update_and_propagate` use `bump: patch|minor|major`. Custom versions break the bump logic.
5. **Making your component `is_global: true` without setting `marketplace_category` + `description` + `agent_meta`.** Global components show up in marketplace browsers; without metadata, agents can't discover them well. Set the marketplace fields if you're publishing globally.

## See also

- [`find-component.md`](find-component.md) — look up an existing component before authoring a near-duplicate
- [`update-and-propagate.md`](update-and-propagate.md) — update a component AND repoint every consuming page atomically
- [`rollback-component.md`](rollback-component.md) — undo a bad update
- [`../content/landing-page.md`](../content/landing-page.md) — insert your component into a page block
- [`../reference/block-types.md`](../reference/block-types.md#the-css-field-rule-for-components) — the Shadow DOM rule
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*_component` tool family
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
