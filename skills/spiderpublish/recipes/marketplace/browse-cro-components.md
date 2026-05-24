# recipes/marketplace/browse-cro-components

Browse the SpiderPublish CRO catalog (urgency, scarcity, social proof, capture popups, sticky bars, timers, agent-native GEO primitives) and insert a component into a page. Each component animates its own preview so you (and the agent) can pick by behaviour, not by name.

## When to use

- A tenant's landing page converts at 2% and they need conversion-rate-optimization (CRO) primitives: scarcity timer, sticky CTA bar, exit-intent popup, social-proof toast.
- You're shipping a launch page and need to bundle urgency cues without authoring components from scratch.
- An agent is composing a high-conversion page and needs the catalog of pre-built "gimmicks" rather than inventing them.
- You want **agent-native (GEO) primitives** — Markdown-mirror, contextual menu, schema injector — so LLM-class agents see structured content alongside the visual page.

If you want a generic component browse (heros, features, pricing — non-CRO) → use `content_list_marketplace_components({category: "hero" | ...})`. If you want to author a NEW CRO component → [`../components/create-component.md`](../components/create-component.md). If you want to manage marketplace assets as a super_admin → [`author-site-template.md`](author-site-template.md) / [`author-bg-video.md`](author-bg-video.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **A page exists to insert into.** `content_create_page` first if not (see [`../content/landing-page.md`](../content/landing-page.md)). The CRO catalog is BROWSE + INSERT — there's nothing to do without a target page.

## The CRO catalog — by behaviour

The catalog ships ~30+ `sys-*` components across these behavioural classes. Each component name maps to one observable user-visible behaviour; the dashboard's marketplace browser animates the preview so you can see it before inserting.

### Urgency + scarcity (timers, low-stock, deadlines)

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-timer-fixed-date` | Countdown to a specific datetime (e.g. "Sale ends 31 Dec midnight UTC") | On every render; rolls negative after target |
| `sys-timer-v2-components` | Composable timer pieces (days / hours / minutes / seconds) for custom layouts | Same |
| `sys-bar-sticky-promo` | Top-of-page sticky bar with countdown OR dismissible offer | On page load; persistent until dismissed |

### Social proof (toasts, marquees, viewer counts)

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-proof-recent-sales-toast` | Bottom-corner toast: "Someone in <city> just bought X" | Periodic during scroll; ~5-10s intervals |
| `sys-proof-live-viewers-pulse` | "12 people viewing now" badge with pulse animation | Periodic refresh |
| `sys-proof-trending-now` | "Trending now" pill on featured items | On render |
| `sys-press-marquee` | Horizontal-scrolling press logos ("As seen in: NYT, TechCrunch…") | Continuous animation |
| `sys-headline-marquee-trust` | Headline-style marquee with trust signals | Same |
| `sys-quotes-hover-spotlight` | Testimonial grid; hover reveals full quote | On hover |

### Trust signals (badges, uptime)

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-trust-badges-strip` | Horizontal strip of trust badges (SSL, payment processors, awards) | On render |
| `sys-trust-uptime-status` | Live status indicator with link to status page | Periodic refresh from status URL |
| `sys-guarantee-badge-floating` | Floating "30-day money-back" seal | Persistent during scroll |

### Capture popups + sticky CTAs

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-popup-exit-intent` | Modal that fires when cursor moves toward browser chrome (exit intent) | `mouseleave` toward top edge; once per cookie window |
| `sys-popup-geo-discount` (+ v110 variant) | Modal that fires based on visitor's geolocation (IP-based) | On page load if geo matches; once per cookie window |
| `sys-bar-sticky-cta-mobile` | Mobile-only bottom sticky CTA bar | On scroll past N% on mobile breakpoint |
| `sys-form-2step-optin` | Two-step opt-in form (email → confirm) — works as inline AND as popup variant | Inline on render OR popup on trigger |

### Scroll-triggered behaviours

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-scroll-progress-bar` | Top-of-page progress bar showing % scrolled | Continuous on scroll |
| `sys-stats-counter-on-scroll` | Stat numbers that count up when the section enters viewport | IntersectionObserver |

### Agent-native (GEO) primitives

These exist specifically so LLM-class agents see structured content alongside the visual page. Underused by humans; critical for AI-driven discovery.

| Slug | What it does | Where it lives |
|---|---|---|
| `sys-geo-md-mirror` | Mirrors the page's visual content into a Markdown blob at `/<path>.md` or in a `<noscript>` block | Hidden from visitors; visible to LLMs |
| `sys-geo-contextual-menu` | Renders a `<nav>` with semantic anchor links per section | In-DOM; aids screen readers + LLMs |
| `sys-geo-schema-injector` | Injects per-page schema.org JSON-LD (`Product`, `Article`, `FAQPage`, etc.) into `<head>` | Visitors don't see; Google + LLMs parse |

### Page-level form components (different from `kind='form'` iframe embed)

These render the form **inline on the page server-side** — no cross-origin iframe, no `kind='form'` flow_id. Simpler shape; props.fields[]; for static lead-capture rather than conversational flows.

| Slug | What it does |
|---|---|
| `sys-form-2step-optin` | Email → confirm two-step capture |
| `sys-form-multistep-funnel` | Multi-step page-level funnel (no /f/<id> URL) |
| `sys-form-newsletter-inline` | Inline newsletter signup |

For **conversational** forms (welcome screens, logic, branching) → use `kind='form'` flow + `kind='form'`'s `/f/<flow_id>` URL OR the page-block embed pattern in [`../booking/form-as-page-section.md`](../booking/form-as-page-section.md). The `sys-form-*` components above are SEPARATE — page-level static forms with no conversational layer.

## The 3-call path

```
1. content_list_marketplace_components({ category: "capture" | "social-proof" | ... })
   OR marketplace_search({ q: "exit-intent popup with email capture", ... })
2. content_get_component_by_slug({ slug: "sys-popup-exit-intent" })   # inspect props_schema
3. page_insert_section({ page_id, component_slug, props })            # dry_run + confirm
```

### 1. Discover — by category or by intent

**By category** (when you know the lane):

```
content_list_marketplace_components({
  category: "capture",            # forms-shaped components — sys-form-*, sys-popup-*
  is_featured: true               # surface featured-only
})
# Other CRO-shaped categories: social-proof, cta, header, footer
```

Returns slug + name + version + props_schema + default_props + preview_thumbnail_url + marketplace_description. The preview thumbnail in the dashboard animates the component's behaviour.

**By intent** (when you want semantic discovery):

```
marketplace_search({
  q: "exit-intent popup with email capture for a luxury hotel",
  mood: "calm",
  scene_type: "data-collection-form"
})
```

`marketplace_search` cross-searches bg-videos / components / site-templates by AI-discovery axes: `mood` (calm, energetic, bold, …), `palette`, `brand_fit`, `scene_type`. Much smarter than category filters when the agent has a natural-language intent — picks `sys-popup-exit-intent` AND `sys-form-2step-optin` AND a calm-palette bg-video, not just one.

### 2. Inspect the component

```
content_get_component_by_slug({ slug: "sys-popup-exit-intent" })
// → {
//   slug, name, version, kind: "interactive", js_runtime: "vanilla",
//   html_template, css, js,
//   props_schema: {
//     type: "object",
//     properties: {
//       headline: { type: "string", default: "Wait! Don't go yet." },
//       offer_text: { type: "string", default: "Get 10% off your first order." },
//       cta_label: { type: "string", default: "Claim discount" },
//       cookie_window_hours: { type: "integer", default: 168 }    # 7d; popup won't re-fire within window
//     }
//   },
//   default_props: { ... },
//   dependencies: [],
//   agent_meta: { trigger_kind: "exit_intent", scene_type: "capture-popup" },
//   ...
// }
```

Read the `props_schema` — those are the knobs you can twist when inserting. Read `agent_meta.trigger_kind` for popups/bars to know WHEN the component fires (`exit_intent`, `scroll_percent`, `time_on_page`, `manual`).

### 3. Insert into a page

```
# Step 3a — dry_run preview
page_insert_section({
  page_id: "<page-uuid>",
  component_slug: "sys-popup-exit-intent",
  props: {
    headline:    "Hold on — get 15% off",
    offer_text:  "Sign up to our newsletter for an instant 15% discount.",
    cta_label:   "Get 15% off",
    cookie_window_hours: 72   # re-fire after 3 days
  },
  position: "end",            # CRO popups typically don't need precise positioning
  dry_run: true
})
// → { dry_run: true, preview: { insertion_index, new_block_id, blocks_count_before/after }, confirm_token, _rules }

# Step 3b — confirm
page_insert_section({
  page_id: "<page-uuid>",
  component_slug: "sys-popup-exit-intent",
  props: { ... same as dry_run ... },
  confirm_token: "cft_..."
})
// → { inserted: true, block_id: "blk_...", _audit: { errors: [], warnings: [] } }
```

The new block is `type: "component"` with the slug + props. The page is NOT republished — call `content_publish_page` after if needed (gate is dry_run-default). For non-published pages, the block is in the draft already.

### Deploy (when you're done inserting)

```
content_deploy_readiness()
content_deploy_site_preview()                    # eyeball preview URL
content_deploy_site_production({ confirm_token }) # ~2-5s live
```

For CRO components: ALWAYS preview before production. The "felt experience" of an exit-intent popup or sticky bar is very different from looking at code — it might be too aggressive (firing immediately), it might overlap the footer on small viewports, it might compete with another component you forgot was on the page.

## Composition — combine CRO components for stack effects

CRO works best when components compose. Common stacks:

| Page type | Stack |
|---|---|
| E-commerce product | `sys-trust-badges-strip` + `sys-proof-recent-sales-toast` + `sys-timer-fixed-date` + `sys-popup-exit-intent` |
| SaaS landing | `sys-press-marquee` + `sys-form-2step-optin` + `sys-bar-sticky-cta-mobile` + `sys-popup-exit-intent` |
| Lead-gen | `sys-form-multistep-funnel` + `sys-trust-uptime-status` + `sys-stats-counter-on-scroll` |
| Agent-discoverable | Any of the above + `sys-geo-md-mirror` + `sys-geo-schema-injector` (zero visible cost, big LLM-visibility win) |

Each component is independent — they don't communicate. Insert them one at a time via `page_insert_section`.

## The GEO primitives — why they matter

LLM-class agents (Claude, GPT-4o, Perplexity) increasingly scrape web pages to answer questions. Visual components — heroes, animations, scroll-triggered counters — are often invisible or noisy to them. The GEO primitives close the gap:

- `sys-geo-md-mirror` exposes a clean Markdown render of your page at `/<path>.md`. LLMs prefer Markdown over HTML.
- `sys-geo-schema-injector` adds schema.org JSON-LD that LLMs (and Google) parse natively for entity extraction.
- `sys-geo-contextual-menu` adds anchor-link navigation in semantic `<nav>` — LLMs use it to summarize the page structure.

Add these to every published page. They cost ~0 in render time, ~0 in visual layout, and meaningfully improve LLM-driven discovery. Catalog/CLAUDE.md → "Agent-native primitives" for the framing.

## Verify

```
content_visual_check({
  page_url: "https://<tenant>/<page-slug>",
  viewport: "desktop"
})
```

For most CRO components: check `screenshot_url` shows the component visually. For popups + bars with `trigger_kind: 'exit_intent'`, the screenshot won't capture the popup (it hasn't fired) — verify in a browser by moving cursor toward the URL bar.

For forms inside a page-level component (`sys-form-*`): the form renders inline server-side, so `body_text_preview` SHOULD contain the form labels. Different from `kind='form'` flow embed (cross-origin iframe = opaque).

## Anti-patterns

1. **Adding 8 CRO components to one page.** Conversion uplift plateaus; cognitive overload kicks in. Pick 2-4 that compose well for the page's intent.
2. **Setting `cookie_window_hours: 0` on a popup.** Popup re-fires on every page load including back-button — visitor rage-quits. Default 168h (7 days) for exit-intent; 24h for geo-discount.
3. **Combining `sys-bar-sticky-promo` AND `sys-bar-sticky-cta-mobile` on the same page.** Both bind to top/bottom — they fight for viewport. Pick one.
4. **Using `sys-form-newsletter-inline` for a multi-field lead-gen form.** It's email-only. Use `sys-form-multistep-funnel` OR `kind='form'` flow + `/f/<id>` embed for multi-field.
5. **Skipping the GEO primitives because "the page looks the same."** That's the point — they're invisible to visitors, critical for LLMs/Google. Free conversion uplift on AI-driven traffic.
6. **Composing `/book/<flow_id>` URLs from CRO components.** None of the `sys-*` CRO components use `flow_id` — they're standalone page-level components. The `/book/<id>` anti-pattern only applies to conversational forms (see Rule 62 / W13).

## See also

- [`../booking/form-as-page-section.md`](../booking/form-as-page-section.md) — conversational `kind='form'` flow embedded as a page block (different surface; uses iframe)
- [`../booking/build-form.md`](../booking/build-form.md) — author a conversational form from scratch
- [`browse-and-insert-section.md`](browse-and-insert-section.md) — generic marketplace browse (heros, features, non-CRO)
- [`../content/landing-page.md`](../content/landing-page.md) — page authoring before inserting CRO
- [`../components/find-component.md`](../components/find-component.md) — `content_get_component_by_slug` deep-dive
- [`../components/create-component.md`](../components/create-component.md) — author your own CRO component
- [`suggest-agent-meta.md`](suggest-agent-meta.md) — LLM-suggest mood / palette / scene_type for marketplace assets
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `marketplace_*` tool catalog
- catalog/CLAUDE.md → "Marketplace V2 agent surface" — internal spec
