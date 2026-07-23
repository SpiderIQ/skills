# Design a newsroom page — compose the press components into a page a journalist can scan

You want to **build the newsroom**, not just publish a release into it. That is a different job:
`press-newsroom.md` teaches the *content* API (create a release, contacts, a kit); this reference
teaches the *page* — which components to drop, in what order, bound to what data, styled to which of
four archetypes. The goal a good newsroom optimises for is **time-to-headline** and
**time-to-asset**: a reporter arrives knowing roughly what and when, and needs the headline plus a
downloadable logo fast. A newsroom is *scanned*, not *browsed*.

Reach for `references/content.md` if you only need a page + sections; reach for
`references/templates-deploy.md` for the theme/deploy mechanics this reference assumes.

---

## The vocabulary — three components, four snippets, one data source

A newsroom page is composed from exactly three system components plus a live data source. Everything
else (the release detail page, the contact block, the boilerplate) is a **route** the platform
renders for you — you do not build it.

| Building block | Slug | What it renders | Where it lives |
|---|---|---|---|
| **Release list** | `sys-press-releases` | A live, newest-first list of published releases (thumb · type badge · dateline · title · subhead) | A block you insert on the newsroom page |
| **Media kit** | `sys-press-kit` | Ungated downloadable assets — per-asset + a "download all" zip, sizes shown up front | A block you insert |
| **"As seen in" marquee** | `sys-press-marquee` | A CSS-only scrolling strip of publication logos, each clickable to the article | A block you insert |
| **Release detail** | `press-release.liquid` (route) | The full release page: dateline, pull-quotes, boilerplate, contacts, legal | Auto-rendered at `/press/{slug}` |
| **Contacts** | `press-contact-block` (snippet) | "Media contacts" — one or many, regional | Rendered inside the release + newsroom |
| **Boilerplate** | `press-boilerplate` (snippet) | The evergreen "About X" + a small fact sheet | Rendered inside the release |

**The `press` data source** feeds `sys-press-releases`. It is a `kind='dynamic'` binding — the list
stays current on its own; you never paste release rows into props. Its knobs are **`default_sort`**
and **`default_limit`** (on the component's `sources[0]`), overridable per block via the block's
`data_binding` (`sort` / `limit` / `filter`). The item fields a template can read: `slug`, `title`,
`subheadline`, `release_type`, `dateline_city`, `dateline_date`, `published_at`, `hero_image_url`,
`hero_image_alt`, `is_featured`.

> The single most common newsroom bug is **oldest-first order.** The sort key must be
> `-published_at` (with the leading minus). Drop the `-` and the renderer's default surfaces the
> *oldest* release at the top — the exact opposite of a newsroom.

**WRONG** — pasting rows or using the wrong knob name:
```
insertSection(component_slug="sys-press-releases",
              props={ items: [ {title: "…"}, {title: "…"} ],   # ❌ not how a dynamic list works
                      sort: "published_at" })                   # ❌ wrong key AND oldest-first
```
**RIGHT** — bind the source, newest-first, capped:
```
insertSection(component_slug="sys-press-releases",
              props={ heading: "Latest news",
                      subheading: "Announcements, statements and coverage." })
# the block's data_binding carries { source_id: "press", sort: "-published_at", limit: 6 }
```

→ Component prop tables: below. Data-source landmine also in `press-newsroom.md` → Gotchas.

---

## The four archetypes — pick one, then build to it

Every newsroom is one of four archetypes, distinguished by **who scans it** and **what they came
for**. Pick the archetype first; it decides the hero, the index strategy, and whether the kit or the
marquee leads. This table is the load-bearing decision aid — read the "Index strategy" column against
the honesty rules in the next section.

| Archetype | Who scans it / came for | Hero lead | Index strategy | Components | Distinct design move | Mood |
|---|---|---|---|---|---|---|
| **Minimal / Solo** | One reporter · "is this real, who do I email, grab a logo" | No hero — title + one-line lede | Flat list ✅ | `sys-press-releases`, `press-contact-block`, `press-boilerplate` | One column ≤64rem, dateline + title + excerpt, an email, a boilerplate | Near-monochrome, one link colour |
| **Startup / Launch** | Tech press, investors, candidates · the new thing + proof | One launch, full-bleed (render/gradient) + CTA | Flat list + type badges ✅ | `sys-press-releases`, `sys-press-marquee`, kit optional | Changelog rhythm, coverage marquee HIGH as social proof, often no boilerplate | Can be dark, bold accent |
| **Corporate / Enterprise** | Trade press, analysts, investors · the official version + a quote + a logo | Featured latest release as a large hero card | Featured-hero+list (see honesty) | `sys-press-releases`, `sys-press-marquee`, `sys-press-kit`, contact + boilerplate | Type-led restraint, fixed date column, regional contact routing, kit + logo wall prominent | Light, restrained, one accent |
| **Agency / Creative** | Design press, prospective clients, juries · the visuals + the brand system | Editorial cover — oversized image, asymmetric type | Image-first grid (see honesty) | `sys-press-releases` (image-forward), `sys-press-kit` (front-and-centre), `sys-press-marquee` | The media kit *is* the point; work/press blur; expressive type | Expressive, bespoke palette |

**Build the Minimal archetype first.** It maps to the shipped components with **zero gaps** and is
the right default — a flat reverse-chron list is genuinely correct for a solo newsroom, not a
compromise. Prove the composition end-to-end there, then layer richer archetypes.

→ Exemplars + full pattern analysis: `docs/external/press-newsroom-design-research-2026-07-23.md`
(the design source this reference distils).

---

## Build a Minimal newsroom — the zero-gap reference sequence

This is the canonical build. Every other archetype is this sequence plus archetype-specific blocks.

```
1. listSiteTemplates()                       # is the one-click "newsroom" starter available?
   → if yes, jump to the one-click path below and skip to step 6

2. createPage(title="Newsroom", slug="newsroom", template="blank")
   → page_id                                 # "blank" bypasses the theme chrome; the page IS the newsroom

3. insertSection(page_id, component_slug="sys-press-releases",
                 props={ heading: "Newsroom",
                         subheading: "Official announcements and press contacts." })
   # binds the `press` source (newest-first, limit 6) automatically

4. insertSection(page_id, component_slug="sys-press-kit",
                 props={ heading: "Media kit",
                         description: "Logos and brand assets — no form, just download.",
                         assets: [ … ], zip_download_url: "…", zip_size_human: "24.6 MB" })

5. # contacts + boilerplate ride on each RELEASE (press-contact-block / press-boilerplate
   #   snippets) — you author them via the press content API, not as page blocks. See press-newsroom.md.

6. previewPage(page_id)                       # confirm order + palette BEFORE publishing
7. publishPage(page_id) → deployPreview → deployProduction
8. content_visual_check(<live newsroom url>)  # a client-rendered list fools curl — visual-check it
```

**One-click path (preferred when the starter exists).** The platform ships a `newsroom` single-page
starter that composes all of the above:

```
listSiteTemplates()                                   # find slug "newsroom" (is_single_page=true)
applySiteTemplate(slug="newsroom", dry_run=true)      # → confirm_token (two-phase, destructive-gated)
applySiteTemplate(slug="newsroom", confirm_token=…)   # clones the composed page as a DRAFT
# then edit copy/colours on the draft → publishPage → deploy → visual-check
```

The clone lands as a **draft** and adopts the tenant's palette; the releases list is already bound to
the live `press` source. Adapt copy, don't rebuild.

→ Two-phase deploy mechanics: `references/templates-deploy.md`. Release authoring: `press-newsroom.md`.

---

## What is buildable today — the honesty every design must respect

A newsroom mockup that promises an index we cannot render wastes the build. Three tiers, per the
design research:

| Pattern | Tier | What that means for you |
|---|---|---|
| Flat reverse-chron list | ✅ Ships today | `sys-press-releases` renders exactly this on a composed page |
| Ungated media kit (per-asset + zip + sizes) | ✅ Ships today | `sys-press-kit` — but drive colour from tokens (see below) |
| "As seen in" marquee | ✅ Ships today | `sys-press-marquee` — **ships empty**; shows nothing until the tenant uploads logos |
| Featured-hero + list · card grid | 🟡 New / route-only | `layout: featured` / `layout: grid` on `sys-press-releases` are **incoming** (not on a composed page yet). A filterable, year-grouped index is a **`/press` route** feature, not a composed-single-page one |
| Media-kit thumbnail grid | 🟡 Incoming | `sys-press-kit` `layout: grid` is being added; today the kit is a text list of assets |
| Type filter / year jump / RSS | Route-only | These live on the `/press` route template, not on a composed newsroom block |

**The composed-page vs `/press`-route distinction (internalise this).** A composed single-page
newsroom (what `applySiteTemplate` builds, what these components target) renders a **flat list** — no
filters, no year grouping, no featured slot. All the rich index behaviour (type-filter links,
year-jump nav, a lead-hero for the newest release) lives only on the **`/press` route** template,
which a composed page does not use. So: **Minimal and Startup ship today on the flat list**;
**Corporate's featured-hero and Agency's grid** either wait on the incoming `layout` props or route
the archetype to a full `/press` page instead of a composed one. Do not mock a featured/grid/filter
*composed* index as if it renders today.

**The marquee ships empty.** `sys-press-marquee` defaults to `logos: []`. A freshly-applied template
shows *no logos* until the tenant wires their own (there is no preset gallery). Tell the client: the
"As seen in" strip is blank until you upload publication logos to the media library and list them.

→ Full gap list + per-archetype verdicts: design research §10 + §11.

---

## Design taste — hierarchy, heroes, and the one rule you cannot break

Reference tables state *what*; this section is the *why* an agent needs to make the calls a table
can't encode.

**The hero answers "what did I come for?"** Corporate leads with the top *story*; Startup with the
new *thing*; Agency with the *visual*; Minimal offers *orientation only* (a title + lede, no hero). A
hero that doesn't answer the archetype's question is decoration — cut it.

**Ungate the media kit.** Verified across 30 real newsrooms: the best let a reporter grab assets
*without a form*. Never put the kit behind a lead-capture wall. Per-asset downloads with the file
size shown *before* the click, plus a "download all" zip, is the pattern — `sys-press-kit` already
does it. A gated kit is the single fastest way to look amateur to press.

**Dateline is the one press convention that still means something.** "BERLIN, August 1, 2026 —" on
its own line above the body. Keep it; it signals a real newsroom. Drop the dead conventions: **no
"FOR IMMEDIATE RELEASE", no "###" end marker** — zero of 30 newsrooms use them.

**Drive every colour from theme tokens — this is the one rule you cannot break.** The release detail
template `press-release.liquid` is the model: it uses `.prose` (never `.prose-invert`, which hardcodes
`#fff`/`#d4d4d8` and vanishes on a light tenant) and drives headings, borders and quotes from
`var(--heading)` / `var(--border)` / `var(--primary)`. A component that hardcodes a colour scheme
breaks on any tenant whose theme doesn't match — and fails WCAG AA contrast.

**WRONG** — hardcoded scheme (what `sys-press-kit` shipped with, now being corrected):
```css
.kit h2      { color: #fff; }                     /* ❌ invisible on a light tenant */
.kit .asset  { border: 1px solid rgba(255,255,255,0.08); }  /* ❌ borders vanish; AA fail */
```
**RIGHT** — token-driven, works on every theme:
```css
.kit h2      { color: var(--heading, #111); }
.kit .asset  { border: 1px solid var(--border, #e5e5e5); }
:host        { background-color: var(--bg, transparent); }
```

**Filters are routes, not JavaScript.** When an index needs type/year filtering, the right pattern is
a real URL (`/press/type/announcement`) — shareable, crawlable, back-button-correct, keyboard-navigable,
no script. A client-side `<select>` filtering a JSON blob breaks all of that and is invisible to a
reporter who arrives via a `/type/…` link. (This lives on the `/press` route, per the honesty table.)

→ The worked example of a great release page — dateline, pull-quotes, body measure, boilerplate,
token discipline — is `press-release.liquid`. Study it as the gold standard for the detail surface.

---

## Decision tree — which index does this newsroom need?

```
Is a filterable / year-grouped / featured-hero index required?
│
├─ NO  → compose a single page with sys-press-releases (flat list).
│        This is Minimal and Startup. Ships today. ✅  ← start here
│
└─ YES → does it need to be a COMPOSED single page (applySiteTemplate)?
         │
         ├─ NO, a dedicated /press page is fine
         │     → route the archetype to the /press ROUTE template.
         │       Gets year grouping + type filters + lead-hero for free. 🟡 (Corporate's clean path)
         │
         └─ YES, must be composed
               → featured/grid on a composed page needs the INCOMING
                 sys-press-releases layout props (featured|grid). Until they land,
                 fall back to the flat list or the /press route. Do NOT promise it today. 🟡/🔴
```

---

## Component prop reference

Declare every prop you pass — the skill drops params it doesn't know (see `client/schema.yaml`).
These tables are the authoritative prop set for each component.

### `sys-press-releases` — the release list (`kind=dynamic`, `block_type=list`, source `press`)

| Prop | Type | Default | Notes |
|---|---|---|---|
| `heading` | string | "Latest news" | Section heading |
| `subheading` | string | — | Optional intro line under the heading |
| `empty_message` | string | "No press releases yet — check back soon." | Shown when nothing is published |
| `layout` | enum | `list` | `list` today; **`featured` / `grid` incoming** (C.index) — flat list until then |
| *(source)* `default_sort` | string | `-published_at` | **Newest-first needs the leading `-`** |
| *(source)* `default_limit` | integer | `6` | Cap the composed list; a block `data_binding.limit` overrides |
| *(source)* `default_filter` | object | `{}` | Reserved; block `data_binding.filter` overrides |

### `sys-press-kit` — the media kit (`required: [assets]`)

| Prop | Type | Default | Notes |
|---|---|---|---|
| `heading` | string | — | e.g. "Media kit" |
| `description` | string | — | Usage terms / who to contact for anything not listed |
| `empty_text` | string | "Media assets are coming soon." | Shown when the kit has no assets |
| `zip_download_url` | string | — | "Download all" bundle; omit the button if absent |
| `zip_size_human` | string | — | Pre-formatted, e.g. "24.6 MB" (Liquid has no `filesize`) |
| `layout` | enum | `list` | `list` today; **`grid` incoming** (C.kit) for a thumbnail kit |
| `assets[]` | array | — | Required. Per-asset fields below |

**`assets[]` item fields:** `download_url` (counted — preferred), `r2_url` (fallback), `original_name`,
`filename`, `caption` (the human label), `mime_type`, `file_size_human`, `alt_text` (EAA).

### `sys-press-marquee` — "As seen in" (`kind=interactive`, `js_runtime=none`)

| Prop | Type | Default | Notes |
|---|---|---|---|
| `headline` | string | "As seen in" | Eyebrow above the strip |
| `subline` | string | — | Optional line below |
| `aria_label` | string | "As seen in" | Screen-reader region label |
| `logos[]` | array | `[]` | **Empty by default** — `{src, alt, href?, title?}`, `maxItems: 24`. Tenant uploads their own |
| `speed_seconds` | integer | `40` | 10–240; one full pass. Slower = calmer |
| `direction` | enum | `ltr` | `ltr` \| `rtl` |
| `monochrome` | boolean | `true` | Grayscale + dim, colour on hover — the press-strip convention |
| `accent` | enum | `subtle` | `subtle` \| `primary` \| `secondary` |
| `density` | enum | `comfy` | `compact` \| `comfy` |

→ These props are declared in `client/schema.yaml`. The kit palette bug is being corrected (C.kit);
teach the token-driven pattern above, not the old hardcoding.

---

## Verify a newsroom page you built

```
previewPage(page_id)
  → releases render NEWEST first (if oldest-first, the sort lost its leading `-`)
  → the kit heading + borders are VISIBLE on this tenant's palette (not white-on-light)
  → the marquee is empty IF no logos were wired — that is expected, not a bug

content_visual_check(<live newsroom url>)
  → a client-rendered list fools curl; only a visual check confirms it rendered
```

→ Then confirm each release links to its `/press/{slug}` detail page (rendered by
`press-release.liquid`). Release-content verification is in `press-newsroom.md` → Verify.
