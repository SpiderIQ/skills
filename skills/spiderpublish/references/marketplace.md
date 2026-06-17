# Marketplace — browse + insert sections, author templates, background videos, agent-meta

The SpiderPublish marketplace serves curated sections, site templates, and background videos.
Browsing is a public read (`/api/v1/content/...` and the `dashboard_site_templates` /
`dashboard_bg_videos` listing endpoints); authoring a curated asset is an admin/dashboard write.
Inserting a section into a page uses `page_insert_section` against
`/api/v1/dashboard/projects/{pid}/content/pages/{page_id}/insert-section`.

**Read when:** browsing and inserting a marketplace section, browsing CRO components, authoring a
site template or a background video for the gallery, picking a background video, or writing the
`agent_meta` block that makes an asset agent-discoverable.


---

## Browse And Insert Section

Find marketplace assets by intent (mood / palette / brand-fit / scene), then insert one into a page — agent-discovery flow shipped 2026-05-05.

The classic flow `content_list_marketplace_components` filters by `category` (hero, features, pricing, …). The new `marketplace_search` filters by **what an agent actually wants** — "calm cinematic for a luxury hotel," "energetic conversion-focused for ecommerce" — across all 3 marketplace tables (bg-videos / components / site-templates) in one query.

### Quick ask: "find a calm bg-video and use it as hero on the homepage"

```
marketplace_search(
  mood = ["calm"],
  asset_types = ["bg_video"],
  limit = 5
)
# → results: [{ slug: "alpine-wildflowers", asset_type: "bg_video",
#               video_url: "https://media.cdn.spideriq.ai/bg-videos/alpine-wildflowers.mp4",
#               mood: ["calm","dreamy"], scene_type: "nature-landscape", ... }, ...]

content_insert_section(
  page_id = "<homepage uuid>",
  component_slug = "sys-bg-video",
  props = { video_slug: "alpine-wildflowers" },
  position = "start"
)
# → preview envelope with confirm_token

content_insert_section(
  page_id = "<homepage uuid>",
  component_slug = "sys-bg-video",
  props = { video_slug: "alpine-wildflowers" },
  position = "start",
  confirm_token = "<from previous>"
)
# → block inserted; page persists in draft until you publish + deploy
```

Runnable end-to-end (with auth + page lookup): `examples/marketplace-search-and-insert.sh`.

### Why search by intent?

Categories tell you the **shape** ("it's a hero"); they don't tell you whether the hero matches a luxury hotel brief or a fintech dashboard brief. The 4 universal axes do:

| Axis | Vocabulary (subset) | Picks |
|---|---|---|
| `mood` | calm, energetic, bold, dreamy, futuristic, urban, minimal, warm, editorial, professional, friendly, clear, technical, credible | The emotional register |
| `palette` | monochrome, deep-blue, cream, neutral-warm, nature-green, neon-accent, cinematic | The visual signature |
| `brand_fit_tags` | saas, agency, ecommerce, fintech, hospitality, restaurant, wellness, blog, publication, real-estate, … | The industry vertical |
| `scene_type` | hero-bold, conversion-cta, social-proof (components); city-aerial, nature-landscape (bg-videos); marketing-site, docs-site (site-templates) | The semantic shape |

`marketplace_search` matches **any-of** within an axis ("mood includes calm OR editorial") and **and-of** across axes ("calm-mood AND saas-brand-fit"). For tighter narrowing, pass single values per axis.

### Per-asset agent_meta

Beyond the 4 universal axes, each table has its own JSONB `agent_meta` with extra filters:

```
# Calm bg-video, slow pace, night scene, no people
marketplace_search(
  mood = ["calm"],
  asset_types = ["bg_video"],
  agent_meta = { pace: "slow", time_of_day: "night", has_people: false }
)
```

The full vocabulary lives in `template_get_help` (or `GET /content/help`) — search for `BgVideoAgentMeta` / `ComponentAgentMeta` / `SiteTemplateAgentMeta`.

### Anti-patterns

- **Don't bind `idap.lead` to a List block** — it's a singleton (`is_collection=false`); only Item Details accepts it.
- **Don't pass `mood` as a comma-string in the JSON body** — it's `string[]`. The CLI accepts `--mood calm,editorial`, the API expects `["calm","editorial"]`.
- **`agent_meta` is `extra="forbid"`** — typos return 422. Use `template_get_help` if a key isn't in the table above.
- **Universal axes are NOT inside `agent_meta`** — `mood` / `palette` / `brand_fit_tags` / `scene_type` are sibling top-level fields. Putting them inside `agent_meta` silently no-ops.

### See also

- [recipes/component-update-and-propagate](components.md#update-and-propagate) — when you want to edit one component everywhere it's used
- [tool-surface.md — full tool catalog](tool-surface.md) — full tool catalog including `content_insert_section`


---

## Browse CRO Components

Browse the SpiderPublish CRO catalog (urgency, scarcity, social proof, capture popups, sticky bars, timers, agent-native GEO primitives) and insert a component into a page. Each component animates its own preview so you (and the agent) can pick by behaviour, not by name.

### When to use

- A tenant's landing page converts at 2% and they need conversion-rate-optimization (CRO) primitives: scarcity timer, sticky CTA bar, exit-intent popup, social-proof toast.
- You're shipping a launch page and need to bundle urgency cues without authoring components from scratch.
- An agent is composing a high-conversion page and needs the catalog of pre-built "gimmicks" rather than inventing them.
- You want **agent-native (GEO) primitives** — Markdown-mirror, contextual menu, schema injector — so LLM-class agents see structured content alongside the visual page.

If you want a generic component browse (heros, features, pricing — non-CRO) → use `content_list_marketplace_components({category: "hero" | ...})`. If you want to author a NEW CRO component → [`../components/create-component.md`](components.md#create-component). If you want to manage marketplace assets as a super_admin → [`author-site-template.md`](marketplace.md#author-site-template) / [`author-bg-video.md`](marketplace.md#author-bg-video).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **A page exists to insert into.** `content_create_page` first if not (see [`../content/landing-page.md`](content.md#landing-page)). The CRO catalog is BROWSE + INSERT — there's nothing to do without a target page.

### The CRO catalog — by behaviour

The catalog ships ~30+ `sys-*` components across these behavioural classes. Each component name maps to one observable user-visible behaviour; the dashboard's marketplace browser animates the preview so you can see it before inserting.

#### Urgency + scarcity (timers, low-stock, deadlines)

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-timer-fixed-date` | Countdown to a specific datetime (e.g. "Sale ends 31 Dec midnight UTC") | On every render; rolls negative after target |
| `sys-timer-v2-components` | Composable timer pieces (days / hours / minutes / seconds) for custom layouts | Same |
| `sys-bar-sticky-promo` | Top-of-page sticky bar with countdown OR dismissible offer | On page load; persistent until dismissed |

#### Social proof (toasts, marquees, viewer counts)

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-proof-recent-sales-toast` | Bottom-corner toast: "Someone in <city> just bought X" | Periodic during scroll; ~5-10s intervals |
| `sys-proof-live-viewers-pulse` | "12 people viewing now" badge with pulse animation | Periodic refresh |
| `sys-proof-trending-now` | "Trending now" pill on featured items | On render |
| `sys-press-marquee` | Horizontal-scrolling press logos ("As seen in: NYT, TechCrunch…") | Continuous animation |
| `sys-headline-marquee-trust` | Headline-style marquee with trust signals | Same |
| `sys-quotes-hover-spotlight` | Testimonial grid; hover reveals full quote | On hover |

#### Trust signals (badges, uptime)

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-trust-badges-strip` | Horizontal strip of trust badges (SSL, payment processors, awards) | On render |
| `sys-trust-uptime-status` | Live status indicator with link to status page | Periodic refresh from status URL |
| `sys-guarantee-badge-floating` | Floating "30-day money-back" seal | Persistent during scroll |

#### Capture popups + sticky CTAs

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-popup-exit-intent` | Modal that fires when cursor moves toward browser chrome (exit intent) | `mouseleave` toward top edge; once per cookie window |
| `sys-popup-geo-discount` (+ v110 variant) | Modal that fires based on visitor's geolocation (IP-based) | On page load if geo matches; once per cookie window |
| `sys-bar-sticky-cta-mobile` | Mobile-only bottom sticky CTA bar | On scroll past N% on mobile breakpoint |
| `sys-form-2step-optin` | Two-step opt-in form (email → confirm) — works as inline AND as popup variant | Inline on render OR popup on trigger |

#### Scroll-triggered behaviours

| Slug | What it does | Trigger / fires |
|---|---|---|
| `sys-scroll-progress-bar` | Top-of-page progress bar showing % scrolled | Continuous on scroll |
| `sys-stats-counter-on-scroll` | Stat numbers that count up when the section enters viewport | IntersectionObserver |

#### Agent-native (GEO) primitives

These exist specifically so LLM-class agents see structured content alongside the visual page. Underused by humans; critical for AI-driven discovery.

| Slug | What it does | Where it lives |
|---|---|---|
| `sys-geo-md-mirror` | Mirrors the page's visual content into a Markdown blob at `/<path>.md` or in a `<noscript>` block | Hidden from visitors; visible to LLMs |
| `sys-geo-contextual-menu` | Renders a `<nav>` with semantic anchor links per section | In-DOM; aids screen readers + LLMs |
| `sys-geo-schema-injector` | Injects per-page schema.org JSON-LD (`Product`, `Article`, `FAQPage`, etc.) into `<head>` | Visitors don't see; Google + LLMs parse |

#### Page-level form components (different from `kind='form'` iframe embed)

These render the form **inline on the page server-side** — no cross-origin iframe, no `kind='form'` flow_id. Simpler shape; props.fields[]; for static lead-capture rather than conversational flows.

| Slug | What it does |
|---|---|
| `sys-form-2step-optin` | Email → confirm two-step capture |
| `sys-form-multistep-funnel` | Multi-step page-level funnel (no /f/<id> URL) |
| `sys-form-newsletter-inline` | Inline newsletter signup |

For **conversational** forms (welcome screens, logic, branching) → use `kind='form'` flow + `kind='form'`'s `/f/<flow_id>` URL OR the page-block embed pattern in [`../booking/form-as-page-section.md`](forms-booking.md#form-as-page-section). The `sys-form-*` components above are SEPARATE — page-level static forms with no conversational layer.

### The 3-call path

```
1. content_list_marketplace_components({ category: "capture" | "social-proof" | ... })
   OR marketplace_search({ q: "exit-intent popup with email capture", ... })
2. content_get_component_by_slug({ slug: "sys-popup-exit-intent" })   # inspect props_schema
3. page_insert_section({ page_id, component_slug, props })            # dry_run + confirm
```

#### 1. Discover — by category or by intent

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

#### 2. Inspect the component

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

#### 3. Insert into a page

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

#### Deploy (when you're done inserting)

```
content_deploy_readiness()
content_deploy_site_preview()                    # eyeball preview URL
content_deploy_site_production({ confirm_token }) # ~2-5s live
```

For CRO components: ALWAYS preview before production. The "felt experience" of an exit-intent popup or sticky bar is very different from looking at code — it might be too aggressive (firing immediately), it might overlap the footer on small viewports, it might compete with another component you forgot was on the page.

### Composition — combine CRO components for stack effects

CRO works best when components compose. Common stacks:

| Page type | Stack |
|---|---|
| E-commerce product | `sys-trust-badges-strip` + `sys-proof-recent-sales-toast` + `sys-timer-fixed-date` + `sys-popup-exit-intent` |
| SaaS landing | `sys-press-marquee` + `sys-form-2step-optin` + `sys-bar-sticky-cta-mobile` + `sys-popup-exit-intent` |
| Lead-gen | `sys-form-multistep-funnel` + `sys-trust-uptime-status` + `sys-stats-counter-on-scroll` |
| Agent-discoverable | Any of the above + `sys-geo-md-mirror` + `sys-geo-schema-injector` (zero visible cost, big LLM-visibility win) |

Each component is independent — they don't communicate. Insert them one at a time via `page_insert_section`.

### The GEO primitives — why they matter

LLM-class agents (Claude, GPT-4o, Perplexity) increasingly scrape web pages to answer questions. Visual components — heroes, animations, scroll-triggered counters — are often invisible or noisy to them. The GEO primitives close the gap:

- `sys-geo-md-mirror` exposes a clean Markdown render of your page at `/<path>.md`. LLMs prefer Markdown over HTML.
- `sys-geo-schema-injector` adds schema.org JSON-LD that LLMs (and Google) parse natively for entity extraction.
- `sys-geo-contextual-menu` adds anchor-link navigation in semantic `<nav>` — LLMs use it to summarize the page structure.

Add these to every published page. They cost ~0 in render time, ~0 in visual layout, and meaningfully improve LLM-driven discovery. Catalog/CLAUDE.md → "Agent-native primitives" for the framing.

### Verify

```
content_visual_check({
  page_url: "https://<tenant>/<page-slug>",
  viewport: "desktop"
})
```

For most CRO components: check `screenshot_url` shows the component visually. For popups + bars with `trigger_kind: 'exit_intent'`, the screenshot won't capture the popup (it hasn't fired) — verify in a browser by moving cursor toward the URL bar.

For forms inside a page-level component (`sys-form-*`): the form renders inline server-side, so `body_text_preview` SHOULD contain the form labels. Different from `kind='form'` flow embed (cross-origin iframe = opaque).

### Anti-patterns

1. **Adding 8 CRO components to one page.** Conversion uplift plateaus; cognitive overload kicks in. Pick 2-4 that compose well for the page's intent.
2. **Setting `cookie_window_hours: 0` on a popup.** Popup re-fires on every page load including back-button — visitor rage-quits. Default 168h (7 days) for exit-intent; 24h for geo-discount.
3. **Combining `sys-bar-sticky-promo` AND `sys-bar-sticky-cta-mobile` on the same page.** Both bind to top/bottom — they fight for viewport. Pick one.
4. **Using `sys-form-newsletter-inline` for a multi-field lead-gen form.** It's email-only. Use `sys-form-multistep-funnel` OR `kind='form'` flow + `/f/<id>` embed for multi-field.
5. **Skipping the GEO primitives because "the page looks the same."** That's the point — they're invisible to visitors, critical for LLMs/Google. Free conversion uplift on AI-driven traffic.
6. **Composing `/book/<flow_id>` URLs from CRO components.** None of the `sys-*` CRO components use `flow_id` — they're standalone page-level components. The `/book/<id>` anti-pattern only applies to conversational forms (see Rule 62 / W13).

### See also

- [`../booking/form-as-page-section.md`](forms-booking.md#form-as-page-section) — conversational `kind='form'` flow embedded as a page block (different surface; uses iframe)
- [`../booking/build-form.md`](forms-booking.md#build-form) — author a conversational form from scratch
- [`browse-and-insert-section.md`](marketplace.md#browse-and-insert-section) — generic marketplace browse (heros, features, non-CRO)
- [`../content/landing-page.md`](content.md#landing-page) — page authoring before inserting CRO
- [`../components/find-component.md`](components.md#find-component) — `content_get_component_by_slug` deep-dive
- [`../components/create-component.md`](components.md#create-component) — author your own CRO component
- [`suggest-agent-meta.md`](marketplace.md#suggest-agent-meta) — LLM-suggest mood / palette / scene_type for marketplace assets
- [`../reference/tool-surface.md`](tool-surface.md) — `marketplace_*` tool catalog
- catalog/CLAUDE.md → "Marketplace V2 agent surface" — internal spec


---

## Author Site Template

Publish a curated starter site to the marketplace catalog so other tenants can `content_apply_site_template({slug})` to clone it. Super-admin / marketplace-authoring-brand operation.

### When to use

- You're on the SpiderIQ team curating new starters for the catalog (restaurant, SaaS, agency, lawyer, …).
- You've built a polished example site in the **marketplace authoring tenant** (`cli_spideriq_templates` — the canonical brand for marketplace-authored assets) and want to promote it to the global catalog.
- You're shipping an industry-pack with 3-5 paired starters.

If you want to APPLY an existing template to a tenant → [`../content/apply-site-template.md`](templates-deploy.md#apply-site-template). If you want to clone the marketplace authoring tenant's UI patterns into a specific tenant → use that recipe, not this one. If you're authoring a single component (not a whole site) → [`../components/create-component.md`](components.md#create-component) + [`../components/upload-component-preview.md`](components.md#upload-component-preview).

### Prerequisites

1. **PAT scope is super_admin OR brand_admin of `cli_spideriq_templates`.** The marketplace authoring tenant is the canonical brand for `is_global: true` assets. Other PATs get 403 on the create-template endpoint.
2. **Source pages exist + are published** in the marketplace authoring tenant. The template clones from THESE.
3. **Preview image ready** — PNG/JPG/WEBP of the rendered site (typically a homepage screenshot or composite). ≤5 MB.
4. **Tenant scope verified** + bound to the authoring tenant. Run `./scripts/verify-tenant-scope.sh`.

### The 5-call path

```
1. (in authoring tenant) build the source pages — landing-page.md / blog-post.md / etc.
2. content_upload_site_template_preview   — upload the preview image to R2
3. (REST) POST /content/site-templates    — create the catalog row              # VERIFY tool name
4. content_get_site_template               — confirm shape
5. (across other tenants) content_apply_site_template — confirms it works end-to-end
```

**Resolved 2026-05-24 — product gap flagged:** the upload-preview MCP tool exists (`content_upload_site_template_preview`), and `next_step` strings in content.ts reference `content_create_site_template` / `content_update_site_template` as if they were registered. They are NOT — the catalog-row CRUD is REST-only via `POST /api/v1/dashboard/projects/{pid}/content/site-templates` and `PATCH .../{slug}` (files: [`app/api/v1/dashboard_site_templates.py:177`](https://github.com/SpiderIQ/SpiderIQ/blob/master/app/api/v1/dashboard_site_templates.py#L177), `:232`). Tracked for an MCP-wrapper PR; the `next_step` strings in content.ts also need updating once the wrappers land.

#### Step 1 — build the source pages

In the marketplace authoring tenant (NOT the tenant the template will be applied to), build the pages exactly as you want them to land for downstream tenants:

```
# In cli_spideriq_templates context
content_create_page({ title: "Home", slug: "home", template: "default", blocks: [...] })
content_create_page({ title: "Menu", slug: "menu", template: "default", blocks: [...] })
content_create_page({ title: "About", slug: "about", ... })
content_create_page({ title: "Reservations", slug: "reservations", ... })
content_create_page({ title: "Contact", slug: "contact", ... })

# Publish all of them
content_publish_page({ page_id: ..., confirm_token: ... }) for each

# Set the nav menus
content_update_navigation({ location: "header", items: [...] })
content_update_navigation({ location: "footer", items: [...] })

# Set the theme settings (the whitelisted keys that get copied)
content_update_settings({
  settings: {
    primary_color:    "#8B4513",
    body_text_color:  "#1c1917",
    site_name:        "Trattoria Italiana",      # used as default; downstream tenants override
    logo_url:         "https://media.spideriq.ai/templates/trattoria/logo.svg"
  }
})
```

The source tenant's current state at template-publish-time is what gets cloned. Iterate until the source site is the canonical example.

#### Step 2 — upload the preview image

```
content_upload_site_template_preview({
  slug:       "trattoria-italiana",                  # used as both the R2 key stem AND the path segment
  local_path: "./templates/trattoria-italiana/preview.png"
})
// → { url: "https://media.cdn.spideriq.ai/templates/trattoria-italiana.png", key, size_bytes, content_type }
```

5 MB cap; PNG/JPG/JPEG/GIF/WEBP allowed. The preview image is what shows in the marketplace browser card.

**Important:** this tool only uploads to R2 — it does NOT PATCH the catalog row. You'll set `preview_thumbnail_url` to the returned URL in the next step.

#### Step 3 — create the catalog row

REST only as of 2026-05-24. No MCP wrapper for create/update; use the REST path below. (Upload-preview IS exposed via `content_upload_site_template_preview`.)

```bash
curl -X POST "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/site-templates" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "slug":                    "trattoria-italiana",
    "name":                    "Trattoria Italiana — restaurant starter",
    "description":             "Menu / About / Contact / Reservations starter with rustic warm palette. Mobile-first.",
    "industry":                "restaurant",
    "use_case":                "small-business",
    "tags":                    ["restaurant", "italian", "small-business", "warm-palette"],
    "preview_url":             "https://acme-templates.spideriq.ai/",
    "preview_thumbnail_url":   "https://media.cdn.spideriq.ai/templates/trattoria-italiana.png",
    "is_featured":             false,
    "source_page_slugs":       ["home", "menu", "about", "reservations", "contact"],
    "source_nav_locations":    ["header", "footer"],
    "source_settings_keys":    ["primary_color", "body_text_color", "site_name", "logo_url"],
    "source_component_slugs":  [],
    "agent_meta": {
      "mood":           "warm",
      "palette":        "earth-tone",
      "brand_fit_tags": ["small-business", "hospitality"],
      "scene_type":     "restaurant"
    }
  }'
# → 201 Created { template_id, slug, ... }
```

| Field | Notes |
|---|---|
| `slug` | URL-safe identifier. Stable handle for `content_apply_site_template`. |
| `name` | Display name in marketplace browsers. |
| `description` | Markdown-allowed. Shown on the catalog card. |
| `industry` / `use_case` | Filter dimensions for `content_list_site_templates`. |
| `tags[]` | Free-form. Surfaces in `content_list_site_templates({ tag })`. |
| `preview_url` | Live URL of the actual rendered example (the authoring tenant's primary domain). |
| `preview_thumbnail_url` | The image from Step 2. |
| `source_page_slugs[]` | The pages in the authoring tenant that get cloned on apply. ORDER matters — first slug is typically `home`. |
| `source_nav_locations[]` | Which nav menus get copied. Typically `header` + `footer`; `docs_sidebar` for doc-shaped templates. |
| `source_settings_keys[]` | Whitelisted theme keys that copy. **Never include secrets** (analytics_id, webhook URLs, encrypted keys). |
| `source_component_slugs[]` | If the template depends on tenant-authored components (vs `is_global` ones), list them so the apply tool can clone those too. Usually empty. |
| `agent_meta` | AI-discovery axes (mood / palette / brand_fit / scene_type) — for `marketplace_search` semantic queries. See catalog/CLAUDE.md → marketplace_taxonomy. |
| `is_featured` | Promote in the catalog. Curated decision; not for self-promotion. |

As of 2026-05-24, the REST create endpoint is NOT Phase 11+12 gated — single POST creates the catalog row. This is intentional for super_admin authoring flows (low-frequency, high-trust). If the gate is added later, the same recipe applies with a `dry_run=true` → `confirm_token` round-trip prepended.

#### Step 4 — confirm the catalog row landed

```
content_get_site_template({ slug: "trattoria-italiana" })
// → full record including the source_page_blocks (what visitors will see on apply)
```

Read it back. Confirm `preview_thumbnail_url` is the right R2 URL, `source_page_slugs` lists what you expect.

#### Step 5 — apply to a test tenant (end-to-end smoke)

In a test tenant (NOT the authoring tenant):

```
# Apply
content_apply_site_template({ slug: "trattoria-italiana", dry_run: true })
content_apply_site_template({ slug: "trattoria-italiana", confirm_token })

# Publish + deploy
# (per the standard publish + deploy flow)

# Visual-check the home page
content_visual_check({ page_url: "https://<test-tenant>/", viewport: "desktop" })
```

If the test tenant's deployed version looks like your authoring tenant's source pages → success. If not, debug + iterate on the source pages, then re-publish the template (PATCH the catalog row to point at the latest source state).

### Update an existing template

Templates aren't versioned by default — re-running create with the same slug 409s. To update:

```bash
# PATCH the catalog row
curl -X PATCH "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/site-templates/<slug>" \
  -H "Authorization: Bearer ..." \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Updated copy...",
    "is_featured": true
  }'
```

If you changed the SOURCE PAGES in the authoring tenant, downstream tenants who APPLIED earlier WON'T auto-update — the apply was a one-time clone. To roll forward, downstream tenants need to re-apply (which creates NEW drafts; the old applied pages are preserved separately).

### Versioning approach (for major changes)

For breaking changes to the template shape:

1. Don't update the existing slug.
2. Create a new slug (e.g. `trattoria-italiana-v2`).
3. Mark the old slug `is_featured: false` + add a description note ("Superseded by trattoria-italiana-v2").
4. Promote the new slug in `is_featured`.

This way, downstream tenants who applied v1 are stable; new tenants see v2.

### Anti-patterns

1. **Authoring directly in a customer's tenant + promoting from there.** Settings + content bleeds across tenants. Always author in `cli_spideriq_templates` (the canonical marketplace authoring brand).
2. **Including secrets in `source_settings_keys`.** `analytics_id`, `webhook_*`, encrypted keys → leak to every downstream tenant. Only include public + brand keys.
3. **Listing 30+ pages in `source_page_slugs`.** Apply becomes a heavy mutation (30 page creates + nav updates + settings merge). Aim for the minimum viable starter — 5-10 pages.
4. **Forgetting to set `agent_meta`.** `marketplace_search` is the high-leverage discovery surface; without `mood` / `palette` / `scene_type`, agents can't find your template semantically. ALWAYS set it.
5. **Skipping the end-to-end smoke (Step 5).** Bugs in the source pages bake into every apply. Test in a throwaway tenant before promoting.
6. **Using `is_featured: true` for your own template right after publishing.** Curation decision — leave to the SpiderIQ team to promote based on quality + downstream traction.

### See also

- [`../content/apply-site-template.md`](templates-deploy.md#apply-site-template) — the downstream apply flow (what the catalog row enables)
- [`../components/create-component.md`](components.md#create-component) — author a component (different shape — components are slot-in pieces; site templates are whole sites)
- [`../components/upload-component-preview.md`](components.md#upload-component-preview) — sibling pattern for component card art
- [`author-bg-video.md`](marketplace.md#author-bg-video) — author a bg-video catalog row (parallel marketplace asset type)
- [`suggest-agent-meta.md`](marketplace.md#suggest-agent-meta) — LLM-suggest the agent_meta axes
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*_site_template` tool catalog
- catalog/CLAUDE.md → "Marketplace Admin Slice 1" — backend internals


---

## Author BG Video

Publish a curated background-video clip to the marketplace bg-video catalog. Super-admin / marketplace-authoring-brand operation. Visitors pair the clip with a `sys-bg-video` component for hero / section backgrounds.

### When to use

- You're on the SpiderIQ team adding clips to the bg-video gallery.
- A new clip is ready (MP4 ≤50 MB, with a JPG/PNG poster fallback for autoplay-blocked viewers).
- You're rotating the featured set or marking some clips deprecated.

If you want to USE an existing bg-video on a page → use the `sys-bg-video` component via `page_insert_section` (see [`browse-cro-components.md`](marketplace.md#browse-cro-components)). If you're authoring a site template → [`author-site-template.md`](marketplace.md#author-site-template).

### Prerequisites

1. **PAT scope is super_admin OR brand_admin of `cli_spideriq_templates`.** Other PATs 403 on the create endpoint.
2. **MP4 file ≤50 MB.** Compressed; H.264 encoding; web-compatible.
3. **JPG/PNG poster image.** Used as fallback when autoplay is blocked (mobile Safari, data-saver, low-power mode).
4. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh`; bound to the authoring tenant.

### The 4-call path

```
1. content_upload_bg_video       — upload MP4 to R2
2. content_upload_bg_video       — upload poster JPG (same tool, different file)
3. (REST) POST /content/bg-videos — create the catalog row                   # VERIFY tool name
4. content_get_marketplace_bg_video — confirm shape
```

**Resolved 2026-05-24 — product gap flagged:** the upload tool exists (`content_upload_bg_video` at [`packages/mcp-tools/src/publish/content.ts:1663`](https://github.com/SpiderIQ/SpiderIQ/blob/master/packages/mcp-tools/src/publish/content.ts#L1663)) but `content_create_bg_video` and `content_update_bg_video` are **referenced in `next_step` hints** without being registered as actual MCP tools. The catalog-row CRUD is REST-only via `POST /api/v1/dashboard/projects/{pid}/content/bg-videos` and `PATCH .../{slug}` (files: [`app/api/v1/dashboard_bg_videos.py:188`](https://github.com/SpiderIQ/SpiderIQ/blob/master/app/api/v1/dashboard_bg_videos.py#L188), `:239`). Tracked for an MCP-wrapper PR.

#### Step 1 — upload the MP4

```
content_upload_bg_video({
  slug:       "ocean-sunrise-loop",         # R2 key stem: bg-videos/ocean-sunrise-loop.mp4
  local_path: "./bg-videos/ocean-sunrise.mp4"
})
// → {
//   url:          "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.mp4",
//   key:          "bg-videos/ocean-sunrise-loop.mp4",
//   size_bytes:   24_315_881,
//   content_type: "video/mp4"
// }
```

50 MB server-enforced cap. Tool sniffs content-type from `.mp4` extension.

**For 3-8 second background loops:**

| Setting | Target |
|---|---|
| Duration | 3-8 seconds (longer = more bandwidth, no behavioural benefit) |
| Resolution | 1920×1080 (downscales fine on mobile) |
| Codec | H.264 baseline / main profile |
| Bitrate | 2-5 Mbps |
| File size | <5 MB ideally; ≤50 MB hard cap |
| Audio | NONE (autoplay requires muted; remove audio track) |

Recommended encode command:
```bash
ffmpeg -i input.mov \
  -c:v libx264 -profile:v main -preset slow -crf 23 \
  -vf "scale=1920:-2,fps=24" \
  -an \                                     # drop audio
  -movflags +faststart \                    # web-optimized
  -t 6 \                                    # trim to 6s
  output.mp4
```

#### Step 2 — upload the poster

```
content_upload_bg_video({
  slug:       "ocean-sunrise-loop",         # SAME slug — overwrites R2 key with different extension
  local_path: "./bg-videos/ocean-sunrise-poster.jpg",
  ext:        "jpg"
})
// → { url: "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.jpg", ... }
```

The poster IS the first/representative frame of the video, used when autoplay is blocked (mobile Safari / data-saver / low-power mode). Without a poster, viewers see a black box instead.

Same `slug` — R2 key differs by extension. The catalog row references BOTH URLs.

#### Step 3 — create the catalog row

REST only as of 2026-05-24. No MCP wrapper for create/update; use the REST path below.

```bash
curl -X POST "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/bg-videos" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "slug":             "ocean-sunrise-loop",
    "name":             "Ocean sunrise — calm loop",
    "description":      "Wide aerial of ocean at sunrise. Calm waves; warm orange palette. Perfect for hotel / spa / wellness heros.",
    "video_url":        "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.mp4",
    "poster_url":       "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.jpg",
    "category":         "nature",
    "duration_seconds": 6,
    "loop_seconds":     6,
    "tags":             ["ocean", "sunrise", "calm", "warm", "aerial"],
    "is_featured":      false,
    "replication_prompt": "Aerial drone footage of ocean at sunrise, warm orange palette, calm waves, slow camera pan. No people, no objects.",
    "agent_meta": {
      "mood":           "calm",
      "palette":        "warm",
      "brand_fit_tags": ["hotel", "spa", "wellness"],
      "scene_type":     "hero-bg-video"
    }
  }'
# → 201 Created
```

| Field | Notes |
|---|---|
| `slug` | URL-safe identifier. Stable handle. |
| `name` | Display name in the marketplace browser. |
| `description` | Markdown-allowed. |
| `video_url` | R2 URL from Step 1 (MP4). Strict-allowlisted to R2 hosts post-2026-05-12. |
| `poster_url` | R2 URL from Step 2 (poster image). Same allowlist. |
| `category` | One of: `nature | city | abstract | food | tech | people`. The 6 catalog dimensions. |
| `duration_seconds` | Real duration. Used by the renderer to set `<video duration>`. |
| `loop_seconds` | Loop point — typically equals duration. Lets the renderer fade-cut at a clean boundary. |
| `tags[]` | Free-form. Surfaces in `content_list_marketplace_bg_videos({ tag })`. |
| `is_featured` | Promote in the catalog. Curated decision. |
| `replication_prompt` | TEXT-TO-VIDEO prompt that would produce this clip. For Sora/Veo/Runway agents to remix. Optional but high-leverage. |
| `agent_meta.{mood, palette, brand_fit_tags, scene_type}` | AI-discovery axes for `marketplace_search`. ALWAYS set. |

#### Step 4 — confirm + smoke

```
content_get_marketplace_bg_video({ slug: "ocean-sunrise-loop" })
# → full record
```

Smoke-test in a test tenant by pairing with `sys-bg-video`:

```
# In a test tenant
page_insert_section({
  page_id:        "<test-page>",
  component_slug: "sys-bg-video",
  props: {
    video_url:  "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.mp4",
    poster_url: "https://media.cdn.spideriq.ai/bg-videos/ocean-sunrise-loop.jpg",
    overlay_opacity: 0.3,
    headline:   "Welcome"
  }
})
```

Deploy, visual-check:

```
content_visual_check({ page_url: "https://<test-tenant>/", viewport: "desktop" })
# Check screenshot shows the hero with poster (first frame) visible.
```

Open in an actual browser to see the loop play (visual-check captures the first paint; doesn't wait for video playback).

### Update / rotate

To replace the MP4 (e.g. better-encoded version):

```
content_upload_bg_video({ slug: "ocean-sunrise-loop", local_path: "./v2/ocean-sunrise.mp4" })
# Same R2 key, overwrites
```

R2 overwrites are atomic; visitors stop seeing the old version on next cache TTL.

To deprecate a clip:

```bash
# PATCH the catalog row
curl -X PATCH "https://spideriq.ai/api/v1/dashboard/projects/$AUTHORING_PID/content/bg-videos/<slug>" \
  -H "Authorization: Bearer ..." \
  -d '{ "is_featured": false, "tags": ["deprecated", ...] }'
```

There's no "delete" today; un-feature + add deprecated tag is the soft path. Hard delete via REST `DELETE /content/bg-videos/<slug>` exists but breaks any tenant currently using the slug.

### Anti-patterns

1. **Uploading with audio track intact.** Autoplay requires `muted` to fire (browser policy). With audio, autoplay silently fails on most browsers. ALWAYS strip audio in encoding (`-an` flag).
2. **Skipping the poster.** Mobile Safari + data-saver viewers see a black box. ALWAYS upload + reference a poster.
3. **MP4 > 5 MB for a 6-second clip.** Visitors pay the bandwidth on every page load. Compress harder (CRF 25-28; lower resolution; shorter duration).
4. **Forgetting `agent_meta`.** `marketplace_search` is the high-leverage discovery surface. Without `mood` / `palette` / `scene_type`, agents looking for "calm ocean for a spa site" won't find your clip.
5. **Authoring in a customer tenant.** Always `cli_spideriq_templates` for marketplace-authored assets.
6. **Setting `is_featured: true` on your own upload.** Curation decision — leave to the SpiderIQ team based on quality + downstream usage.
7. **Reusing a slug across categories.** Slugs are unique. `ocean-sunrise-loop` in category `nature` can't also exist in `abstract`. Different slug per asset.

### See also

- [`browse-cro-components.md`](marketplace.md#browse-cro-components) — `sys-bg-video` component that consumes bg-videos
- [`author-site-template.md`](marketplace.md#author-site-template) — sibling marketplace authoring pattern (site templates instead of bg-videos)
- [`pick-bg-video.md`](#) — downstream: a tenant browses + picks a bg-video (queued v0.5.0)
- [`suggest-agent-meta.md`](marketplace.md#suggest-agent-meta) — LLM-suggest the agent_meta axes
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*_bg_video` tool catalog
- catalog/CLAUDE.md → "Marketplace Admin Slice 1" — backend internals


---

## Pick BG Video

Browse the curated background-video library (12 short loops across 6 categories) and pair the chosen clip with a `sys-bg-video` component on a page — in one preview-then-confirm flow via `page_insert_section`.

### When to use

- Adding a cinematic hero with a looping background video without sourcing/encoding/uploading your own clip.
- Building a section with a `sys-bg-video` block where you don't yet have an asset.
- Surfacing the catalog on a dashboard "browse bg videos" picker.
- Pattern: "I want one of those looping hero videos but I haven't picked which."

### Prerequisites

- A PAT scoped to the tenant.
- A target page (`page_id`) where you want to insert the section.
- The `sys-bg-video` component published in the marketplace (it is — it ships in every tenant via the global components catalog).

### Step 1 — Browse the catalog

```
content_list_marketplace_bg_videos({
  category: "nature"       # optional; one of: nature | city | abstract | food | tech | people
})
# → [
#     {
#       slug: "forest-mist-loop-12s",
#       name: "Forest mist — 12s loop",
#       description: "Slow drift through pine canopy, golden hour",
#       r2_url:     "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s.mp4",
#       poster_url: "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s-poster.webp",
#       duration_seconds: 12,
#       loop_seconds:     12,
#       category:   "nature",
#       tags:       ["forest", "golden-hour", "calm"],
#       is_featured: true
#     },
#     ...
#   ]
```

**Public read, no auth required for the browse**. Filterable by `category`, `tag`, `is_featured`. Pagination via `limit` (≤200) + `offset`.

The catalog ships with 12 clips across 6 categories:

| Category | Tone |
|---|---|
| `nature` | Forest, ocean, sky, weather — calm, organic |
| `city` | Urban motion, neon, traffic-light timelapses — energetic |
| `abstract` | Particle systems, gradient sweeps, fluid sims — modern brand |
| `food` | Steam, pour shots, ingredient drift — culinary |
| `tech` | Server racks, circuit boards, holographic UIs — B2B SaaS |
| `people` | Faceless silhouettes, hands at work — service brands |

#### Inspect one clip

```
content_get_marketplace_bg_video({ slug: "forest-mist-loop-12s" })
# → the full row above (single fetch by slug; cheaper than re-filtering)
```

### Step 2 — Insert into a page with `page_insert_section`

The `sys-bg-video` component takes the chosen clip's URLs as props. Insert via Phase 11+12 gated `page_insert_section`:

```
# Stage 2a — dry_run preview
page_insert_section({
  page_id:        "<page-uuid>",
  component_slug: "sys-bg-video",
  props: {
    video_url:  "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s.mp4",
    poster_url: "https://cdn.spideriq.ai/marketplace-bg-videos/forest-mist-loop-12s-poster.webp",
    loop:       true,
    autoplay:   true,
    muted:      true,
    overlay_opacity: 0.4
  },
  position: "start",     # "start" | "end" | "before" | "after" | int
  dry_run:  true
})
# → {
#     dry_run: true,
#     preview: { insertion_index: 0, new_block_id: "blk_...", blocks_count_before: 5, blocks_count_after: 6 },
#     confirm_token: "cft_..."
#   }

# Stage 2b — consume the token
page_insert_section({
  page_id:        "<page-uuid>",
  component_slug: "sys-bg-video",
  props:          { ... same as above ... },
  position:       "start",
  confirm_token:  "cft_..."
})
# → { success: true, new_block_id: "blk_...", page: {...updated...} }
```

`position: "start"` puts the bg-video as the first block (the hero slot). `"before" / "after"` need an `anchor_block_id`.

The page itself is NOT republished after insert — call `content_publish_page` (safe-default gated) and then `content_deploy_site_preview` → `content_deploy_site_production` to push live.

### Steps — full flow

```
1. content_list_marketplace_bg_videos({ category: "nature" })   — browse
2. content_get_marketplace_bg_video({ slug })                    — confirm pick
3. page_insert_section({ ..., dry_run: true })                   — preview insert
4. page_insert_section({ ..., confirm_token })                   — confirm
5. content_publish_page({ page_id })                             — preview + confirm
6. content_deploy_site_preview()                                 — preview URL
7. content_deploy_site_production({ confirm_token })             — push live
8. content_visual_check({ page_url, viewport })                  — verify
```

### Recommended props by use case

| Use case | `overlay_opacity` | `autoplay` | `muted` | Notes |
|---|---|---|---|---|
| Hero with copy on top | 0.4–0.6 | true | true | Overlay needed for text contrast |
| Background ambient (footer / break) | 0.0 | true | true | No overlay; muted always |
| Click-to-play (with sound) | 0.0 | false | false | Browsers block autoplay-with-sound; needs user gesture |
| Mobile-first | 0.5 | true | true | Always muted on mobile; `playsinline` is implicit |

### Gotchas

- **`page_insert_section` is Phase 11+12 gated.** You can't skip the dry_run → confirm dance. The dry_run preview tells you the insertion index — useful when `position: "start"` and there's already a hero block.
- **`autoplay: true, muted: false` rarely works.** Browsers block autoplay with sound. Pair `autoplay: true` with `muted: true` always; offer a sound toggle as a separate UI.
- **Marketplace clips are ~5-15 MB each** — fine for a hero but adds to LCP. Run [`../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) post-deploy with `viewport: "mobile"` to confirm acceptable load time.
- **Poster image is critical for perceived performance** — without it, the section is blank until the video buffers. Always pass `poster_url` from the catalog row.
- **The catalog is curated, not user-uploadable from this tool.** To publish a NEW bg-video to the marketplace, see [`author-bg-video.md`](marketplace.md#author-bg-video) (super_admin only).
- **`r2_url` may change between catalog versions** — store it in `props` at insert time; don't expect to read it dynamically.

### Verify

```
content_get_page({ page_id })
# → confirm blocks[0] has component_slug: "sys-bg-video" and your chosen URLs

content_visual_check({
  page_url: "https://<tenant>/<page-slug>",
  viewport: "desktop"
})
# → body_text_preview should still show your text content (overlay shouldn't hide it)
#   dom.media_elements should include {type: "video", src: "<the r2_url>"}
```

### Anti-patterns

- **Skipping the catalog browse** and hardcoding a `cdn.spideriq.ai/marketplace-bg-videos/...` URL. Catalog URLs may change; the browse is the contract.
- **Inserting via `content_update_page` with manually-constructed blocks[]** instead of `page_insert_section`. Loses the Phase 11+12 gate + the insertion-index preview.
- **`autoplay: true, muted: false`** — browsers block it. Always mute autoplay.
- **No `poster_url`** — blank section until buffer fills. Always pass it.
- **Looping `content_list_marketplace_bg_videos` with `limit: 200`** to "see everything." Filter by `category` + `tag` instead; the catalog is small but the bulk return is heavier than necessary.
- **Using the marketplace bg-video for short product demos** (15s+). Use a real `<video>` element with controls; bg-videos are for ambient loops.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "add a looping background video to a page"
# Top-1 should be: recipes/marketplace/pick-bg-video.md
```

### See also

- [`browse-and-insert-section.md`](marketplace.md#browse-and-insert-section) — the generic "browse marketplace + insert" pattern (this recipe is its bg-video specialisation)
- [`browse-cro-components.md`](marketplace.md#browse-cro-components) — for capture / urgency / scarcity components (different catalog)
- [`author-bg-video.md`](marketplace.md#author-bg-video) — publish a NEW clip to the catalog (super_admin only)
- [`../content/scroll-video-hero.md`](content.md#scroll-video-hero) — when you want a scroll-scrubbed video (different primitive — `sys-scroll-sequence`, not `sys-bg-video`)
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — `page_insert_section` is gated; the dry_run → confirm flow


---

## Suggest Agent Meta

Suggest mood / palette / brand_fit_tags / scene_type / agent_meta for a freshly uploaded marketplace asset using the SpiderGate-powered inference engine, then apply via the gated `set_*_agent_meta` tools — agent-curation flow shipped 2026-05-06 (slice 6).

The Marketplace V2 catalog is searchable by intent (mood / palette / brand-fit / scene-type / agent_meta). When an agent uploads a NEW asset, that asset arrives with empty metadata — invisible to `marketplace_search`. This recipe is the auto-curate path: an LLM-driven suggester proposes values; the agent reviews; the apply path writes them with `agent_meta_source='llm_inferred'`.

### Quick ask: "I just uploaded a bg-video — suggest its metadata so other agents can find it"

```
marketplace_suggest_agent_meta(
  asset_type = "bg_video",
  slug = "raindrops-tokyo-street"
)
# → SuggestEnvelope:
# {
#   "asset_type": "bg_video",
#   "slug": "raindrops-tokyo-street",
#   "proposed_universal_axes": {
#     "mood": ["urban", "dreamy"],
#     "palette": ["neon-accent", "monochrome"],
#     "brand_fit_tags": ["fintech", "tech"],
#     "scene_type": "city-aerial"
#   },
#   "proposed_agent_meta": {
#     "pace": "medium",
#     "time_of_day": "night",
#     "weather": "rain",
#     "has_people": true,
#     "aspect_ratio": "16:9"
#   },
#   "confidence_per_key": [
#     { "key": "mood",        "value": ["urban","dreamy"],  "confidence": 0.91, "action": "auto_apply" },
#     { "key": "palette",     "value": ["neon-accent",...], "confidence": 0.85, "action": "auto_apply" },
#     { "key": "scene_type",  "value": "city-aerial",        "confidence": 0.78, "action": "auto_apply" },
#     { "key": "agent_meta.weather", "value": "rain",        "confidence": 0.65, "action": "review" }
#   ],
#   "dropped_keys": [],          // off-vocab values the engine refused (audit-only)
#   "reasoning": "Defocused nighttime cityscape with rainfall and warm window lights — urban, dreamy, fintech-fitting.",
#   "usage": { "model": "spideriq/vision", "input_tokens": 670, "output_tokens": 220, "cost_usd": 0.005 }
# }

# Step 2: review + apply (gated, dry_run=true default → confirm_token round-trip)
set_bg_video_agent_meta(
  slug = "raindrops-tokyo-street",
  mood = ["urban", "dreamy"],
  palette = ["neon-accent", "monochrome"],
  brand_fit_tags = ["fintech", "tech"],
  scene_type = "city-aerial",
  agent_meta = { pace: "medium", time_of_day: "night", has_people: true, aspect_ratio: "16:9" }
  # Skip "weather": "rain" — confidence was "review" tier
)
# → preview envelope with confirm_token

set_bg_video_agent_meta(
  slug = "raindrops-tokyo-street",
  ...same args...,
  confirm_token = "<from previous>"
)
# → applied; agent_meta_source = 'llm_inferred', agent_meta_filled_at = NOW()
```

### Why this exists

- New marketplace assets arrive bare — invisible to `marketplace_search`. Without metadata, no other agent finds them.
- Manual curation is slow + inconsistent. The inference engine sees the poster (or the component HTML / template description) and produces structured metadata in <2 seconds.
- Provenance tracking (`agent_meta_source` column, slice 2) means LLM suggestions never overwrite a human curator's edits — `human_curated` is sticky.

### When to call this vs the V2 search tools

| Situation | Call this |
|---|---|
| Just uploaded a bg-video / component / site-template | ✅ `marketplace_suggest_agent_meta` |
| Want to find an existing asset by intent | ❌ use `marketplace_search` instead |
| Have your own labels in mind | ❌ skip suggester, call `set_*_agent_meta` directly |
| Bulk-fill many assets at once | ❌ ask SpiderIQ admin to run the slice 4 bulk pipeline |

### Output decoded

| Field | What it means |
|---|---|
| `proposed_universal_axes` | mood / palette / brand_fit_tags / scene_type — already filtered for off-vocab |
| `proposed_agent_meta` | per-asset-type keys (BgVideoAgentMeta / ComponentAgentMeta / SiteTemplateAgentMeta) — already filtered |
| `confidence_per_key[].action` | `auto_apply` (≥0.75 + vocab match) / `review` (≥0.55) / `drop` (already excluded from proposals) |
| `dropped_keys` | Audit log: keys the LLM proposed but the validator refused. Read these to spot vocabulary drift. |
| `reasoning` | One sentence justification — useful when picking between proposals |
| `usage.cost_usd` | <$0.01 typical per call (Opus 4.7 via spideriq/vision or spideriq/lead-analysis routes) |

### Guardrails

- **Always validated against locked Pydantic enums BEFORE returning.** A hallucinated mood like `"stoic"` never reaches you — it's dropped + listed in `dropped_keys`.
- **Universal `palette` is open vocabulary** by design — semantic color tokens (`deep-blue`, `cinematic`, `neon-accent`) are accepted as-is.
- **`scene_type` is single-value** and OMITTED when no enum value fits. The engine returns `scene_type: null` rather than force-fitting.
- **`agent_meta` has `extra="forbid"`** — keys not in `BgVideoAgentMeta` / `ComponentAgentMeta` / `SiteTemplateAgentMeta` are dropped.

### Anti-patterns

- **Don't blindly apply low-confidence values.** The `action: "review"` tier is your queue — eyeball before passing to `set_*_agent_meta`.
- **Don't re-run on `human_curated` rows.** They're sticky by design; the apply tool will silently no-op those keys (good). But it wastes a call.
- **Don't expect this to fill `palette` for components.** Most components have placeholder thumbnails — the engine returns `palette: null` for them. Components inherit theme palette at render time.

### See also

- [recipes/marketplace-search-and-insert](marketplace.md#browse-and-insert-section) — once metadata is filled, find assets by intent
- [tool-surface.md — full tool catalog](tool-surface.md) — full tool catalog including the `set_*_agent_meta` apply tools
