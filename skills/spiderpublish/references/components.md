# Components — author, find, update + propagate, rollback

Custom + library components live under `/api/v1/dashboard/content/components/...` (Bearer PAT).
A component is `html_template` + a separate `css` field (Shadow-DOM scoped — inline `<style>`
is dropped; see [`block-types.md`](block-types.md)). The two one-shots that matter:
`component_update_and_propagate` (edit + repoint every consuming page atomically) and
`component_rollback`. Deploy semantics: [`deploy-protocol.md`](deploy-protocol.md).

**Read when:** creating a reusable component, finding one by slug, propagating an edit to all
pages that use it, rolling a component back, or uploading a preview image for the gallery.


---

## Create Component

Author a new library component — Tier 1 static, Tier 2 interactive (vanilla JS), Tier 3 with CDN deps, or Tier 4 framework (React/Vue/Svelte) bundled via esbuild.

### When to use

- A tenant has a custom UI pattern that recurs across pages — pull it into a reusable component.
- You're adding marketplace assets (set `is_global: true` from the marketplace authoring brand `cli_spideriq_templates`).
- You need behaviour the bundled block types don't cover (animation, charts, framework-specific UI).

Pick the right Tier based on what the component does — see "The four tiers" below.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Decide the tier.** Wrong tier = wasted work. Tier 1 is the default; go higher only when you need to.
3. **(Tier 3 only)** Check `content_list_cdn_allowlist()` — your dep keys must be in the allowlist, or `content_create_component` 422s.
4. **(Tier 4 only)** Know the framework (`react` | `vue` | `svelte`). The build pipeline reads your `source_code` and produces an R2-hosted bundle.

### The four tiers

| Tier | `kind` | `js_runtime` | What you ship | Use for |
|---|---|---|---|---|
| **1 — Static** | `static` | none | `html_template` + `css` (no JS) | Hero, CTA, FAQ, pricing — anything purely presentational with props |
| **2 — Interactive** | `interactive` | vanilla | + `js` (scoped to shadow root) | Carousel, modal, accordion, hover-states — interactivity without external libs |
| **3 — Rich** | `interactive` | vanilla | + `dependencies[]` (allowlisted CDN libs) | GSAP scroll-sequences, Chart.js charts, leaflet maps — needs an external library |
| **4 — Framework** | `dynamic` | `react`/`vue`/`svelte` | + `framework` + `source_code` | Complex stateful components — chat widgets, admin panels, multi-step flows where vanilla JS becomes painful |

**Don't pick Tier 4 just because you know React.** Tier 1/2 handle 80% of cases with less overhead. Tier 4 means an esbuild round-trip per save, larger bundles, and the renderer pays an extra mount-time cost.

### Tier 1 — Static component

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
- **CSS in the separate `css` field, NEVER inline `<style>` in `html_template`.** Shadow DOM ignores inline styles — silent-no-render. (See [`../reference/block-types.md`](block-types.md#the-css-field-rule-for-components).)
- `props_schema` is JSON Schema. The renderer validates props against it at insert time (well — server-side via `page_insert_section`).
- `default_props` provides example values; the dashboard uses them as the initial props when a user inserts the component.
- `status` lands at `draft`. `content_publish_component` to flip to `published` (with dry_run gate).
- Phase 11+12 is **opt-in** on `content_create_component`. Pass `dry_run: true` for preview.

### Tier 2 — Interactive component (add `js`)

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

### Tier 3 — Rich component (CDN deps)

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

### Tier 4 — Framework component (React/Vue/Svelte)

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

### After create — publish + use

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

See [`../content/landing-page.md`](content.md#landing-page) for the page-authoring loop and [`../reference/block-types.md`](block-types.md) for the `type: "component"` block shape.

### Authoring hints (P5 — surfaced to other agents)

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

### Anti-patterns

1. **Inline `<style>` in `html_template`.** Shadow DOM ignores it. Use the `css` field.
2. **Picking Tier 4 because "React is easier."** Tier 1/2 covers 80% of components with no build step, no bundle hosting, no rebuild loop. Reach for Tier 4 only when state management or component composition gets painful.
3. **`dependencies: ["my-cool-lib"]` where the key isn't in `content_list_cdn_allowlist`.** 422. Either request the lib be added (separate ops process) or inline the JS in your `js` field.
4. **Setting `version: "<custom>"` outside of semver.** The component_propagation pipeline expects semver — bumps via `component_update_and_propagate` use `bump: patch|minor|major`. Custom versions break the bump logic.
5. **Making your component `is_global: true` without setting `marketplace_category` + `description` + `agent_meta`.** Global components show up in marketplace browsers; without metadata, agents can't discover them well. Set the marketplace fields if you're publishing globally.

### See also

- [`find-component.md`](components.md#find-component) — look up an existing component before authoring a near-duplicate
- [`update-and-propagate.md`](components.md#update-and-propagate) — update a component AND repoint every consuming page atomically
- [`rollback-component.md`](components.md#rollback-component) — undo a bad update
- [`../content/landing-page.md`](content.md#landing-page) — insert your component into a page block
- [`../reference/block-types.md`](block-types.md#the-css-field-rule-for-components) — the Shadow DOM rule
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*_component` tool family
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Find Component

Look up a component by slug — one call, no pagination. The "don't paginate" recipe.

### When to use

- You know (or strongly suspect) the slug of the component you want (`sys-hero-split`, `acme-pricing-table`, etc.).
- You're about to insert a component into a page block (`type: "component", component_slug: "..."`) and need its `props_schema` first.
- You want to verify a component exists + is published before depending on it.
- You're discovering what `component_version` is current.

If you don't know any slug + need to browse → see "Browsing when you don't know the slug" below.

### The 1-call path (when you know the slug)

```
content_get_component_by_slug({ slug: "sys-hero-split" })
// → {
//     id, slug, name, version: "1.2.0", kind: "static",
//     html_template, css, js,
//     props_schema: { type: "object", properties: {...}, required: [...] },
//     default_props,
//     dependencies: [],
//     description, category: "hero",
//     status: "published",
//     is_global: true,
//     ...
//   }
```

That's it. One call, returns the whole component including `props_schema` so you know what to pass when you insert.

**Optional version pin** — defaults to latest published:

```
content_get_component_by_slug({ slug: "sys-hero-split", version: "1.1.0" })
```

### Browsing when you don't know the slug

```
content_list_components({
  category: "hero",            # optional filter — one of: hero, cta, faq, pricing, features, testimonials, contact_form, footer, header, gallery, stats, custom
  status: "published",          # optional filter — typically "published" for usable components
  include_global: true,         # include the system-shipped `sys-*` components, not just your tenant's
  limit: 50                     # default 50; max effective ~200 before truncation
})
// → [
//   { id, slug: "sys-hero-split",     name: "Hero — split image+text", category: "hero", version: "1.2.0", status: "published", is_global: true },
//   { id, slug: "sys-hero-centered",  name: "Hero — centered", ... },
//   { id, slug: "acme-hero-portrait", name: "Acme portrait hero", is_global: false, ... }
// ]
```

`is_global: true` = shipped with the platform (system components, prefixed `sys-`). Available to every tenant.
`is_global: false` = your tenant authored it (or another tenant if it's been shared).

Filter chain:
- `category` narrows by domain.
- `include_global: false` if you only want your tenant's authored components.
- `status: "published"` excludes drafts.

Once you've found the right one, grab its `slug` and call `content_get_component_by_slug` for the full record.

### Components vs marketplace sections

There's a related-but-distinct tool: `content_list_marketplace_components` returns components flagged for the marketplace UI (`marketplace_featured`, `marketplace_category`, with thumbnails). Different surface — marketplace is the "browse + insert into a page" UX, while `content_list_components` is the lower-level catalog.

| Tool | Returns | When |
|---|---|---|
| `content_get_component_by_slug` | One component, fully populated | You know the slug |
| `content_list_components` | Tenant + global components catalog | Browsing without slug |
| `content_list_marketplace_components` | Components flagged for marketplace UI (`marketplace_featured`, thumbnails, categories) | Building a marketplace-style picker |
| `marketplace_search` | Free-text search across marketplace catalog | Natural-language discovery |

For agentic flows, `content_get_component_by_slug` is the high-value tool — one call, structured response, no pagination. The other three exist for browse + discovery surfaces.

### Pin a specific version

`content_get_component_by_slug` defaults to the latest published version. To pin:

```
content_get_component_by_slug({ slug: "sys-hero-split", version: "1.1.0" })
```

`content_list_component_versions({ slug })` returns the full version history:

```
content_list_component_versions({ slug: "sys-hero-split" })
// → [
//   { version: "1.2.0", published_at: "2026-05-...", changelog: "..." },
//   { version: "1.1.0", published_at: "2026-04-...", changelog: "..." },
//   { version: "1.0.0", published_at: "2026-03-...", changelog: "..." }
// ]
```

When you insert a component into a page block, you can pin the version:

```
{
  type: "component",
  component_slug: "sys-hero-split",
  component_version: "1.1.0",       // pin; omit for latest published
  data: { /* props per the schema */ }
}
```

Without `component_version`, the renderer uses latest published — meaning a future component update (via `component_update_and_propagate` with semver bump) will roll the page forward. Sometimes desirable, sometimes not — pin if you want stability.

### What you can do with the result

Once you have the component record:

- **Read `props_schema`** to know what `data: {...}` shape your `type: "component"` block should pass.
- **Read `default_props`** for example values.
- **Read `dependencies[]`** to know if the component is Tier 3 (needs allowlisted CDN libs). The renderer auto-injects from `content_cdn_allowlist`.
- **Read `kind`** to know whether the component is `static` / `interactive` / `dynamic` / `extension` — affects hydration.
- **Read `_audit`** (on get) for latent issues (Tier 3 with missing dep, etc).

### Anti-patterns

1. **Paginating `content_list_components({limit: 500})` to "find by slug."** Use `content_get_component_by_slug` — one call, faster, never truncated.
2. **Searching by `name`.** `content_list_components` doesn't filter by name; use `marketplace_search` for free-text, or `category` to narrow.
3. **Assuming `is_global: true` means "always available."** It is, in terms of read access — but you can't `content_publish_component` / `content_delete_component` on a global one unless you're the marketplace authoring brand (`cli_spideriq_templates`). Your tenant can use it; not edit it.
4. **Pinning `component_version` on a fast-evolving component.** If the component author pushes a critical fix, your pinned page misses it. Pin only when you've seen instability OR when you need bug-compatible behaviour.
5. **Inserting a Tier 3 component without checking `dependencies[]`.** The renderer fails silently in dev if a dep doesn't resolve. Check the result of `content_get_component_by_slug` includes `dependencies: ["gsap", ...]` AND each key is in `content_list_cdn_allowlist()`.

### See also

- [`create-component.md`](components.md#create-component) — author your own Tier 1-4 component
- [`../content/landing-page.md`](content.md#landing-page) — insert a component into a page block
- [`../reference/tool-surface.md`](tool-surface.md) — one-shot vs choreography (this recipe is the canonical "use the one-shot")
- [`../reference/block-types.md`](block-types.md) — `type: "component"` block shape (with top-level `component_slug`)
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Update And Propagate

Update a component's HTML/CSS/props AND roll the new version across every consuming page — **one tool call**.

### The one-shot path (preferred, v2.88.0+)

```
component_update_and_propagate(
  slug = "hero",
  css = <new css string>,
  dry_run = true
)
```

Returns a preview envelope with `affected_pages: [...]` and a `confirm_token`. Re-run with the token to apply:

```
component_update_and_propagate(
  slug = "hero",
  css = <same new css>,
  confirm_token = "cft_..."
)
```

The server does all of this in one transaction:

1. Fetches the current `hero` component, auto-bumps semver (default `patch`: `1.4.2` → `1.4.3`).
2. Inserts a new **published** row with the bumped version + your new content.
3. Queries every page whose `blocks` reference `component_slug: "hero"`.
4. UPDATEs each page's `blocks` JSONB to pin the new version on every matching block.
5. Returns `{component, affected_pages, unaffected_pages}`.

### No tenant deploy needed

Block-level page content renders live via the content API on the next request. Only run `content_deploy_site_preview` + `content_deploy_site_production` if you ALSO changed templates, theme, or config.

### Common variants

#### Staged rollout — update component everywhere, repoint only the home page

```
component_update_and_propagate(
  slug="hero",
  css=<new css>,
  pages=["home"],
  dry_run=true
)
```

Other pages keep their old version pin. Once you've verified the home page, call again with `pages` omitted to roll to all.

#### Minor / major version bump

```
component_update_and_propagate(
  slug="hero",
  props_schema=<new schema>,
  bump="minor",
  dry_run=true
)
```

Use `minor` for backward-compatible prop additions, `major` for contract breaks (default is `patch`).

#### Update multiple fields at once

```
component_update_and_propagate(
  slug="hero",
  html_template=<new html>,
  css=<new css>,
  props_schema=<new schema>,
  dependencies=["gsap"],
  dry_run=true
)
```

### Why not `component_update` + N `content_update_page` calls?

The legacy path:
1. PATCH `/components/{id}` with manually-bumped version
2. GET `/pages?has_component=hero` (doesn't exist; you paginate and filter client-side)
3. PATCH `/pages/{id}` per page, modifying its `blocks` JSONB
4. Each PATCH goes through its own Lock 4 confirm_token flow

`component_update_and_propagate` bundles this into one transaction with one confirm_token. Half-applied state is impossible — either everything lands or nothing does.

### Files in this skill

- `SKILL.md` — this file (human-readable recipe)
- `schema.yaml` — Tier 2 tool-sequence for MCP consumers

### See also

- [recipes/component-rollback](../SKILL.md) — undo a bad update using the same one-shot pattern
- [LEARNINGS.md → Component editing](../SKILL.md) — gotchas
- [SpiderIQ `/content/help` → `update_component_site_wide`](https://spideriq.ai/api/v1/content/help?format=yaml) — the canonical agent-facing description


---

## Rollback Component

Revert a component to an earlier version's content AND repoint every consuming page — **one tool call**.

### The one-shot path (v2.88.0+)

```
# First find the target version to roll back to
content_list_component_versions(slug="hero")
# → returns all versions with created_at + status

# Then roll back
component_rollback(
  slug="hero",
  target_version="1.4.0",
  dry_run=true
)
```

Returns a confirm_token. Re-run to apply:

```
component_rollback(
  slug="hero",
  target_version="1.4.0",
  confirm_token="cft_..."
)
```

### What happens server-side

The rollback never mutates history — it **creates a new forward version** that copies the target's content, then repoints consuming pages:

1. Fetches `hero@1.4.0` content (the known-good version).
2. Auto-bumps semver from CURRENT published version (so if current is `1.4.3` and bump is `patch`, new is `1.4.4`).
3. Inserts a new published row: `hero@1.4.4` with `1.4.0`'s content.
4. UPDATEs every page's blocks JSONB to pin `1.4.4`.
5. Returns `{component, rollback: {target_version: "1.4.0"}, affected_pages}`.

The audit trail stays intact — you can always see "v1.4.4 was a rollback of v1.4.0" in the component history.

### When to use this

- Your last `component_update_and_propagate` broke something
- A recent `component_update` introduced a regression you didn't catch before publish
- You want to A/B-compare an old version against the current one

### Common variants

#### Staged rollback — revert only one page first

```
component_rollback(
  slug="hero",
  target_version="1.4.0",
  pages=["home"],
  dry_run=true
)
```

Other pages keep their current (broken) pin. Verify the home page rollback works, then call again without `pages` to roll to all.

#### Fresh semver branch

```
component_rollback(
  slug="hero",
  target_version="1.4.0",
  bump="minor",  # → creates 1.5.0 instead of 1.4.4
  dry_run=true
)
```

Useful when you want a clean minor-version boundary that marks "rollback happened here."

### Gate action is distinct

A confirm_token issued for `component_rollback` CANNOT be consumed against `component_update_and_propagate` and vice versa. Lock 4 prevents cross-use — you can't accidentally apply a forward-update token to a rollback flow.

### No tenant deploy needed

Same as `component_update_and_propagate`: block-level page content renders live via the content API on next request. Run `content_deploy_site_preview` + `content_deploy_site_production` only if you ALSO changed templates/theme/config.

### Files in this skill

- `SKILL.md` — this file
- `schema.yaml` — Tier 2 tool-sequence for MCP consumers

### See also

- [recipes/component-update-and-propagate](../SKILL.md) — the forward flow
- [LEARNINGS.md → Component editing](../SKILL.md)
- [SpiderIQ `/content/help` → `rollback_component`](https://spideriq.ai/api/v1/content/help?format=yaml)


---

## Upload Component Preview

Upload a preview thumbnail (PNG/JPG/GIF/WEBP/MP4) for a component — reads the file from disk, uploads to R2, auto-PATCHes `preview_thumbnail_url`. The marketplace card art for component browsers.

### When to use

- You just authored a component and want to give it card art for the marketplace browser.
- You're improving discoverability — a component without a preview thumbnail is hard to find in a UI grid.
- You're rotating a thumbnail (rebrand, new screenshot).
- You're adding animated previews (MP4 loops showing the component's behaviour over time).

If you only need a static URL pointed at an already-uploaded image → just `content_update_component({ thumbnail_url: "https://..." })`. This recipe is for when the file is on your disk and you want one-call upload + PATCH.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Component exists** (got `component_id` from `content_create_component` or `content_get_component_by_slug`).
3. **File on disk, ≤5 MB.** Allowed extensions: `png`, `jpg`, `jpeg`, `gif`, `webp`, `mp4`. Server enforces the 5 MB cap.
4. **You own (or have edit access to) the component.** Global components (`is_global: true`) need super_admin / marketplace-authoring-brand PAT.

### The 1-call path

```
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./design/component-previews/sys-pretty-card.png"
})
// → {
//   success: true,
//   component_id: "comp_...",
//   url: "https://media.cdn.spideriq.ai/component-previews/<key>.png",
//   key: "component-previews/<key>.png",
//   size_bytes: 84221,
//   content_type: "image/png",
//   preview_thumbnail_url: "https://media.cdn.spideriq.ai/component-previews/<key>.png"
// }
```

That's it. The tool:
1. Reads the file from disk.
2. Sniffs content-type from extension (overrideable with `ext`).
3. POSTs multipart to `/content/components/{id}/upload-preview`.
4. Server uploads to R2.
5. Server PATCHes the component's `preview_thumbnail_url` to the R2 URL.
6. Returns the new URL.

One round-trip; no separate upload-then-patch.

### Params

| Field | Notes |
|---|---|
| `component_id` | REQUIRED. UUID from `content_create_component`. |
| `local_path` | REQUIRED. Absolute path or cwd-relative. Tool resolves; file must be readable. |
| `ext` | OPTIONAL. Override the extension/content-type. Default: extension from `local_path`. One of: `png`, `jpg`, `jpeg`, `gif`, `webp`, `mp4`. |
| `workspace` | OPTIONAL. Workspace name (default `"default"`). |

### File size + format constraints

| Format | Use for |
|---|---|
| **PNG** | Logos, icons, UI screenshots with transparency. Lossless. |
| **JPG/JPEG** | Photos, full-page screenshots. Lossy but smaller. |
| **WEBP** | Same shape as JPG but ~30% smaller. Preferred for thumbnails when supported. |
| **GIF** | Short animations (looping). Larger than equivalent MP4. |
| **MP4** | Animated previews. The CRO catalog uses MP4 to show behaviour (popup fires, bar slides in). |

5 MB cap is server-enforced. For animated MP4 over 5 MB:
- Compress more (try CRF 28-30 with H.264).
- OR use SpiderMedia upload directly (`upload_local_file`) and PATCH `preview_thumbnail_url` manually with the returned URL.

### Typical use — Tier 1-3 component preview

After authoring a component ([`create-component.md`](components.md#create-component)):

```
# 1. Create the component
content_create_component({
  slug: "sys-pretty-card",
  name: "Pretty card",
  html_template: "<div>...</div>",
  css: "...",
  props_schema: { ... }
})
# → { id: "comp_..." }

# 2. Take a screenshot of the rendered component (use the dashboard's preview pane, or render locally)

# 3. Upload the preview
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./previews/sys-pretty-card.png"
})
# → component now has preview_thumbnail_url

# 4. (For marketplace components) set additional marketplace metadata
content_update_component({
  component_id: "comp_...",
  marketplace_category: "custom",
  marketplace_featured: false,
  marketplace_description: "A pretty content card with optional CTA",
  authoring_hints: {
    preferred_path: "Pass title + body via props; optional cta object",
    must_set: ["title", "body"]
  }
})

# 5. Publish (so it appears in marketplace browsers)
content_publish_component({ component_id: "comp_..." })
content_publish_component({ component_id: "comp_...", confirm_token })
```

### Animated MP4 previews (the CRO pattern)

CRO components animate their behaviour for discovery. A static thumbnail of `sys-popup-exit-intent` is just "a popup card"; an MP4 shows the modal sliding in when the cursor leaves.

To author an animated MP4 preview:

1. Record the component in action (browser, screen recorder, OBS, etc.).
2. Trim to 3-6 seconds. Loop-friendly first/last frame.
3. Encode H.264 / web-compatible MP4 at 720p or smaller. Aim for <3 MB.
4. Upload:

```
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./previews/sys-popup-exit-intent.mp4",
  ext:          "mp4"
})
```

The marketplace browser detects MP4 and auto-loops/auto-mutes the playback. Visitors hover/scroll to the card; the preview plays.

### Replace an existing preview

Same call, new file:

```
content_upload_component_preview({
  component_id: "comp_...",
  local_path:   "./previews/sys-pretty-card-v2.png"
})
# → preview_thumbnail_url is now the new R2 URL
```

The old preview file stays in R2 (not auto-deleted; no orphan cleanup yet). If you need to remove it: SpiderMedia's `delete_file({ key })` with the old key from the prior response.

### Remove a preview entirely

There's no first-party "delete preview" tool today. Two options:

1. **Re-PATCH `preview_thumbnail_url` to `null`** via `content_update_component({ component_id, thumbnail_url: null })`.
2. **Upload a placeholder** (a transparent 1x1 PNG or a "no preview available" image) to keep visual consistency in the marketplace browser.

Option 1 lands a card without a thumbnail (the browser usually renders a generic placeholder). Option 2 keeps the card visually consistent.

### Verify

Open the marketplace browser (dashboard's marketplace page) and find your component — the new thumbnail should render. OR:

```
content_get_component_by_slug({ slug: "sys-pretty-card" })
# Check preview_thumbnail_url is the new R2 URL.
```

Visit the URL directly to confirm the file uploaded:

```bash
curl -I https://media.cdn.spideriq.ai/component-previews/<key>.png
# HTTP/2 200, content-type: image/png
```

### Anti-patterns

1. **File >5 MB.** Server-rejected. Compress or use SpiderMedia direct upload + manual PATCH.
2. **Wrong extension.** `local_path: "./preview.heic"` → not in allowlist → 422. Convert to PNG/JPG first.
3. **Forgetting to set `marketplace_*` fields** when publishing a component to the marketplace. The preview shows but other browse filters (`marketplace_category`, `is_featured`, `marketplace_description`) won't surface it. See [`../marketplace/browse-cro-components.md`](marketplace.md#browse-cro-components).
4. **Animated MP4 longer than 8s or larger than 3 MB.** Marketplace browser auto-plays — long clips eat bandwidth, large files slow the page. Aim for 3-6s, ≤3 MB.
5. **Static screenshot of a CRO component that's all about animation.** Visitors don't get the behavioural signal. Use MP4 for animated/triggered components.
6. **Uploading a preview for a draft component thinking it'll go live with the next publish.** Preview thumbnail is independent of component status — it's updated immediately. Publishing the component just flips status; the preview is already in place.

### See also

- [`create-component.md`](components.md#create-component) — author the component before adding preview
- [`find-component.md`](components.md#find-component) — `content_get_component_by_slug` to confirm preview persisted
- [`../marketplace/browse-cro-components.md`](marketplace.md#browse-cro-components) — where the previews surface
- [`../marketplace/author-bg-video.md`](marketplace.md#author-bg-video) — similar pattern for bg-video assets
- [`../reference/tool-surface.md`](tool-surface.md) — `content_upload_component_preview` signature
- catalog/CLAUDE.md → Marketplace Admin Slice 1 — the upload endpoint shipped 2026-04-28
