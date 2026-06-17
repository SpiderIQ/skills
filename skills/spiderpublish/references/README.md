# References — the SpiderPublish procedure + reference layer

The router lives in [`../SKILL.md`](../SKILL.md); the API surface + intent envelope in
`../client/schema.yaml`. These twelve files are the **procedures** (eight domain files) and the
**cross-cutting reference** (four docs every domain cites). Each fact has exactly one home — no
domain file re-explains deploy, the block schema, the booking model, or the tool surface.

## The four cross-cutting reference docs (read once per session)

| File | Read when… |
|---|---|
| [`tool-surface.md`](tool-surface.md) | First call in any SpiderPublish session — which MCP package to install (`@spideriq/mcp-publish` 87 atomic vs `@spideriq/mcp` 134+ kitchen-sink), the three discovery endpoints (`/content/help`, `/content/help/block-fields`, `/dashboard/idap/merge-tags`), CLI-vs-MCP-vs-HTTP, and the "prefer one-shot tools" rule. |
| [`block-types.md`](block-types.md) | Before composing any non-component block — the 15 default block types + the exact `data.*` keys the default theme reads (wrong names render BLANK, not 422), the `css`-field-not-`<style>` Shadow-DOM rule, and the canonical 6 anti-patterns. |
| [`deploy-protocol.md`](deploy-protocol.md) | Before any production mutation/deploy — the two-phase `?dry_run=true` → `?confirm_token=cft_…` gate (opt-in vs safe-default), the five-lock tenant defense, the `ConfirmTokenError` 403/409/410 map, and "verify the 200 with a visual check." |
| [`booking-model.md`](booking-model.md) | Before any form/booking work — the `booking_flows` `kind` discriminator, the `flow` JSONB shape, cal.com as slot-resolver, calendar-OAuth-by-invite, the `/f/<id>` URL surface (never compose `/book/<id>` by hand — the W13 incident), the 25 field types, and the Rule 62 visual-check assertion. |

## The eight domain procedure files

| File | Read when… |
|---|---|
| [`content.md`](content.md) | Building or editing a landing page, blog post, docs page, nav menu, custom domain, site settings, a dynamic (data-bound) list/item page, a scroll-video hero — or duplicating, locking, restoring, exporting, or previewing a page. |
| [`components.md`](components.md) | Creating a reusable component, finding one by slug, propagating an edit to every consuming page (`component_update_and_propagate`), rolling a component back, or uploading a gallery preview image. |
| [`templates-deploy.md`](templates-deploy.md) | Applying a theme, applying a curated starter site, previewing a deploy without going live, or rolling back a bad deploy. |
| [`forms-booking.md`](forms-booking.md) | Building a form or booking flow, wiring conditional logic/variables, embedding a form, cloning a form/booking template, test-submitting, locking for review, sharing a standalone URL, or inviting staff to connect calendars. |
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
