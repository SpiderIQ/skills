---
name: spiderpublish
description: >
  Author, publish, deploy on SpiderPublish — SpiderIQ's multi-tenant CMS +
  booking runtime. Trigger on: "add a page", "edit the header", "create a
  contact form", "publish the blog", "embed this form", "set up booking",
  "connect a custom domain", "deploy the tenant site", or a tenant name
  (sms-chemicals.com, demo.spideriq.ai). Covers pages, posts, docs,
  components, navigation, themes, forms/booking (kind='form' OR 'booking'
  — both render at /f/<id>), site cloning, two-phase deploy gate.
  SpiderPublish has a five-lock tenant defense; generic web knowledge
  gets it wrong.
---

# SpiderPublish

SpiderPublish is a **runtime**, not a generic CMS. Three layers:

- **STORE** — FastAPI + PostgreSQL. Every authored thing (page, post,
  component, form, setting, template) lives here in a tenant-isolated row.
  Nothing is "on disk."
- **SERVE** — Cloudflare Workers (`dispatch` → `liquid-renderer`) reads
  templates from per-tenant KV and fetches content from STORE at request
  time. Forms render at `/f/<flow_id>` (same URL for `kind='form'` AND
  `kind='booking'` — disambiguated by the `kind` column).
- **MANAGE** — dashboard, MCP (87 atomic or 134+ kitchen-sink), CLI
  (`spideriq`), VSCode extension. All four call the same STORE API; pick by
  ergonomics.

The agent's job is to land changes in STORE correctly, then trigger SERVE
via deploy.

---

<HARD-GATE name="tenant-scope">

**Before any mutation, run the tenant-scope verifier and paste its output.**

```bash
./scripts/verify-tenant-scope.sh
# {"ok":true,"project_id":"cli_xxx","spideriq_json":"...","exit":0}
```

Exit `0` → safe. Exit `1` (mismatch), `2` (no `spideriq.json`), `3` (no PAT) → **STOP and fix**.

**Why a script, not prose:** language-only "remember to check scope" rules
get skipped under ship pressure (Hyperframes commit `190f1ec` proved this
empirically). Running the script + pasting output makes the check auditable
and unmissable. Same pattern Hyperframes uses for their `w2h-verify.mjs`,
`lint_source.py`, `contrast-report.mjs`.

</HARD-GATE>

<HARD-GATE name="deploy-protocol">

**Authoring lives in STORE; nothing reaches end users until you deploy.**

For destructive ops on **production tenants**, wrap in the two-phase
confirm flow:

```bash
./scripts/dry-run-then-confirm.py \
  --url https://spideriq.ai/api/v1/dashboard/projects/$PID/content/deploy \
  --method POST \
  --description "Deploy <tenant> to production" \
  --body '{}'
```

The wrapper handles `?dry_run=true` → preview → `?confirm_token=cft_…`,
plus the 410 (expired), 409 (consumed), 403 (mismatch) envelopes. Distinct
exit codes — see [`scripts/README.md`](../../scripts/README.md).

**Honest framing:** Phase 11+12 is **OPT-IN**, not mandatory. The dashboard
wraps it automatically; the CLI's interactive prompts do the same; direct
API/MCP callers must choose. On dev tenants, skipping it is fine. On prod
tenants, always opt in.

For every recipe's last step → [`reference/deploy-protocol.md`](reference/deploy-protocol.md).

</HARD-GATE>

---

## Intent → recipe (cheap lookup, no LLM cycles)

Don't read the full decision tree if you already know roughly what the user
wants. Run:

```bash
./scripts/find-tool-for-intent.sh "<user's intent in plain English>"
```

Returns top 3 candidate recipes by keyword overlap. ~50 tokens vs. ~3000
for re-reading this whole file.

---

## Decision tree — pick a recipe

| The user wants to… | Read |
|---|---|
| create + publish a landing page | `recipes/content/landing-page.md` |
| publish a blog post | `recipes/content/blog-post.md` |
| add a page to the docs tree | `recipes/content/docs-page.md` |
| apply a curated starter site (browse + clone) | `recipes/content/apply-site-template.md` |
| add a dynamic LIST page (iterates posts/docs/listings) | `recipes/content/dynamic-list-page.md` |
| add a dynamic ITEM page (`/blog/<slug>` pattern) | `recipes/content/dynamic-item-page.md` |
| change site-wide settings (SEO defaults, colors, analytics) | `recipes/content/update-site-settings.md` |
| add a scroll-linked video hero | `recipes/content/scroll-video-hero.md` |
| iterate on a page with live preview | `recipes/content/preview-iteration.md` |
| lock a page while a human reviews | `recipes/content/lock-page-during-review.md` |
| import a site from Tilda | `recipes/content/import-tilda-site.md` |
| connect a custom domain | `recipes/content/custom-domain.md` |
| apply a theme | `recipes/content/apply-theme.md` |
| edit the navigation menus | `recipes/content/navigation.md` |
| override a single section without forking the theme | `recipes/content/section-override.md` |
| edit header/footer once, propagate site-wide | `recipes/components/update-and-propagate.md` |
| iterate a component safely with rollback | `recipes/components/rollback-component.md` |
| find a component without paginating | `recipes/components/find-component.md` |
| create a new library component (Tier 1–4) | `recipes/components/create-component.md` |
| upload a preview thumbnail / MP4 for a component | `recipes/components/upload-component-preview.md` |
| browse marketplace + insert a section into a page | `recipes/marketplace/browse-and-insert-section.md` |
| **browse CRO components (urgency, scarcity, social proof, capture popups, sticky bars, timers, GEO primitives)** | `recipes/marketplace/browse-cro-components.md` |
| publish a curated site template to the marketplace (super_admin) | `recipes/marketplace/author-site-template.md` |
| publish a bg-video clip to the marketplace (super_admin) | `recipes/marketplace/author-bg-video.md` |
| suggest agent-meta tags for a marketplace asset | `recipes/marketplace/suggest-agent-meta.md` |
| design a form's look + per-question media | `recipes/booking/build-form.md` |
| build a full lead-gen form end-to-end | `recipes/booking/build-lead-gen-form.md` |
| clone an existing form template | `recipes/booking/clone-form-template.md` |
| set up a booking flow (calendar slots) | `recipes/booking/clone-booking-template.md` |
| invite staff to connect their calendar | `recipes/booking/invite-staff-calendar.md` |
| embed a form on an external site (inline / popup) | `recipes/booking/embed-form.md` |
| **embed a form INSIDE a SpiderPublish page** | `recipes/booking/form-as-page-section.md` |
| **share a form via standalone URL (QR / bio / reviewer link)** | `recipes/booking/share-form-standalone.md` |
| **add conditional logic + variables to a form** | `recipes/booking/add-logic-and-variables.md` |
| import directory listings from IDAP | `recipes/directory/import-listings.md` |
| bulk upload media to SpiderMedia | `recipes/media/bulk-upload.md` |
| fill IDAP records from form submissions | `recipes/integrations/idap-fill-from-form.md` |
| clone a public URL into a Liquid template (SpiderClone) | `recipes/clone/url-to-template.md` |
| run a content audit before shipping | `recipes/audit/audit-driven-edit.md` |
| audit + fix all internal links | `recipes/audit/link-audit.md` |
| audit + fix a content issue end-to-end | `recipes/audit/audit-and-fix.md` |
| **visual-check a deployed page (Playwright sidecar; Rule 62)** | `recipes/audit/visual-check-a-page.md` |
| **pre-flight deploy readiness checklist** | `recipes/audit/deploy-readiness.md` |

All recipes are authored. The 16 ported from the public starter kit
(designer-kit) — proven in production by HeyGen-class agent runs — were
joined in v0.3.0 (2026-05-24) by 14 new recipes + 5 reference docs, then
v0.4.0 (2026-05-24) added 14 more: 3 forms (page-section + standalone + logic),
4 content (site-template + dynamic pages + settings), 3 components/audit
(preview-upload + visual-check + deploy-readiness), and 4 marketplace
(CRO catalog + author-site-template + author-bg-video).

---

## Tool surface — pointer only

**Three discovery endpoints** (call once per session, cache):

| Endpoint | Returns |
|---|---|
| `GET /api/v1/content/help` | ~2,867-token YAML reference (block types, 14 Liquid filters, 4 tags) |
| `GET /api/v1/content/help/block-fields` | Accepted shapes per block-type |
| `GET /api/v1/dashboard/idap/merge-tags?page_id={id}` | Merge-tag variables for dynamic pages |

**Two MCP packages** — pick by runtime ceiling:

| Package | Tools | Runtime |
|---|---|---|
| `@spideriq/mcp-publish` | 87 atomic (content+media+booking minus form_*) | Antigravity, Claude Desktop, any 128-tool ceiling |
| `@spideriq/mcp` | 134+ kitchen sink (adds form_*) | Claude Code, Cursor, Codex |

Prefer one-shot tools over multi-step choreography
(`content_get_component_by_slug` over `list_components` + filter;
`form_create_from_template` over `form_create` + N × `form_add_field`).

Full map: [`reference/tool-surface.md`](reference/tool-surface.md).

---

## Anti-patterns (always relevant)

- **Constructing `/book/<id>` for a `kind='form'` flow.** Canonical URL for
  both kinds is `/f/<id>`. Legacy `/book/<id>` 301-redirects for
  `kind='booking'` but silent-fails for `kind='form'` (the W13 production
  incident). Always call `form_preview_url` / `form_get_embed_snippet`;
  never compose URLs by hand.
- **Asserting on `body_text_preview` after `content_visual_check` for a
  form.** Cross-origin iframe body is opaque. Assert on
  `dom.shadow_hosts.includes("spideriq-form")` instead. Same rule for any
  shadow-host custom element.
- **Inlining `<style>` blocks inside `html_template`.** Custom component CSS
  goes in the separate `css` field; the renderer wraps it in Shadow DOM and
  Tailwind classes don't pierce the boundary.
- **Paginating `list_components` to find one by slug.** Use
  `content_get_component_by_slug` — one call, no pagination.
- **Skipping `?dry_run=true` on destructive ops in production.** Opt-in by
  design, but in production always opt in (use the wrapper script above).
- **Treating SpiderPublish like a generic CMS.** Authoring lands in STORE;
  nothing is publicly visible until SERVE redeploys.
- **Confusing Forms / SpiderFlow / Funnels.** Forms = `kind='form'` rows in
  `booking_flows`. SpiderFlow is the public attribute namespace
  (`data-spiderflow-*`) — same product, code-level identifier. Funnels
  (future) is `kind='funnel'`. Don't conflate the names.

---

## See also

- [`scripts/README.md`](../../scripts/README.md) — full script inventory + the "why scripts not prose" rationale
- [`reference/deploy-protocol.md`](reference/deploy-protocol.md) — full two-phase pipeline + five-lock defense
- [`reference/block-types.md`](reference/block-types.md) — block model + the `css`-field rule + validators
- [`reference/tool-surface.md`](reference/tool-surface.md) — CLI vs MCP map + discovery endpoints
- [`reference/booking-model.md`](reference/booking-model.md) — `flow.json` / `schema.json`, cal.com, OAuth-by-invite
- [`../_shared/auth.md`](../../_shared/auth.md) — the PAT auth pattern (shared with `spidermail`, `spidergate`)
