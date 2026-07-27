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
stays current on its own; you never paste release rows into props. **It binds itself.** The component
declares `press` on its own `sources[0]` with `default_sort: -published_at` and `default_limit: 6`, and
the renderer falls back to those whenever the block doesn't override them. So **inserting the component
with nothing but `props` renders the live list, newest-first** — there is no binding step. The item
fields a template can read: `slug`, `title`, `subheadline`, `release_type`, `dateline_city`,
`dateline_date`, `published_at`, `hero_image_url`, `hero_image_alt`, `is_featured`.

**WRONG** — pasting rows, or trying to sort via a prop:
```
insertSection(component_slug="sys-press-releases",
              props={ items: [ {title: "…"}, {title: "…"} ],   # ❌ not how a dynamic list works
                      sort: "published_at" })                   # ❌ `sort` is not a prop; silently ignored
```
**RIGHT** — just insert it. The `press` source, newest-first order and 6-item cap all come from the
component:
```
insertSection(component_slug="sys-press-releases",
              props={ heading: "Latest news",
                      subheading: "Announcements, statements and coverage." })
# renders the live press list, newest-first, capped at 6 — no data_binding needed
```

### Overriding the source (sort / limit / filter) — use `createPage`/`updatePage`, NOT `insertSection`

You only need an explicit `data_binding` to **change** the defaults (a different sort, a bigger cap, a
`release_type` filter). It is a **block-level** field, and the agent-facing path to it is the page's
`blocks[]` array — **not** the insert call:

```
createPage(title="Newsroom", slug="newsroom", template="blank",
           blocks=[{ id: "<uuid-you-generate>", type: "component",
                     component_slug: "sys-press-releases",
                     props: { heading: "Latest news" },
                     data_binding: { source_id: "press", sort: "-published_at", limit: 12 } }])
```

> **`data_binding` is NOT a parameter on `insertSection`.** It exists on the raw HTTP
> `POST /pages/{id}/insert-section` body, but it is **not declared** on this skill's `insertSection`,
> on the `page_insert_section` MCP tool, or on the `@spideriq/core` client — and every one of those
> surfaces **drops params it doesn't know** (see *Component prop reference* below). Pass it to
> `insertSection` and it is silently stripped. Set it via `createPage`/`updatePage`
> `blocks[].data_binding` instead.
>
> **Corollary:** because the component self-binds, an insert that "loses" the binding still renders
> correctly. A blank release list is therefore almost never a binding problem — look at the tenant's
> `snippets/block-renderer.liquid` override first (a stale copy drops `items:` and blanks **every**
> dynamic block, press or not).

> **Sort key: `-published_at`, with the leading minus.** Only relevant when you override the sort — the
> component default already has it. Drop the `-` and you surface the *oldest* release at the top, the
> exact opposite of a newsroom.

→ Component prop tables: below. Release authoring: `press-newsroom.md`.

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
| **Corporate / Enterprise** | Trade press, analysts, investors · the official version + a quote + a logo | Featured latest release as a large hero card | **`/press` route** register (filter + year jump) + a media-resources companion page ✅ | `sys-press-marquee`, `sys-press-kit`, regional contacts + boilerplate (the register is the route, not a block) | Type-led restraint, fixed date column, regional contact routing, kit + logo wall prominent | Light, restrained, one accent |
| **Agency / Creative** | Design press, prospective clients, juries · the visuals + the brand system | Editorial cover — oversized image, asymmetric type | `layout: grid` ✅ (block-level) | `sys-press-releases` (image-forward), `sys-press-kit` (front-and-centre), `sys-press-marquee` | The media kit *is* the point; work/press blur; expressive type | Expressive, bespoke palette |

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
   # binds itself: the component's sources[0] carries press + -published_at + limit 6.
   # Only reach for an explicit data_binding to CHANGE those — and set it via
   # createPage/updatePage blocks[], never insertSection (which strips it). See above.

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

**One-click path (preferred when the starter exists).** The platform ships **five** newsroom
starters — pick the one that matches your chosen archetype:

| Archetype | Template slug | Notes |
|---|---|---|
| Minimal / Solo | `newsroom-minimal` | Releases(list) · kit · contact · boilerplate. The zero-gap default. |
| Startup / Launch (dark) | `newsroom-startup-dark` | Hero · marquee(high) · releases(list) · kit · contact. |
| Startup / Launch (light) | `newsroom-startup-light` | Same source page as dark; light palette. |
| Corporate / Enterprise | `newsroom-corporate` | Media-resources page that links up to the built-in `/press` route for the filterable register. |
| Agency / Creative | `newsroom-agency` | Editorial hero · releases(grid) · kit(grid) · marquee · contacts. |

```
listSiteTemplates()                                        # find the newsroom-* slug you want (is_single_page=true)
applySiteTemplate(slug="newsroom-minimal", dry_run=true)   # → confirm_token (two-phase, destructive-gated)
applySiteTemplate(slug="newsroom-minimal", confirm_token=…)# clones the composed page as a DRAFT
# then edit copy/colours on the draft → publishPage → deploy → visual-check
```

The clone lands as a **draft** and adopts the tenant's palette; the releases list renders the live
`press` source, and the starter's blocks already carry the right `layout` ids for that archetype (the
one thing an `insertSection` build cannot set — see the layout table below). Adapt copy, don't rebuild.

→ Two-phase deploy mechanics: `references/templates-deploy.md`. Release authoring: `press-newsroom.md`.

---

## What is buildable today — the honesty every design must respect

A newsroom mockup that promises an index we cannot render wastes the build. Three tiers, per the
design research:

| Pattern | Tier | What that means for you |
|---|---|---|
| Flat reverse-chron list | ✅ Ships today | `sys-press-releases` renders exactly this on a composed page |
| Ungated media kit (per-asset + zip + sizes) | ✅ Ships today | `sys-press-kit` — token-driven palette, legible on light and dark tenants |
| "As seen in" marquee | ✅ Ships today | `sys-press-marquee` — **ships empty**; shows nothing until the tenant uploads logos |
| Featured-hero + list · card grid | ✅ Ships today | `layout: featured` / `layout: grid` on `sys-press-releases` render on a composed page, and `is_featured` elevates that release to the hero. ⚠️ set as **`blocks[].layout`** — `insertSection` cannot |
| Media-kit thumbnail grid | ✅ Ships today | `sys-press-kit` `layout: grid` — a thumbnail card per asset. ⚠️ this one is **`props.layout`** (see the asymmetry table) |
| Type filter / year jump / RSS | Route-only | These live on the `/press` route template, not on a composed newsroom block |

**The composed-page vs `/press`-route distinction (internalise this).** A composed single-page
newsroom (what `applySiteTemplate` builds, what these components target) now renders **all three
release layouts** — flat list, featured-hero, and card grid. What a composed page still cannot do is
the **navigational** index behaviour: type-filter links, year-jump nav, and RSS. Those live only on the
**`/press` route** template. So the split is now about *filtering*, not *layout*:

- **Minimal · Startup · Agency** — composed page, done. Flat list or `grid`, no route needed. ✅
- **Corporate** — still routes to **`/press`** for the register, and that is deliberate: it is the
  archetype whose readers filter by type and jump by year, which only the route can do. The shipped
  `newsroom-corporate` starter therefore clones a *media-resources companion page* (kit · marquee ·
  regional contacts · boilerplate) that links up to `/press`, and carries **no** release index at all.
  Don't "improve" it by composing a `featured` index onto it — you'd trade filtering for a hero.
- Use `featured` when you want a lead story **without** needing filters (a Startup launch page, say).

Do not mock a filterable *composed* index as if it renders today — but do use featured/grid freely.

**The marquee ships empty.** `sys-press-marquee` defaults to `logos: []`. A freshly-applied template
shows *no logos* until the tenant wires their own (there is no preset gallery). Tell the client: the
"As seen in" strip is blank until you upload publication logos to the media library and list them.

### ⚠️ `layout` lives in a DIFFERENT place on each component — and both wrong answers fail silently

The two press components both document a `layout`, but the renderer reads them from opposite places.
Neither mistake raises an error, logs a warning, or emits an HTML comment — you just get the default
variant and no clue why. Verified live on both components:

| Component | Set it as | Reachable via | Wrong answer (silent no-op) |
|---|---|---|---|
| `sys-press-releases` (`list`·`featured`·`grid`) | **block-level `layout`** | `createPage`/`updatePage` `blocks[].layout` **only** — not `insertSection` | `props.layout` → renders the plain list, no hero, no grid |
| `sys-press-kit` (`list`·`grid`) | **`props.layout`** | anywhere props go — `insertSection(props={layout:"grid"})` works | block-level `layout` → renders the list variant |

Why they differ: the release list ships a **separate `html_template` per layout variant**, so the
renderer swaps the whole template by `block.layout`. The kit has **one** template that branches
internally (`{% if layout == 'grid' %}`), and that `layout` resolves from props. The kit *also*
declares `layouts` metadata, so a block-level `layout: grid` on the kit **matches** — which is exactly
why it emits no "layout not found" comment and still gives you the list.

**Consequence for the build path:** a pure-`insertSection` build can produce Minimal and Startup, and
can grid the *kit* — but it **cannot** set the release list's `featured`/`grid`. For Agency's grid index
(or a featured lead story anywhere), either compose the page with `createPage(blocks=[…])` carrying
`blocks[].layout`, or start from the matching `newsroom-*` starter (its blocks already carry them).

```
# Agency: grid index + grid kit, composed in one call
createPage(title="Newsroom", slug="newsroom", template="blank", blocks=[
  { id: "<uuid>", type: "component", component_slug: "sys-press-releases",
    layout: "grid",                                    # ← BLOCK level
    props: { heading: "Press" } },
  { id: "<uuid>", type: "component", component_slug: "sys-press-kit",
    props: { heading: "Media kit", layout: "grid",     # ← PROPS
             assets: [ … ] } },
])
```

> Every block in `blocks[]` needs **both** `id` (a UUID you generate) and `type` — the API rejects the
> page with `422 body.blocks.0.id: Field required` otherwise. `insertSection` mints the id for you;
> `createPage`/`updatePage` do not.

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

**WRONG** — hardcoded scheme (what `sys-press-kit` originally shipped with; since fixed — don't
reintroduce it in a component you author):
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
Does it need type FILTERING, year grouping, or RSS?
│
├─ YES → route the archetype to the /press ROUTE template.
│        Filters + year jump + feeds only exist there. ✅ (Corporate's clean path)
│
└─ NO  → compose a single page. Which release layout?
         │
         ├─ flat list  → insertSection(sys-press-releases, props={…}). ✅ Minimal, Startup
         │               Simplest path; the component self-binds.
         │
         └─ featured hero or card grid  → ✅ Agency (grid), or a Startup launch
                       page wanting a lead story (featured). Ships today, BUT
                       `layout` must be set at BLOCK level, which insertSection
                       cannot do. Use createPage(blocks=[{… layout:"grid" …}])
                       or apply the matching newsroom-* starter.
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
| *(source)* `default_sort` | string | `-published_at` | Applied automatically — **newest-first already**. Only restate it (with the leading `-`) when you override |
| *(source)* `default_limit` | integer | `6` | Applied automatically; a block `data_binding.limit` overrides |
| *(source)* `default_filter` | object | `{}` | Reserved; block `data_binding.filter` overrides |

**⚠️ `layout` is NOT in this component's `props_schema`** — its only props are `heading`, `subheading`
and `empty_message`. `list` · `featured` · `grid` are selected by the **block-level** `layout` field
(`blocks[].layout`), never `props.layout`. See the asymmetry table above.

### `sys-press-kit` — the media kit (`required: [assets]`)

| Prop | Type | Default | Notes |
|---|---|---|---|
| `heading` | string | — | e.g. "Media kit" |
| `description` | string | — | Usage terms / who to contact for anything not listed |
| `empty_text` | string | "Media assets are coming soon." | Shown when the kit has no assets |
| `zip_download_url` | string | — | "Download all" bundle; omit the button if absent |
| `zip_size_human` | string | — | Pre-formatted, e.g. "24.6 MB" (Liquid has no `filesize`) |
| `layout` | enum | `list` | `list` \| `grid` — **both ship today**. A real **prop** here (unlike the release list): pass it inside `props`, incl. via `insertSection` |
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

→ These props are declared in `client/schema.yaml`. The kit's palette is already token-driven (C.kit
shipped) — teach the token pattern above; there is no hardcoded-colour bug left to work around.

---

## Verify a newsroom page you built

```
previewPage(page_id)
  → releases render NEWEST first (if oldest-first, an override sort lost its leading `-`)
  → the layout you asked for actually rendered — a hero for `featured`, tiles for `grid`.
    Still a plain list? You set `props.layout` on the release list; it must be `blocks[].layout`.
    Kit still a text list? You set block-level `layout`; the kit wants `props.layout`.
  → the kit heading + borders are VISIBLE on this tenant's palette (not white-on-light)
  → the marquee is empty IF no logos were wired — that is expected, not a bug

# Release list BLANK? Don't chase the data_binding — the component self-binds.
#   Check the tenant's snippets/block-renderer.liquid override: a stale copy drops `items:`
#   and blanks EVERY dynamic block. Confirm by putting any other dynamic list on the same
#   page — if that's empty too, it's the renderer override, not press.

content_visual_check(<live newsroom url>)
  → a client-rendered list fools curl; only a visual check confirms it rendered
```

→ Then confirm each release links to its `/press/{slug}` detail page (rendered by
`press-release.liquid`). Release-content verification is in `press-newsroom.md` → Verify.
