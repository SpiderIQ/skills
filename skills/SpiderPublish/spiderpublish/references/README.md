# References — the SpiderPublish procedure + reference layer

The router lives in [`../SKILL.md`](../SKILL.md); the API surface + intent envelope in
`../client/schema.yaml`. These files are the **procedures** (the domain files) and the
**cross-cutting reference** (the docs every domain cites). Each fact has exactly one home — no
domain file re-explains deploy, the block schema, the booking model, or the tool surface.

> The tables below are the **curated entry points, not an inventory.** The directory holds 27
> files; this line claimed "thirteen" long after that stopped being true (corrected 2026-08-14).
> Design pages, per-noun guides and the legacy set are reached from the domain files that cite
> them.

## The five cross-cutting reference docs (read once per session)

| File | Read when… |
|---|---|
| [`tool-surface.md`](tool-surface.md) | First call in any SpiderPublish session — which MCP configuration to use (facade mode: 9 listed / 431 reachable — and why the unfiltered 431-tool list makes some clients silently abort), the three discovery endpoints (`/content/help`, `/content/help/block-fields`, `/dashboard/idap/merge-tags`), CLI-vs-MCP-vs-HTTP, and the "prefer one-shot tools" rule. |
| [`multi-workspace-setup.md`](multi-workspace-setup.md) | The brand owns MORE THAN ONE client (agency, reseller), or you hit `AMBIGUOUS_TENANT` — the 5-rung resolution order, one-workspace-per-client vs pass-`workspace`-every-call, the `spideriq.json` keys that are actually read (and the ones silently ignored), and the three HOST bugs that make a correct config look broken: the global/local name collision (`client is closing: EOF`), the sibling crash that disables every server in the file (`unknown tool name: call_mcp_tool` — NOT the same bug as a truncated tool list), and the concurrent-`npx` cache race (`ECOMPROMISED`). |
| [`block-types.md`](block-types.md) | Before composing any non-component block — the 15 default block types + the exact `data.*` keys the default theme reads (wrong names render BLANK, not 422), the `css`-field-not-`<style>` Shadow-DOM rule, and the canonical 6 anti-patterns. |
| [`deploy-protocol.md`](deploy-protocol.md) | Before any production mutation/deploy — the two-phase `?dry_run=true` → `?confirm_token=cft_…` gate (opt-in vs safe-default), the five-lock tenant defense, the `ConfirmTokenError` 403/409/410 map, and "verify the 200 with a visual check." |
| [`booking-model.md`](booking-model.md) | Before any form/booking work — the `booking_flows` `kind` discriminator, the `flow` JSONB shape, cal.com as slot-resolver, calendar-OAuth-by-invite, the `/f/<id>` URL surface (never compose `/book/<id>` by hand — the W13 incident), the 25 field types, and the Rule 62 visual-check assertion. |

## The nine domain procedure files

| File | Read when… |
|---|---|
| [`content.md`](content.md) | Building or editing a landing page, blog post, docs page, nav menu, custom domain, site settings, a dynamic (data-bound) list/item page, a scroll-video hero — or duplicating, locking, restoring, exporting, or previewing a page. |
| [`collections.md`](collections.md) | Defining a CUSTOM content type (case studies, team, FAQs, products) — declare a `schema_json`, bulk-fill records, publish (gated `status` transition), expose via `is_public`, and render as a `kind='dynamic'` component. The reads-use-slug / writes-use-id trap and the reject-unknown-fields rule. |
| [`components.md`](components.md) | Creating a reusable component, finding one by slug, propagating an edit to every consuming page (`component_update_and_propagate`), rolling a component back, or uploading a gallery preview image. |
| [`templates-deploy.md`](templates-deploy.md) | Applying a theme, applying a curated starter site, previewing a deploy without going live, or rolling back a bad deploy. |
| [`forms-booking.md`](forms-booking.md) | Building a form or booking flow, wiring conditional logic/variables, embedding a form, cloning a form/booking template, test-submitting, locking for review, sharing a standalone URL, or inviting staff to connect calendars. |
| [`agent-hire-discover.md`](agent-hire-discover.md) | Discovering, hiring, or switching an OPVS agent **headlessly** (no dashboard) and getting its `flow_id` to embed — `list_agent_catalog`→`hire_agent`→`list_hired_agents` (CLI `spideriq agent catalog\|hire\|list`), the component_id-not-profile_id hire key, the `status` discriminator (not HTTP 402/202), and the origin-allowlist-or-403 rule. The switch-Aisha→Zara walkthrough. |
| [`agent-embed.md`](agent-embed.md) | Embedding a live OPVS AI agent (SDR/support/concierge/booking) on the site as a `kind='agent'` flow — `agent_flow_*` tools, the secret-free binding, standalone/inline/concierge/headless mounts, the 3-tier customization, and the surface-vs-live-conversation honesty split. |
| [`agent-component-authoring.md`](agent-component-authoring.md) | Designing a mountable, brand-skinned `<opvs-agent>` marketplace COMPONENT (distinct from the agent flow) — `content_create_agent_component`, the four form-factors (section/widget/concierge/headless), the inline `--opvs-agent-*` token skin (the css-column-is-bypassed trap), the manual `createComponent` emission recipe, and browsing by `agent_form_factor`. |
| [`media.md`](media.md) | Bulk-uploading a folder of images, importing media (including video) from a URL, or auditing/trimming a tenant's media footprint. |
| [`marketplace.md`](marketplace.md) | Browsing + inserting a marketplace section, browsing CRO components, authoring a site template or background video, picking a background video, or writing the `agent_meta` that makes an asset agent-discoverable. |
| [`integrations.md`](integrations.md) | Syncing Airtable → directory, wiring a cal.com booking flow, a Cloudflare custom domain, mirroring a form to HubSpot, a Stripe pricing table, filling a form from an IDAP record, cloning a public URL / Tailwind page into a template, or bulk-importing directory listings. |
| [`audit.md`](audit.md) | Auditing a tenant's site before a deploy, doing an audit-driven edit pass, running the deploy-readiness probe, link-auditing for 404s, or visual-checking a published page. |

## API surface — the correct bases

| Operation | Base | Auth |
|---|---|---|
| Authoring (create/update/delete/publish/list-with-drafts) | `POST/PATCH/GET /api/v1/dashboard/content/...` (or project-scoped `/api/v1/dashboard/projects/{pid}/content/...`) | Bearer PAT |
| Components | `/api/v1/dashboard/content/components/...` | Bearer PAT |
| Templates / themes / deploy | `/api/v1/dashboard/templates/...` and `/api/v1/dashboard/content/deploy...` | Bearer PAT |
| Booking/forms authoring | `/api/v1/dashboard/booking/...` (public submit: `/api/v1/booking/{flow_id}/submit`) | Bearer PAT |
| Genuinely public reads (search, featured, marketplace browse, vayapin, `/help`) | `/api/v1/content/...` | none |

The legacy `/api/v1/spideriq/content` prefix is **dead** — never use it.
