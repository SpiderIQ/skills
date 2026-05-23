---
name: spiderpublish
description: >
  Author, publish, and deploy websites on SpiderPublish — the multi-tenant content + booking
  runtime by SpiderIQ. Use whenever the user wants to: create or edit pages, blog posts,
  docs, components, navigation, themes, or site settings on a SpiderPublish tenant; build,
  clone, embed, or publish a form or booking flow (kind='form' or kind='booking' — same
  data model, same /f/<id> URL surface); clone any public URL into a reusable Liquid
  template; deploy a tenant site to Cloudflare's edge; or work with the `spideriq` CLI or
  any of the `@spideriq/mcp*` packages. Trigger on phrases as short as "add a page",
  "update the header", "create a contact form", "publish the blog", "embed this form",
  "connect a custom domain", or a tenant identifier like sms-chemicals.com or
  demo.spideriq.ai. SpiderPublish has a five-lock tenant-isolation defense and an opt-in
  two-phase confirm-token gate on destructive operations — generic CMS / HTML / JS
  knowledge will get those wrong.
---

# SpiderPublish

SpiderPublish is a **runtime**, not a generic CMS. Three layers:

- **STORE** — FastAPI + PostgreSQL. Every authored thing (page, post, component, form,
  setting, template) lives here in a tenant-isolated row. Nothing is "on disk."
- **SERVE** — Cloudflare Workers (`dispatch` → `liquid-renderer`) reads templates from
  per-tenant KV and fetches content from STORE at request time. Forms render at
  `/f/<flow_id>` (same URL for `kind='form'` AND `kind='booking'` — disambiguated by the
  `kind` column).
- **MANAGE** — dashboard, MCP (87 atomic or 134+ kitchen-sink), CLI (`spideriq`), VSCode
  extension. All four call the same STORE API; pick by ergonomics.

The agent's job is to land changes in STORE correctly, then trigger SERVE via deploy.

---

<HARD-GATE name="tenant-scope">

**Before any mutation, verify the working tenant.** Every authoring action targets exactly
one client. Targeting the wrong one writes to a real customer's site — and Lock 5 won't
catch it if your PAT happens to scope to the same client.

1. Run `spideriq whoami` — confirm the bound `project_id` AND the PAT's `client_id` match.
2. A `spideriq.json` must exist somewhere in the cwd tree (the CLI walks up). Confirm with
   `cat $(find . -maxdepth 3 -name spideriq.json | head -1)`.
3. If missing or wrong, `spideriq use <client_id|brand-slug>` first.

**Why this matters:** there is no "default tenant." Without scope, the CLI defaults to
deprecated unscoped paths that don't write a tenant-audit row — the five-lock defense
silently degrades.

</HARD-GATE>

<HARD-GATE name="deploy-protocol">

**Authoring lives in STORE; nothing reaches end users until you deploy.**

```
spideriq content deploy              # interactive — preview table → [y/N] → live
spideriq content deploy --json       # non-interactive — emits preview envelope + token
spideriq content deploy --confirm cft_…   # second call, consumes the token
spideriq content deploy --yolo       # legacy one-shot, no preview (avoid on production)
```

The Phase 11+12 `dry_run` / `confirm_token` gate is **OPT-IN** on 10 destructive endpoints
(delete page, publish/unpublish page, update settings, apply theme, delete/publish/archive
component, deploy preview, deploy production, legacy deploy). The dashboard wraps it
automatically; the CLI's interactive prompts do the same; direct MCP / API callers must
choose to opt in.

**Why opt-in, not mandatory:** forcing the gate on every call would block valid automation.
But on production tenants always opt in — `?dry_run=true` first, then `?confirm_token=cft_…`.
Tokens expire in 5 minutes.

For every recipe's last step → `reference/deploy-protocol.md`.

</HARD-GATE>

---

## Decision tree — pick a recipe

| The user wants to… | Read |
|---|---|
| create + publish a landing page | `recipes/content/landing-page.md` |
| publish a blog post | `recipes/content/blog-post.md` |
| add a page to the docs tree | `recipes/content/docs-page.md` |
| add a scroll-linked video hero | `recipes/content/scroll-video-hero.md` |
| edit header/footer once, propagate site-wide | `recipes/components/update-and-propagate.md` |
| override a single section without forking the theme | `recipes/content/section-override.md` |
| edit the navigation menus | `recipes/content/navigation.md` |
| connect a custom domain | `recipes/content/custom-domain.md` |
| apply a theme | `recipes/content/apply-theme.md` |
| create a new library component (Tier 1–4) | `recipes/components/create-component.md` |
| iterate safely with rollback | `recipes/components/rollback-component.md` |
| find a component without paginating | `recipes/components/find-component.md` |
| create a form (contact / lead-gen / NPS / intake / job-app) | `recipes/booking/build-form.md` |
| clone an existing form template | `recipes/booking/clone-form-template.md` |
| set up a booking flow (calendar slots) | `recipes/booking/clone-booking-template.md` |
| invite staff to connect their calendar | `recipes/booking/invite-staff-calendar.md` |
| embed a form on an external site (inline / popup) | `recipes/booking/embed-form.md` |
| import directory listings from IDAP | `recipes/directory/import-listings.md` |
| clone a public URL into a Liquid template (SpiderClone) | `recipes/clone/url-to-template.md` |

---

## Tool surface — pointer only

**Three discovery endpoints** (call once per session, cache the response):

| Endpoint | Returns | Use for |
|---|---|---|
| `GET /api/v1/content/help` | ~2,867-token YAML reference | Block types, 14 Liquid filters, 4 custom tags, full content vocab |
| `GET /api/v1/content/help/block-fields` | Accepted shapes per block-type | Resolving `ContentBlock.data` validation errors |
| `GET /api/v1/dashboard/idap/merge-tags?page_id={id}` | Merge-tag variables | Dynamic-page authoring (`dynamic_list` / `dynamic_item` templates) |

**Two MCP packages** — pick by runtime:

| Package | Tools | Runtime |
|---|---|---|
| `@spideriq/mcp-publish` | 87 (atomic, content+media+booking minus form_*) | Antigravity, Claude Desktop, any with the 128-tool ceiling |
| `@spideriq/mcp` | 134+ (kitchen sink + form_* tools) | Claude Code, Cursor, Codex — no ceiling |

Prefer one-shot tools over multi-step choreography (`content_get_component_by_slug` over
`list_components` + filter; `form_create_from_template` over `form_create` +
N × `form_add_field`).

Full map: `reference/tool-surface.md`.

---

## Anti-patterns (always relevant)

- **Constructing `/book/<id>` for a `kind='form'` flow.** The canonical URL for both kinds
  is `/f/<id>`. Legacy `/book/<id>` 301-redirects for `kind='booking'` but silent-fails for
  `kind='form'` — this caused a production incident with 8 broken iframes shipped to a
  customer. Always call `form_preview_url` / `form_get_embed_snippet`; never compose URLs
  by hand.
- **Asserting on `body_text_preview` after `content_visual_check` for a form.** Cross-origin
  iframe body is opaque to the parent page's DOM. Assert on
  `dom.shadow_hosts.includes("spideriq-form")` instead. Same rule for any shadow-host
  custom element.
- **Inlining `<style>` blocks inside `html_template`.** Custom component CSS goes in the
  separate `css` field; the renderer wraps it in Shadow DOM and Tailwind classes don't
  pierce the boundary.
- **Paginating `list_components` to find one by slug.** Use
  `content_get_component_by_slug` — one call, no pagination.
- **Skipping `?dry_run=true` on destructive ops in production tenants.** It's opt-in by
  design, but in production always opt in.
- **Treating SpiderPublish like a generic CMS.** Authoring lands in STORE; nothing is
  publicly visible until SERVE redeploys.
- **Confusing Forms / SpiderFlow / Funnels.** Forms = `kind='form'` rows in `booking_flows`.
  SpiderFlow is the public attribute namespace (`data-spiderflow-*`) — same product,
  code-level identifier. Funnels (future) is `kind='funnel'`. Don't conflate the names.

---

## See also

- `reference/deploy-protocol.md` — full two-phase pipeline + five-lock defense
- `reference/block-types.md` — block model + the `css`-field rule + validators
- `reference/tool-surface.md` — CLI vs MCP map + discovery endpoints + when to use each
- `reference/booking-model.md` — `flow.json` / `schema.json` shape, cal.com slot-resolver,
  calendar-OAuth-by-invite mechanics
- `../_shared/auth.md` — the PAT auth pattern (shared with `spidermail`, `spidergate`)
