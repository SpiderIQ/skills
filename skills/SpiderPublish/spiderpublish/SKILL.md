---
name: spiderpublish
description: >
  Author, publish, and deploy on SpiderPublish — SpiderIQ's multi-tenant CMS +
  Liquid site runtime. Build pages, blog posts, docs, reusable components,
  navigation, themes, media, and custom domains for a brand's own website, then
  deploy to the Cloudflare edge. Trigger on: "add a page", "write a blog post",
  "edit the header", "create an author", "set up categories/tags", "apply a
  theme", "connect a custom domain", "publish the blog", "deploy the site", or a
  tenant name (sms-chemicals.com, demo.spideriq.ai). Content is LIVE ON PUBLISH (~60s edge
  cache); only templates / theme / chrome need a DEPLOY.
  SpiderPublish is a runtime, not a generic CMS — generic web knowledge gets the
  five-lock tenant defense and the publish-vs-deploy split wrong. Per-tenant,
  PAT-scoped. NOT for sending email (use SpiderMail) or finding prospects (use
  spiderflows / lead-search).
version: "0.12.0"
category: content
---

# SpiderPublish

SpiderPublish is a **runtime**, not a generic CMS. Three layers:

- **STORE** — FastAPI + PostgreSQL. Every authored thing (page, post, doc,
  component, setting, template) lives here in a tenant-isolated row. Nothing is
  "on disk."
- **SERVE** — Cloudflare Workers (`dispatch` → `liquid-renderer`) read templates
  from per-tenant KV and fetch content from STORE at request time. Forms render
  at `/f/<flow_id>`.
- **MANAGE** — this skill (over a PAT), plus the dashboard, MCP, CLI, and VSCode
  extension. All call the same STORE API.

Your job: land changes in STORE correctly — that is enough for CONTENT.
Deploy only when you touched a **template, theme or section**.

```
  CONTENT  ── publish ──▶ STORE (Postgres) ──fetched at REQUEST time──▶ visitors
   pages · posts · docs        status=published        ~60s edge cache
   press · changelog                                   NO DEPLOY NEEDED
   components · nav · settings

  CHROME   ── deploy ───▶ per-tenant KV ──read by the Worker──▶ visitors
   Liquid templates · theme    deploySite() writes KV
   sections/*.liquid           THIS is what deploy is for
```

## Auth + two URL surfaces (one PAT)

`SPIDERIQ_PAT` = Bearer `client_id:api_key:api_secret`. The token identifies the
brand — you do **not** put a workspace id in the URL. The PAT is self-identifying
(`spideriq_pat_<agent_ref>_<secret>`; legacy `<32-hex>` still works) and carries an
`opvsAddress` (`<name>@opvs.run`) — you are ONE account, so re-auth from a new
directory ROTATES it and `--as <opvs-address>` RECOVERs it (no ghost identities).

| Surface | Path | Use for |
|---|---|---|
| **Authoring** | `/api/v1/dashboard/content/*`, `/api/v1/dashboard/templates/*` | every create/update/delete/publish, and reads that must show **drafts** |
| **Public discovery** | `/api/v1/content/*` | search, featured, marketplace browse, vayapin, `/help` — published only, no auth |

> **There is NO `/api/v1/spideriq/content` path.** That was a dead proxy prefix
> the old skill used → every call 404'd. The schema in `client/schema.yaml` now
> carries the correct paths. (See `references/gaps.md` + `learnings/`.)

Add `?format=yaml` (or `md`) to any read — or set `SPIDERIQ_FORMAT=yaml` — for
40–76% fewer tokens.

<HARD-GATE name="authoring-is-not-live--two-phase-on-prod">

**Three rules that bite every agent new to SpiderPublish:**

0. **YOU MAY NOT BE ON THE TENANT YOU THINK. CHECK BEFORE YOU WRITE.** A write
   that lands on the wrong brand's site returns **200 and looks identical to a
   correct one** — same envelope, same id, same "published". Nothing downstream
   will tell you. Preflight once per session, before the first create/update/
   delete/publish:

   ```
   get_auth_status({ topic: "tenancy" })
   ```

   Read four fields off it: `active_workspace` (the tenant your next call
   touches), `resolved_via` (WHY it was chosen — `explicit` · `environment` ·
   `binding` · `sole-credential`), `workspaces[]` (everything else you could
   reach), and `conflicts` (a losing candidate — if this is non-empty, a
   `spideriq.json` or `$SPIDERIQ_WORKSPACE` names a DIFFERENT tenant than the
   one that will actually be used).

   **If more than one workspace is authenticated, stop resolving implicitly and
   pass `workspace: "cli_…"` on every call.** It is rung 1 and always wins. An
   agency session working three clients should never rely on a binding file.

   *(Driving this skill's own HTTP methods with a single `SPIDERIQ_PAT`? The
   token IS the tenant — one credential, no resolution, nothing to check.)*

1. **CONTENT IS LIVE ON PUBLISH. CHROME IS NOT.** These are two different
   pipelines and confusing them wastes more agent time than anything else in
   SpiderPublish — in both directions.

   | You changed… | Live when? | Deploy needed? |
   |---|---|---|
   | page · post · doc · press · changelog · collection record · component · navigation · settings | **on publish**, within ~60s | **NO** |
   | Liquid template · theme · `sections/*.liquid` · the config overlay | on deploy | **YES** |

   **Why:** the renderer fetches content from STORE over HTTP **at request
   time** (`ContentAPIClient` → `GET /content/*`, `X-Content-Domain`). Templates
   and the config overlay come from per-tenant **KV**, which only `deploySite`
   writes.

   **The ~60s trap that makes this look backwards.** Rendered HTML ships
   `Cache-Control: public, s-maxage=60, stale-while-revalidate=300`. So you
   publish, look immediately, still see the old page, run a deploy (which takes
   about as long as the cache window), see the new page — and conclude the
   deploy did it. It didn't. **If content looks stale, wait 60 seconds and
   re-fetch before deploying.**

   Telling the user "this needs a deploy" for a post, doc or changelog entry is
   as wrong as telling them a template change is already live. Both are common;
   the first invents a blocker that does not exist.

2. **DESTRUCTIVE OPS ON A PRODUCTION TENANT ARE TWO-PHASE.** `deletePage`,
   `applyTheme`, `deployProduction`, `deletePage`, `updateSettings`, and the
   deploy itself accept `dry_run: true` → you get a **preview + `confirm_token`
   (`cft_…`)**; pass that token back to actually mutate. On a production tenant,
   ALWAYS preview first. (Envelopes: 410 expired · 409 consumed · 403 mismatch.)

**Why a hard gate, not a footnote:** the publish-vs-deploy confusion and
"delete looked safe" are the two highest-frequency SpiderPublish mistakes, and
the wrong-tenant write is the one with no symptom at all. Before reporting
anything, be sure **which tenant** you wrote to and **which pipeline** you
touched — and verify by **fetching the live URL**, not by trusting a 200.

</HARD-GATE>

## STEP 0 — two questions, before anything else

**0A. WHO am I about to write to?** — `get_auth_status({ topic: "tenancy" })`.
It is in the facade's always-on set, in the unfiltered kitchen sink, in
`@spideriq/mcp-publish`, and in the CLI as `spideriq auth whoami`. See HARD-GATE
rule 0 above for what to read off it. Do this **once per session, before the
first write** — a wrong-tenant write is a 200 with no other symptom.

> ⚠️ **The one place it is missing is `SPIDERIQ_MCP_SLICE=mac-128`** — that
> keep-list names `auth_whoami` / `auth_request_access` / `auth_get_workspaces`
> / `system_health_check` and five more that **do not exist under those names**,
> so all 8 shared auth+system tools are dropped. On that slice you cannot check
> who you are, enrol, or health-check. It is one more reason the answer to
> mac-128 is *never set it* (see 0B).

**0B. Can I reach everything?**

> **Driving this skill's own methods (`createPage`, `createFlow`, `createPressRelease`…)?
> You have everything — skip to the next section.** These call the HTTP API directly,
> so no MCP tool limit applies. 0B is only about **MCP tool** setups.

**Look at your own tool list for `tool_search`.**

**If `tool_search` is there — you are in facade mode. Everything is reachable. Skip the rest of this section.**
You will see ~9 tools, not hundreds. That is deliberate, not truncation. Use:

```
tool_search({ intent: "<what you want to DO>" })   → ranked tool names + a literal `call` string
tool_help({ name: "<exact name>" })                → the full input schema
tool_call({ name: "<exact name>", arguments: {…} }) → runs it, with every gate intact
```

Three rules: **copy the name verbatim** from the result's `call` field (retyping or
pluralising it is the top cause of a not-found); **a search returning nothing means
search again with different words**, not that the capability is missing (431 tools sit
behind it); and pass `include_schemas: true` to skip the `tool_help` hop.

**If `tool_search` is NOT there,** you are on a limited set. Which one:

| Also present | You have | Reaches |
|---|---|---|
| `form_create` | kitchen sink, unfiltered (431) | everything — but see the warning below |
| `marketplace_search`, no `form_create` | `@spideriq/mcp-publish` (163) | content, templates, deploy, marketplace. **No** forms/booking/press/funnels/section-overrides |
| neither — and **no `get_auth_status`/`health_check` either** | mcp-publish + `mac-128` slice (95) | the above **minus the whole reuse path, and minus all 8 auth+system tools** |

**Tell the user how to fix it** — this is a config change, not a platform limit:

```json
"spideriq": {
  "command": "npx",
  "args": ["-y", "@spideriq/mcp@latest"],
  "lazy": true,
  "env": { "SPIDERIQ_MCP_MODE": "facade", "SPIDERIQ_FORMAT": "yaml" }
}
```

> `"lazy": true` is an **Antigravity-specific** key, reported by Antigravity
> sessions (2026-08-13) to avoid an IDE bug where natively-injected (eager)
> tools throw `unknown tool` on call. We have not been able to reproduce or
> disprove it — we cannot run that IDE. Other clients ignore the key, so it is
> safe to leave in. If `tool_search` is listed but calling it says the tool is
> unknown, that is the bug this key is for.

> ⚠️ **Do NOT suggest "just switch to `@spideriq/mcp`" without facade mode.** Measured
> 2026-08-12: the unfiltered 431-tool list makes Antigravity **silently abort the
> ingest and keep the previous package's cached tools** — no error, no warning. The
> session then believes it switched and has not. 163 ingests; 431 does not. Facade
> mode is what makes the full surface reachable on a size-limited client.
>
> ⚠️ **Never set `SPIDERIQ_MCP_SLICE=mac-128`.** 35 of its 130 names are ghosts (a
> plain name intersection, so each is a silent no-op) and it drops
> `marketplace_search`, `page_insert_section`, `content_apply_site_template` and
> `content_get_playbook` — the entire adapt-don't-generate path. **All 8 of its
> "shared auth + system" entries are among the ghosts** (`auth_whoami`,
> `auth_request_access`, `auth_get_workspaces`, `auth_logout`,
> `auth_check_access_status`, `system_health_check`, `system_get_queue_stats`,
> `system_get_api_info` — the real names carry no prefix), so that slice cannot
> check its own tenant, enrol, or health-check.

**When a capability is out of reach, say so plainly and stop** — *"forms need
`@spideriq/mcp` with `SPIDERIQ_MCP_MODE=facade`; you have `@spideriq/mcp-publish`"*.
Do not invent a workaround, and do not report the platform as broken. Every reference
states its own requirement in a `REQUIRES:` block at the top.

## Noun → where the tools are

The user names ONE noun. That noun tells you which reference AND which package:

| The user said… | Tools live in | Read |
|---|---|---|
| page, section, block, hero | any universe (`page_insert_section` needs default+) | `references/content.md` · `references/block-types.md` |
| blog, post, author, tag, category | any universe | `references/content.md` · `references/blog-page-design.md` |
| header, footer, nav, chrome | nav: any · **override: kitchen sink** (fallback `template_upsert`) | `references/content.md` |
| component, marketplace, section library | default+ | `references/components.md` · `references/marketplace.md` |
| theme, template, starter site, deploy | any universe | `references/templates-deploy.md` |
| docs, API reference, OpenAPI | authoring: any · **ask/search: kitchen sink** | `references/content.md` · `references/docs-site-design.md` |
| collection, case studies, products, custom type | any universe | `references/collections.md` |
| changelog, release notes | any universe | `references/changelog.md` |
| **form, lead capture, contact form** | this skill: ✅ HTTP · MCP: **kitchen sink only** | `references/forms-booking.md` |
| **booking, appointment, calendar** | this skill: ✅ HTTP · MCP: **kitchen sink only** | `references/booking-model.md` |
| **funnel, multi-step flow** | this skill: ✅ HTTP · MCP: **kitchen sink only** | `references/funnels.md` |
| **press, newsroom, media kit** | this skill: ✅ HTTP · MCP: **kitchen sink only** | `references/press-newsroom.md` · `references/press-page-design.md` |
| agent, chatbot, AI assistant | `agent_flow` in default+ | `references/agent-embed.md` |
| domain, DNS, go live | any universe | `references/content.md` |

## Approach — SHOP FIRST, then author

**Reuse before generate is the default posture, not an option.** Authoring a
component or page from scratch is the fallback for when the shelf has nothing —
it is not the starting move. There are 363 marketplace components, 26 site
templates and 8 page templates already built and tested.

0. **CONFIRM THE TENANT** — `get_auth_status({ topic: "tenancy" })` once, before
   the first write. Everything below mutates a specific brand's live site and a
   wrong-tenant write returns 200. If `workspaces[]` holds more than one entry,
   pass `workspace: "cli_…"` explicitly from here on.
1. **SHOP** — before writing any HTML or block JSON:
   - a whole site, or a landing / opt-in / thank-you / VSL page →
     `listSiteTemplates` / `listPageTemplates` → `applySiteTemplate` /
     `applyPageTemplate`, then adapt the copy.
   - one section (hero, pricing, FAQ, footer, testimonials, CTA) →
     `listMarketplaceComponents({ category })` → `insertSection`.
   - **Search WIDER than the noun.** Category counts are uneven — `header` holds
     1 component and `faq` holds 1, but `trust-authority` (17), `social-proof`
     (16), `conversion`, `cta` and `content` hold sections that also serve as
     chrome or hero. A single-category search returning 1 result means *search
     again*, not *the shelf is empty*.
2. **Orient** — `getHelp` if you don't know the site shape; `listPages` /
   `listPosts` / `listComponents` to see what already exists (including drafts).
3. **Author** — only what shopping didn't cover. `createPage` / `createPost` /
   `createDoc` (+ `createAuthor`, `createTag`, `createCategory` for taxonomy
   first). Body is **Tiptap JSON**, not HTML.
4. **Assemble** — `insertSection` for components; `applyTheme` for look;
   `updateNavigation` / `updateSettings` for chrome.
5. **Publish** — `publishPost` / `publishPage` / `publishDoc` (draft → published).
6. **Deploy** — `deployPreview` → `deployProduction` (safe), or `deploySite`
   (one-shot). THIS is the step that makes it live.
7. **Verify** — `deployStatus`; on a published URL, a visual check asserting on
   `dom.shadow_hosts` (NOT `body_text_preview`) for embedded components/forms.

## The job is NOT done until… (read before you report back)

A one-word request implies more than one object. Finishing only the named noun is
the most common way an agent reports success on an unfinished site.

| Asked for… | Not done until you have also… |
|---|---|
| "the blog" | authors + tags/categories exist · at least one post **published** (live in ~60s, no deploy) · the `/blog` **listing page** designed — **deploy only if you changed `templates/blog.liquid`** |
| "the header" / "the footer" | nav items point at pages that **exist and are published** (nav itself is live on save) · **template/section edits need `deploySite`** — this is genuinely chrome |
| "a form" | the flow is **published** and reachable at `/f/<id>` (live immediately) · if embedded, the host page is published too · a **test submission accepted** — that is the real proof, not a 200 on publish |
| "a landing page" | blocks composed · SEO fields set (`og_image`, `meta_description`) · slug is not `/` (use `home`) · **published** — live in ~60s, no deploy |
| "docs" | doc pages **published** (live, no deploy) · the docs nav tree resolves · theme applied **after** any OpenAPI import — **the theme is the part that needs `deploySite`** |
| "a press release" | contacts + boilerplate + kit attached · release **published** (live, no deploy — and it notifies journalists **irreversibly**) · a newsroom page exists |
| "a new page" | it is reachable — **linked from navigation or another page**, else it is an orphan URL · **published** (live in ~60s) |

**Note what changed here:** most rows do NOT end in a deploy. Only the chrome
rows do. Running a deploy "to be safe" after a content change is a no-op that
costs a minute and teaches you the wrong model — and *telling the user a deploy
is pending* invents a blocker. See the hard gate above.

## Decision tree — pick a method (→ reference)

| The user wants to… | Method(s) | Read |
|---|---|---|
| Build/edit a page | `createPage` · `updatePage` · `insertSection` · `previewPage` | `references/content.md` |
| Publish a blog post (author + tags + categories + cover) | `createAuthor`→`createCategory`→`createTag`→`createPost`→`publishPost` | `references/content.md` |
| Add a docs page | `createDoc` · `publishDoc` · `getDocsTree` | `references/content.md` |
| **Publish a changelog entry** (version-stamped release notes at `/changelog` + RSS/Atom) | `createChangelog`→`publishChangelog` (`updateChangelog` to correct one) | `references/changelog.md` |
| **Backfill a changelog / blog / newsroom history with its REAL dates** — anything where "the order on the page is wrong" | pass `published_at` on `createChangelog` / `createPost` / `createPressRelease` (or on publish/update to correct) | `references/changelog.md` |
| The changelog page renders in the wrong order (v2.10.0 below v2.2.0) | fix the DATES, or `listChangelog(sort="version")` / the `sort_semver` filter — NEVER Liquid's built-in `sort` | `references/changelog.md` |
| Run a newsroom — publish a press release, with press contacts, a boilerplate and a downloadable media kit | `createPressContact`→`createPressBoilerplate`→`createPressKit`→`createPressRelease`→`publishPressRelease` (or `schedulePressRelease` / `embargoPressRelease`) | `references/press-newsroom.md` |
| **Design the newsroom PAGE** — compose the press components, pick 1 of 6 `newsroom*` starters (the release list self-binds to `press`) | `listSiteTemplates`→`applySiteTemplate`(`newsroom-minimal`\|`-startup-dark`\|`-startup-light`\|`-corporate`\|`-agency`) · or `createPage`→`insertSection`(`sys-press-releases`·`sys-press-kit`·`sys-press-marquee`) — a `featured`/`grid` release index needs `createPage(blocks=[{layout:…}])`, NOT `insertSection` | `references/press-page-design.md` |
| Define a custom content type + fill it (case studies, team, FAQs, products) | `createCollection`→`bulkCreateCollectionRecords`→`updateCollectionRecord`(publish)→`updateCollection`(is_public) | `references/collections.md` |
| Edit header/footer nav | `getNavigation` · `updateNavigation` | `references/content.md` |
| Group pages under a folder + have a menu track it automatically | `createPage`(`is_folder`)→`updatePage`(`parent_id`)→`updateNavigation`(`source: {kind:"folder", folder_id}`) | `references/content.md` |
| Change site settings / SEO / colors | `getSettings` · `updateSettings` | `references/content.md` |
| Connect a custom domain | `addDomain`→`verifyDomain`→`setPrimaryDomain` (or `addSubdomain`) | `references/content.md` |
| Make/edit a reusable component | `createComponent` · `updateComponent` · `publishComponent` · `rollbackComponent` | `references/components.md` |
| Apply a theme / starter site | `listThemes`→`applyTheme` · `listSiteTemplates`→`applySiteTemplate` | `references/templates-deploy.md` |
| Add a landing/opt-in/thank-you/VSL page (clone + adapt — the default) | `listPageTemplates`→`applyPageTemplate` | `references/templates-deploy.md` |
| **Personalise a landing page per prospect** (`/lp/{page}/{id}` — outreach, ABM, a page per account) | `createPage`(`template="dynamic_landing"`)→`publishPage`→`deploySite`; identifier via `?resolve_key=` | `references/dynamic-landing.md` |
| Customise a Liquid template | `getTemplate` · `upsertTemplate` · `previewTemplate` | `references/templates-deploy.md` |
| Deploy / preview a deploy / roll back | `deployPreview`→`deployProduction` · `deploySite` · `deployReadiness` | `references/templates-deploy.md` |
| Build a form / lead capture / contact form | `form_create`→`form_add_field`→`form_publish`→`form_get_embed_snippet` — **kitchen sink only** | `references/forms-booking.md` |
| Build a booking / appointment flow | `booking_template_clone`→`service_create`→`booking_flow_publish` — **kitchen sink only** | `references/forms-booking.md` · `references/booking-model.md` |
| **Build a funnel** — multi-step journey with branching, A/B splits, upsells | `funnel_template_list`→`funnel_template_apply`, then `flow_add_node`/`flow_add_edge` — **kitchen sink only**. NOT the `sys-form-multistep-funnel` component | `references/funnels.md` |
| **Design the BLOG pages** — the `/blog` index + post layout (not writing posts) | `createPage(slug='blog')` · or `template_upsert('templates/blog.liquid')` | `references/blog-page-design.md` |
| **Design a DOCS site / API reference** — the `docs` theme, 3-column reference | `content_import_openapi` **then** `template_apply_theme('docs')` — order matters | `references/docs-site-design.md` |
| Re-embed an agent I ALREADY hired on OPVS (free), or BUY + hire a new one, headlessly (NO dashboard), then get its flow_id to embed | `listAgentRoster`(mine, free)/`listAgentCatalog`(buy)→`hireAgent`→`listHiredAgents` (or CLI `spideriq agent roster\|catalog\|hire\|list`) → `agent_flow_get_embed_snippet` | `references/agent-hire-discover.md` |
| Embed a live AI agent (SDR/support/concierge/booking) on the site | `agent_flow_create`→`agent_flow_publish`→`agent_flow_preview_url`/`agent_flow_get_embed_snippet` | `references/agent-embed.md` |
| Add that agent to the client's OWN React/Vite/Next app (BYOS, npm SDK) | `agent_flow_create`→`agent_flow_publish` then `@spideriq/agent-react` (`<SpiderAgent>`/`useSpiderAgent`) | `references/add-agent-react-app.md` |
| Make the embedded agent READ the page it's on ("what's on this page?" / grounded answers) | `pageContext` prop/attr (no tool — SDK property); auto on hosted pages | `references/page-grounding.md` |
| Design/brand a mountable AI-agent COMPONENT (section/widget/concierge/headless) | `content_create_agent_component` (MCP) · or `createComponent` (marketplace_category=agent) →`insertSection` | `references/agent-component-authoring.md` |
| Host an image/video → CDN URL | `uploadMedia` · `listMedia` | `references/media.md` |
| Browse + insert a marketplace section / bg-video | `listMarketplaceComponents` · `listBgVideos`→`insertSection` | `references/marketplace.md` |
| Sync an external source (Airtable/Stripe/HubSpot/cal/CF) / clone a URL | (integration recipes) | `references/integrations.md` |
| Audit links / readiness / visual-check before shipping | `deployReadiness` · audit recipes | `references/audit.md` |
| Block types, Liquid filters/tags, the css-field rule | — | `references/block-types.md` |
| Two-phase deploy + five-lock defense in depth | `deployPreview`/`deployProduction` | `references/deploy-protocol.md` |
| Forms/booking data model (`flow.json`, cal.com, OAuth-by-invite) | — | `references/booking-model.md` |
| CLI vs MCP map + discovery endpoints | — | `references/tool-surface.md` |

## Post field names (read before any post write)

Use the canonical names on `createPost` / `updatePost`:

| Want to set | Canonical (use this) | Alias now folded server-side |
|---|---|---|
| cover image | **`cover_image_url`** (must end in `_url`) | `cover_image` |
| featured flag | **`is_featured`** | `featured` |
| categories | **`category_ids`** (a LIST of UUIDs) | `category_id` (single → list) |

The API now **accepts the three aliases** (folded into the canonical field, 0.4.1
+ the backend change) — but **any OTHER misnamed field is still silently dropped
with no error**, so prefer the canonical names. Two more post-write gotchas:

- **`cover_image_url` is host-allowlisted** → 422 on an arbitrary host
  (`files.opvs.ai`). Upload via **`uploadMedia`** first and use the CDN url it
  returns (e.g. `media.cdn.spideriq.ai`).
- **`vayapin_pins` wants the public CODE** (`COUNTRY:CODE`, e.g. `DE:KAIMUL` — the
  `vayapin` field from **`vayapinCards`**), NOT the pin UUID (UUID is silently
  dropped). Resolve codes via `vayapinCards` (pinned or query mode) first.

This was the real cause of the "createPost ignores cover_image/author/category"
report. See `learnings/2026-06-11-post-field-names-silently-dropped/`.

## Anti-patterns (always relevant)

- **Claiming a content change needs a deploy.** Posts, pages, docs, press and
  changelog are live on publish (~60s edge cache). Inventing a deploy blocker is
  the more common error of the two.
- **Claiming a TEMPLATE change is live without a deploy.** Templates and theme
  files live in per-tenant KV — only `deploySite` writes them.
- **Deploying because the page "looks stale".** Wait 60s and re-fetch first;
  `s-maxage=60` explains almost every one of these.
- **POSTing to `/api/v1/content/*`.** Those are public READ paths (POST → 405).
  Writes go to `/api/v1/dashboard/content/*`.
- **Using `/api/v1/spideriq/content/...`.** Dead prefix → 404. The base is
  `/api/v1`; method paths in the schema are already correct.
- **Wrong post field names** (`cover_image` / `featured` / `category_id`) →
  silently dropped. Use `cover_image_url` / `is_featured` / `category_ids`.
- **Constructing `/book/<id>` for a `kind='form'` flow.** Canonical URL for both
  kinds is `/f/<id>`; never compose form URLs by hand.
- **Asserting on `body_text_preview` after a visual check of a form/component.**
  The shadow/iframe body is opaque — assert on `dom.shadow_hosts` (the tag name).
- **Inlining `<style>` in a component's `html_template`.** Component CSS goes in
  the `css` field; Tailwind classes don't pierce the Shadow DOM — use
  `:host {}` + `var(--primary)`.
- **Treating SpiderPublish like a generic CMS.** Authoring lands in STORE;
  nothing is publicly visible until SERVE redeploys.

## References (loaded on demand)

- `references/collections.md` — custom collections: define a schema, bulk-fill
  records, publish + expose (is_public), and render them as a dynamic component.
- `references/content.md` — pages, posts, docs, authors/tags/categories, nav,
  settings, domains. **Read before any content write.**
- `references/changelog.md` — version-stamped release notes: the 3-call path,
  setting `published_at` explicitly (the backfill path — the public timeline is
  ordered by DATE), pagination, and the version-sort trap that a template-side
  `| sort: "version"` walks straight into. **Read before any changelog write,
  and before backfilling ANY content type's history.**
- `references/press-newsroom.md` — run a newsroom: press releases plus the
  contact roster, boilerplates and media kits around them. **Read before any
  press write** — scheduling auto-publishes at the set time and embargo mints
  per-journalist preview tokens; publishing notifies journalists irreversibly.
- `references/press-page-design.md` — **design the newsroom PAGE**: compose the
  three press components, the six `newsroom*` starters (1 Phase-1 original + 5 Phase-2 archetypes), the **self-binding** `press` data
  source, and the block-vs-props `layout` asymmetry (both wrong answers fail
  silently), theme-token discipline. **Read before building a newsroom.**
- `references/components.md` — reusable components: create, the css-field rule,
  versions, rollback, update-and-propagate.
- `references/templates-deploy.md` — themes, starter sites, Liquid template
  overrides, the two-phase deploy.
- `references/blog-page-design.md` — **design the blog PAGES**: the three paths to a
  custom `/blog` index + post layout, the "there is no blog component" trap, the
  `/blog/tag/{x}` caveat, and colours-before-templates. **Read before restyling a blog.**
- `references/docs-site-design.md` — **design a docs site**: the `docs` theme, the
  structured API reference, and the one order that matters (import OpenAPI **before**
  applying the theme — otherwise you silently get prose). Plus the four shipped
  limitations to design around. **Read before building docs.**
- `references/funnels.md` — **funnels**: the Flow graph (page/split/embed nodes,
  event edges), clone-a-starter first, and the naming trap that sends agents to the
  `sys-form-multistep-funnel` component instead. **Read before building a funnel.**
- `references/forms-booking.md` — forms + booking flows (build, embed, logic,
  test, share, cal.com calendar invite).
- `references/agent-embed.md` — embed a live OPVS AI agent as a `kind='agent'`
  flow (standalone/inline/concierge/headless), the secret-free binding, the
  3-tier customization, and the surface-vs-conversation honesty split.
- `references/add-agent-react-app.md` — BYOS: put that agent in the client's OWN
  React/Vite/Next app via the `@spideriq/agent-react` npm SDK (`<SpiderAgent>` +
  `useSpiderAgent()`) or zero-dep `@spideriq/agent-core`; SSR-safe, origin-bind gotcha.
- `references/page-grounding.md` — make the embedded agent READ the page it's on:
  the `pageContext` opt-in (prop/attr/loader), auto-vs-selector, the privacy model
  (visible text only, ≤8 KB, forms/passwords/`[data-private]` stripped), and the
  automatic hosted-page (`{url}.md`) path. No CLI/MCP tool — a client-SDK property.
- `references/media.md` — upload/host media, import-from-url, media budget.
- `references/marketplace.md` — browse + insert sections / bg-videos, author
  marketplace assets.
- `references/integrations.md` — Airtable / Stripe / HubSpot / cal.com /
  Cloudflare, clone-a-URL, directory import.
- `references/audit.md` — link audit, deploy readiness, visual-check a page.
- `references/block-types.md` · `references/booking-model.md` ·
  `references/deploy-protocol.md` · `references/tool-surface.md` — reference docs.
- `references/gaps.md` — what the CLI/MCP surfaces do or don't yet expose (read
  if you're on the CLI/MCP path, not this marketplace client).

## Learnings (starting points — verify against current behaviour)

- `learnings/2026-06-11-post-field-names-silently-dropped/` — `cover_image_url`
  / `is_featured` / `category_ids` are the names the backend keeps; wrong names
  vanish silently.
- `learnings/2026-06-11-authoring-is-not-live/` — publish flips a flag; only
  deploy pushes the live site. Two steps.
- `learnings/2026-06-11-dead-spideriq-content-prefix/` — the marketplace base is
  `/api/v1`, writes are on `/dashboard/content`, reads on `/content`; the old
  `/api/v1/spideriq/content` prefix 404'd.
- `learnings/2026-07-12-collection-record-slug-vs-id-asymmetry/` — custom-collection
  records READ by slug but WRITE by id; unknown `data` fields are REJECTED (422),
  not silently dropped like posts.

## See also

- **SpiderMail (`send-receive-email`)** — send/read email on a brand's behalf.
- **spiderflows / lead-search** — find new prospects + their data.
- **workspace skill** — manage brands / team / billing (this manages a brand's
  CONTENT, not the account).
- Token economy: `?format=yaml|md` on every read, or `SPIDERIQ_FORMAT=yaml`.
