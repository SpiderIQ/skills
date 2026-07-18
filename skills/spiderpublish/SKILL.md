---
name: spiderpublish
description: >
  Author, publish, and deploy on SpiderPublish — SpiderIQ's multi-tenant CMS +
  Liquid site runtime. Build pages, blog posts, docs, reusable components,
  navigation, themes, media, and custom domains for a brand's own website, then
  deploy to the Cloudflare edge. Trigger on: "add a page", "write a blog post",
  "edit the header", "create an author", "set up categories/tags", "apply a
  theme", "connect a custom domain", "publish the blog", "deploy the site", or a
  tenant name (sms-chemicals.com, demo.spideriq.ai). Authoring lives in STORE
  (PostgreSQL, tenant-isolated); nothing reaches end users until you DEPLOY.
  SpiderPublish is a runtime, not a generic CMS — generic web knowledge gets the
  five-lock tenant defense and the publish-vs-deploy split wrong. Per-tenant,
  PAT-scoped. NOT for sending email (use SpiderMail) or finding prospects (use
  spiderflows / lead-search).
version: "0.7.0"
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

Your job: land changes in STORE correctly, then trigger SERVE via **deploy**.

```
  AUTHOR (this skill, PAT) ──▶ STORE (Postgres, tenant rows) ──deploy──▶ SERVE (CF edge) ──▶ visitors
   createPage/createPost        draft|published                          live site
   publishPost flips a flag     (still not live)                         (only updates on deploy)
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

**Two rules that bite every agent new to SpiderPublish:**

1. **AUTHORING IS NOT LIVE.** Creating/editing a page or post only changes
   STORE. `publishPost`/`publishPage` flips a row to *published* (visible to the
   API) — the **live site does not change until you `deploySite`** (or
   `deployPreview` → `deployProduction`). Publishing and deploying are two
   separate steps; you usually need both. Telling the user "it's live" after a
   create/publish, without a deploy, is a silent lie.

2. **DESTRUCTIVE OPS ON A PRODUCTION TENANT ARE TWO-PHASE.** `deletePage`,
   `applyTheme`, `deployProduction`, `deletePage`, `updateSettings`, and the
   deploy itself accept `dry_run: true` → you get a **preview + `confirm_token`
   (`cft_…`)**; pass that token back to actually mutate. On a production tenant,
   ALWAYS preview first. (Envelopes: 410 expired · 409 consumed · 403 mismatch.)

**Why a hard gate, not a footnote:** the publish-vs-deploy confusion and
"delete looked safe" are the two highest-frequency SpiderPublish mistakes.
Confirm the deploy step happened before reporting a change as live.

</HARD-GATE>

## Approach

1. **Orient** — `getHelp` (the full authoring reference) if you don't know the
   site shape; `listPages` / `listPosts` / `listComponents` to see what exists
   (including drafts).
2. **Author** — `createPage` / `createPost` / `createDoc` (+ `createAuthor`,
   `createTag`, `createCategory` to set up taxonomy first). Body is **Tiptap
   JSON**, not HTML.
3. **Assemble** — `insertSection` to drop components onto a page; `applyTheme`
   for look; `updateNavigation` / `updateSettings` for chrome.
4. **Publish** — `publishPost` / `publishPage` / `publishDoc` (draft →
   published).
5. **Deploy** — `deployPreview` → `deployProduction` (safe), or `deploySite`
   (one-shot). THIS is the step that makes it live.
6. **Verify** — `deployStatus`; on a published URL, a visual check asserting on
   `dom.shadow_hosts` (NOT `body_text_preview`) for embedded components/forms.

## Decision tree — pick a method (→ reference)

| The user wants to… | Method(s) | Read |
|---|---|---|
| Build/edit a page | `createPage` · `updatePage` · `insertSection` · `previewPage` | `references/content.md` |
| Publish a blog post (author + tags + categories + cover) | `createAuthor`→`createCategory`→`createTag`→`createPost`→`publishPost` | `references/content.md` |
| Add a docs page | `createDoc` · `publishDoc` · `getDocsTree` | `references/content.md` |
| Define a custom content type + fill it (case studies, team, FAQs, products) | `createCollection`→`bulkCreateCollectionRecords`→`updateCollectionRecord`(publish)→`updateCollection`(is_public) | `references/collections.md` |
| Edit header/footer nav | `getNavigation` · `updateNavigation` | `references/content.md` |
| Change site settings / SEO / colors | `getSettings` · `updateSettings` | `references/content.md` |
| Connect a custom domain | `addDomain`→`verifyDomain`→`setPrimaryDomain` (or `addSubdomain`) | `references/content.md` |
| Make/edit a reusable component | `createComponent` · `updateComponent` · `publishComponent` · `rollbackComponent` | `references/components.md` |
| Apply a theme / starter site | `listThemes`→`applyTheme` · `listSiteTemplates`→`applySiteTemplate` | `references/templates-deploy.md` |
| Add a landing/opt-in/thank-you/VSL page (clone + adapt — the default) | `listPageTemplates`→`applyPageTemplate` | `references/templates-deploy.md` |
| Customise a Liquid template | `getTemplate` · `upsertTemplate` · `previewTemplate` | `references/templates-deploy.md` |
| Deploy / preview a deploy / roll back | `deployPreview`→`deployProduction` · `deploySite` · `deployReadiness` | `references/templates-deploy.md` |
| Build a form / booking flow | (forms surface) | `references/forms-booking.md` |
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

- **Reporting a change as "live" without a deploy.** Publish ≠ deploy. The live
  site only updates on `deploySite` / `deployProduction`.
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
- `references/components.md` — reusable components: create, the css-field rule,
  versions, rollback, update-and-propagate.
- `references/templates-deploy.md` — themes, starter sites, Liquid template
  overrides, the two-phase deploy.
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
