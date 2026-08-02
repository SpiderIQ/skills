# Audit — audit-and-fix, audit-driven edit, deploy readiness, link audit, visual check

The pre-flight and verification surface. `content_deploy_readiness`, the link auditor
(`/api/v1/dashboard/content/audit/links` and the project-scoped variant), and the Playwright
`content_visual_check` sidecar catch the silent-200 and silent-blank failures that unit tests
miss. The Rule 62 form assertion (`dom.shadow_hosts.includes("spideriq-form")`, NEVER
`body_text_preview`) lives in [`booking-model.md`](booking-model.md).

**Read when:** auditing a tenant's site before a deploy, doing an audit-driven edit pass, running
the deploy-readiness probe, auditing links for 404s, or visual-checking a published page.


---

## Audit And Fix

Export a page with its audit, parse the findings, fix the most-confident ones, push back. Closes the loop where an AI agent edits a page without ever seeing what's already on it.

### When to use

- You're about to edit a page and only have its slug — no inlined component bodies, no idea what's currently shipping.
- A client reports "the website looks broken" and you want a structured diagnostic before opening the editor.
- You're about to `content_deploy_site_production` and want a per-page health check across the whole site.
- You want to round-trip a page through your IDE — export as archive, edit on disk with native diffs, push back.

### The one-shot call

```bash
GET /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/export?format=json
# → { page, components: [{slug, version, html_template, js, css, props_schema, dependencies, agent_meta, kind, layouts}],
#     settings, domains, audit: {site_level, page_level, block_level, component_level, summary}, exported_at, spideriq_version }
```

**MCP tool:** `content_export_page({page_id, format})` — ships in `@spideriq/mcp-publish@1.10.0+` and kitchen-sink `@spideriq/mcp@1.10.0+`. `format` defaults to `json`.

**CLI:** `spideriq content export <page_id> [--format json|md|archive] [--output <path>]` — ships in `@spideriq/cli@1.10.0+`. JSON to stdout by default. `--format md` returns Markdown for human review. `--format archive` returns a ZIP byte stream — pipe to a file, then unzip into a working directory:

```
exported/
├── page.json                              # the page row (blocks, SEO, template)
├── components/
│   ├── sys-cta@1.0.0.json                 # one file per unique component referenced
│   └── sys-scroll-sequence@1.1.0.json     # full body inlined (html_template + js + css + props_schema)
├── settings.json                          # site-level content_settings row
├── domains.json                           # content_domains rows
├── audit.md                               # human-readable audit (Markdown)
└── manifest.json                          # archive metadata (format_version, exported_at, page_slug)
```

**Runnable example:** examples/content-export-and-audit.sh — covers all three formats end-to-end.

### What gets audited

10 v1 rules grouped by scope. Each finding carries `{rule_id, severity, scope, target, message, suggested_fix?}`.

| Severity | Rule | Catches |
|---|---|---|
| `error` | `block.scroll_sequence_empty_frames` | scroll-sequence component bound with 0 frames — the section will render blank at runtime |
| `error` | `site.no_verified_primary_domain` | published pages have no public URL |
| `warn` | `page.multiple_scroll_sequences` | 2+ scroll sequences on one page (each loads ~10 MB of frame images) |
| `warn` | `page.empty_seo_title` / `page.empty_seo_description` | search engines fall back to less specific text |
| `warn` | `site.missing_favicon` / `site.missing_default_og_image` | missing site-level branding for browsers + social shares |
| `warn` | `component.kind_null_with_dependencies` | latent Tier 3 — component declares dependencies (e.g. gsap) but `kind=NULL`, so it's invisible to marketplace search |
| `warn` | `component.global_empty_agent_meta` | global component has empty `agent_meta`, so it can't be discovered or have its rules retrieved |
| `warn` | `block.legacy_data_layout` / `block.legacy_data_binding` | older block shape with `data.layout` / `data.data_binding` instead of top-level fields |
| `info` | `site.no_analytics` | no analytics configured (no GA, no Plausible, no custom head scripts) |
| `info` | `page.orphan_tree_node` | page has `parent_id` but no siblings — tree nesting is doing nothing |

### Audit summary shape

```json
{
  "summary": { "errors": 7, "warnings": 24, "info": 2 },
  "site_level": [...],
  "page_level": [...],
  "block_level": [...],
  "component_level": [...]
}
```

### Fix-at-source workflow

The auditor surfaces the problem and a `suggested_fix`; the agent decides how to apply it. Common follow-ups:

| Finding | Follow-up |
|---|---|
| `block.scroll_sequence_empty_frames` | `content_update_page(page_id, blocks=<edited>)` — set `props.frames` (array of URLs) OR `props.count` + `props.base_url` + `props.pattern` on the offending block |
| `page.empty_seo_title` / `_description` | `content_update_page(page_id, seo_title=…, seo_description=…)` — 50–60 chars title, 140–160 chars description |
| `site.missing_favicon` / `_default_og_image` | `content_update_settings(favicon_url=…, default_og_image_url=…)` — public 32×32 PNG / 1200×630 PNG |
| `site.no_verified_primary_domain` | `content_add_domain(domain=…)` then DNS verification + `content_set_primary_domain(domain=…)` |
| `component.kind_null_with_dependencies` | `content_update_component(component_id, kind=…)` — one of `static` / `interactive` / `dynamic` / `extension` |
| `component.global_empty_agent_meta` | `content_update_component(component_id, agent_meta={tags:[…], kind:…})` |
| `block.legacy_data_layout` / `block.legacy_data_binding` | `content_update_page(page_id, blocks=<edited>)` — move `data.layout` to top-level `layout`; same for `data_binding` |

### Format decision tree

| Format | When | Returns |
|---|---|---|
| `json` (default) | Agent inspecting / parsing programmatically — pull `audit.summary` + walk findings + take action | flat JSON envelope |
| `md` | Human review (paste into chat / a doc) | text/markdown — every component fenced, audit findings as a checklist |
| `archive` | Round-trip via the SpiderPublish VSCode extension | ZIP byte stream matching the extension's local registry layout |

### Idempotency + cost

The endpoint is read-only — call it as often as needed. The audit runs every time (no cache yet); plan for ~50–500 ms per page depending on component count. Component bodies for global components are deduplicated within the response (one entry per unique `(slug, version)` pair).

### Anti-patterns

- **Don't** call `content_get_page` then loop calling `content_get_component` once per block — that's the slow path and produces no audit. Use `content_export_page` instead.
- **Don't** ignore `info`-severity findings on first pass. They're often signals of intentional choices, but a sweep across the site will surface what's actually unintentional.
- **Don't** assume `audit.errors == 0` means "ready to deploy" — some failures (e.g. broken external links) live in different rule families and ship in P5.


---

## Audit Driven Edit

Edit a page section with **rules-on-the-way-in** (`_rules` envelope on dry_run) and **audit-on-the-way-out** (`_audit` envelope on the success response). Replaces "insert blindly and hope it renders" with a single-roundtrip authoring loop where the agent learns the canonical tool path BEFORE inserting, and sees broken state IMMEDIATELY on the response — not three roundtrips later when the dashboard preview loads.

### When to use

- You're inserting any component for the first time and want to know its canonical authoring path (component author wrote `preferred_path` into `authoring_hints`).
- You're inserting a complex component (scroll-sequence, multistep form, dynamic block) and want the server to flag missing required props before the page goes live.
- You're auditing an existing page for issues — call `GET /pages/{id}?audit_level=warnings` and read the `_page_audit` block.
- You authored a global component and want to write the rules other agents will see when they insert it (the `authoring_hints` write surface).

### The one-shot calls

```bash
# Read a page WITH audit decoration
GET /api/v1/dashboard/projects/{pid}/content/pages/{page_id}?audit_level=warnings
# → page response + _page_audit: {site_level, page_level, block_level, component_level, summary}

# Insert section — dry_run first, get _rules
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/insert-section?dry_run=true
Body: { "component_slug": "sys-scroll-sequence", "props": {} }
# → {
#     "preview": {...},
#     "confirm_token": "cft_xxx",
#     "expires_at": "...",
#     "_rules": {
#       "component_slug": "sys-scroll-sequence",
#       "kind": "interactive",
#       "intrinsic":     [...],          // derived from kind/dependencies/props_schema
#       "authored":      {               // raw passthrough from authoring_hints JSONB
#         "preferred_path": "Use the video_to_scroll_sequence MCP tool — it extracts frames from a video file and creates this block in one call.",
#         "must_set":       ["frames"]
#       },
#       "cross_cutting": [...]           // PageAuditor.audit_page() findings BEFORE the mutation
#     }
#   }

# Confirm — get _audit on the response
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/insert-section?confirm_token=cft_xxx&audit_level=all
Body: { "component_slug": "sys-scroll-sequence", "props": {"frames": ["a.jpg","b.jpg",...]} }
# → {
#     "success": true,
#     "page_id": "...",
#     "new_block_id": "...",
#     "_audit": {
#       "site_level":      [],
#       "page_level":      [],
#       "block_level":     [],          // empty when frames are populated; would carry insertion.scroll_sequence_empty_frames if not
#       "component_level": [],
#       "summary": { "errors": 0, "warnings": 0, "info": 1 }
#     }
#   }
```

**MCP tools** — ship in `@spideriq/mcp-publish@1.12.0+` and kitchen-sink `@spideriq/mcp@1.12.0+`:

- `content_get_page({page_id, audit_level?})` — `audit_level` ∈ `off | errors | warnings | all`, default `warnings`
- `page_insert_section({page_id, component_slug, ..., audit_level?, dry_run?, confirm_token?})` — `audit_level` default `all` for mutations
- `content_create_component({...., authoring_hints?})` — write surface for component authors
- `content_update_component({...., authoring_hints?})` — replace stored hints (pass `{}` to clear)

### The `_rules` envelope (dry_run)

Three independent rule sources composed:

| Source | Where | When present |
|---|---|---|
| **A — intrinsic** | derived from the component's `kind` / `dependencies` / `props_schema` at request time | always |
| **B — authored** | raw passthrough from `content_components.authoring_hints` JSONB (the `preferred_path`, `common_mistakes`, `must_set`, `must_not_set` fields) | when the component author populated the column |
| **C — cross_cutting** | caller-supplied `PageAuditor.audit_page` findings on the target page BEFORE the mutation lands | only on dry_run of `insert_section` |

**Intrinsic rule examples** (the auditor adds these without any author write):

- `intrinsic.scroll_sequence_frames_required` — `kind=interactive` with GSAP/ScrollTrigger dep + `frames` in props_schema → `error`
- `intrinsic.dynamic_requires_data_binding` — `kind=dynamic` → top-level `data_binding` is required → `error`
- `intrinsic.interactive_root_props_contract` — `kind=interactive` → JS body runs as `(root, props) => ...` where `root` is the SHADOW root → `info`
- `intrinsic.props_schema_required` — `props_schema.required[]` is non-empty → `warn` listing the keys

### The `_audit` envelope (mutation success)

Same shape as `PageAuditResult` from `content_export_page` — bucketed by scope:

```json
{
  "site_level":      [],
  "page_level":      [],
  "block_level":     [{ "rule_id": "insertion.scroll_sequence_empty_frames", "severity": "error", "scope": "block", "target": "<block_id>", "message": "...", "suggested_fix": "..." }],
  "component_level": [],
  "summary": { "errors": 1, "warnings": 0, "info": 0 }
}
```

**Mutation rules** (P5 — see [PageAuditor.audit_block_insertion](https://docs.spideriq.ai/api-reference/content/insert-section)):

| Severity | Rule | Catches |
|---|---|---|
| error | `insertion.scroll_sequence_empty_frames` | scroll-sequence inserted with 0 frames bound — section renders blank |
| error | `insertion.unknown_component` | `component_slug` doesn't resolve for this client (not in library, not global) |
| warn | `insertion.missing_required_prop` | `authoring_hints.must_set` lists a prop that's empty/absent |
| warn | `insertion.forbidden_prop` | `authoring_hints.must_not_set` lists a prop that's present |
| info | `insertion.preferred_path_hint` | surfaces `authoring_hints.preferred_path` so you learn the canonical tool |

### The `audit_level` toggle

| Value | Reads (`GET /pages/{id}`) | Mutations (`/insert-section`) |
|---|---|---|
| `off` | omits `_page_audit` entirely (cheapest — skips the auditor walk) | omits `_audit` |
| `errors` | only error-severity findings | only errors |
| `warnings` (default for reads) | errors + warnings | errors + warnings |
| `all` (default for mutations) | every finding incl. info | every finding incl. info |

Default behaviour is agent-friendly. Use `audit_level=off` only inside tight-loop scripts that bulk-insert and audit later via `content_export_page`.

### Component-author write surface — `authoring_hints`

When you author a global component, populate `authoring_hints` so downstream agents inserting it get tailored guidance:

```js
content_create_component({
  slug: "my-component",
  name: "...",
  html_template: "...",
  // ... other args ...
  authoring_hints: {
    preferred_path: "Use my_helper_tool, not manual insert.",      // info-level nudge surfaced on dry_run
    common_mistakes: ["Forgetting props.thank_you_url"],            // visible to all inserting agents
    must_set:        ["headline", "submit_endpoint"],               // missing → warn `insertion.missing_required_prop`
    must_not_set:    ["_internalKey"]                               // present → warn `insertion.forbidden_prop`
  }
})
```

Empty `{}` (the column default) = no hints; the component degrades cleanly to intrinsic-only rules.

### End-to-end recipe

```bash
PROJECT_ID="<your-project-id>"
PAGE_ID="<page-uuid>"
PAT="<your-pat>"

# 1. Read the page first to see current state + page-level audit
curl -H "Authorization: Bearer $PAT" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PROJECT_ID/content/pages/$PAGE_ID?audit_level=warnings" \
  | jq '{slug, blocks_count: (.blocks | length), audit: ._page_audit.summary}'

# 2. dry_run insert — read _rules to learn the canonical path
curl -X POST -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PROJECT_ID/content/pages/$PAGE_ID/insert-section?dry_run=true" \
  -d '{"component_slug": "sys-scroll-sequence", "props": {}}' \
  | tee /tmp/dry_run.json
PREFERRED=$(jq -r '._rules.authored.preferred_path' /tmp/dry_run.json)
echo "Author guidance: $PREFERRED"
TOKEN=$(jq -r '.confirm_token' /tmp/dry_run.json)

# 3. If preferred_path nudges you elsewhere (e.g. video_to_scroll_sequence), STOP and use that tool instead.
#    Otherwise, add the required props and confirm:
curl -X POST -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PROJECT_ID/content/pages/$PAGE_ID/insert-section?confirm_token=$TOKEN&audit_level=all" \
  -d '{"component_slug": "sys-scroll-sequence", "props": {"frames": ["..."]}}' \
  | jq '._audit'
```

### Anti-patterns

- **Don't** ignore `_rules.authored.preferred_path`. The component author wrote it because the manual-insert path is error-prone for that component. Read it BEFORE confirming the dry_run.
- **Don't** skip the dry_run because "you know the shape". Static knowledge of the props_schema doesn't catch dynamic constraints (the page already has 4 scroll-sequences, the site is missing a primary domain, etc.) — those only surface in `_rules.cross_cutting`.
- **Don't** retry on `_audit.errors > 0` without addressing the finding. Each error has a `suggested_fix` field — apply it before the next attempt.
- **Don't** set `audit_level=off` on every call to "save tokens". The audit walk is single-digit milliseconds; the savings come from skipping it inside genuinely tight loops, not on regular agent traffic.
- **Don't** write `authoring_hints` on a tenant-scoped component you didn't author. The hints column is for component authors signalling to downstream inserting agents.

### Backwards compatibility

The envelope fields are **purely additive** — agents that ignore `_rules` / `_audit` / `_page_audit` aren't broken. Components that have empty `authoring_hints` (the column default `{}`) degrade cleanly to intrinsic-only rules. No existing recipe needs to change to keep working.

### See also

- `recipes/scroll-sequence/SKILL.md` — the deeper how-to for the scroll-sequence-specific traps the audit catches
- `recipes/lock-during-review/SKILL.md` — the P4 lock that pairs with this recipe (lock the page, audit, unlock)
- `recipes/audit-and-fix/SKILL.md` — sibling recipe that walks an EXISTING page through the auditor and fixes findings inline (P2)


---

## Deploy Readiness

Pre-flight checklist BEFORE running a production deploy — confirms settings/domain/templates/pages are configured + no blocking issues. Cheap probe; saves a failed deploy + a spent confirm_token.

### When to use

- BEFORE every `content_deploy_site_production` on a tenant you're not 100% sure is configured.
- After applying a site template + customizing — confirm the customizations didn't break readiness.
- After a major refactor (new domain, theme swap, settings change) — confirm everything still passes.
- As a daily / weekly health check via CI for production tenants.

For POST-deploy verification → [`visual-check-a-page.md`](audit.md#visual-check-a-page). For an internal-link audit (404s in nav, dead links) → [`link-audit.md`](audit.md#link-audit).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You're about to deploy** (otherwise this is just a status check — fine, but the recipe is sequenced for deploy use).

### The 1-call path

```
content_deploy_readiness()
// → {
//   ready: true,
//   checks: [
//     { item: "site_name",                   status: "pass" },
//     { item: "primary_domain",              status: "pass",  value: "acme.com" },
//     { item: "domain_verified",             status: "pass" },
//     { item: "home_page_published",         status: "pass",  value: "home" },
//     { item: "navigation_header",           status: "pass",  items_count: 5 },
//     { item: "templates_complete",          status: "pass" },
//     { item: "no_unresolved_block_warnings", status: "warn", warnings_count: 2 }
//   ],
//   blocking: [],
//   warnings: [
//     { item: "blog_post_count",  message: "0 published posts; /blog will be empty" },
//     { item: "no_unresolved_block_warnings", message: "2 pages have render.unused_field_in_default_theme warnings" }
//   ]
// }
```

The shape: `ready` is `true` if `blocking` is empty; deploy will refuse otherwise.

### The checklist (what gets verified)

These are the items the readiness probe walks. Exact list may drift as the catalog evolves; treat as canonical-ish.

#### Settings + identity

| Item | Pass when | Fail when |
|---|---|---|
| `site_name` | `content_settings.site_name` is non-empty | Empty / null (defaults render as `<title>untitled</title>`) |
| `default_meta_title` | Set OR every page has its own `seo_title` | Neither (SEO is degraded) |
| `favicon_url` | Set | Not set (browsers show generic favicon) |
| `logo_url` | Set OR theme doesn't reference it | Theme uses `{{ settings.logo_url }}` but it's null |

#### Domain

| Item | Pass when | Fail when |
|---|---|---|
| `primary_domain` | At least one verified domain set as primary | No primary set (URLs fall back to `<tenant>.sites.spideriq.ai`) |
| `domain_verified` | Primary domain has `verified_at` non-null | Primary is added but not verified — visitors see CF errors |

#### Content

| Item | Pass when | Fail when |
|---|---|---|
| `home_page_published` | A page with `slug: "home"` exists + is published | Visitors hit `/` and see 404 |
| `at_least_one_published_page` | ≥1 published page | Empty tenant — nothing to render |
| `no_orphan_published_pages` | Every published page is reachable via nav OR is the home | Pages exist but no nav link → invisible to visitors |
| `nav_targets_exist` | Every nav item's `url` resolves to a real page / route | Dead links in nav |

#### Templates

| Item | Pass when | Fail when |
|---|---|---|
| `templates_complete` | Theme has the minimum templates (`layout/theme.liquid`, `templates/page.liquid`, etc.) | Custom theme is missing a required template |
| `no_invalid_overrides` | All `content_templates` entries parse as valid Liquid | A `template_upsert` left a syntax error |

#### Page-level audit aggregation

| Item | Pass when | Warn when |
|---|---|---|
| `no_unresolved_block_warnings` | No published page has open `render.unused_field_in_default_theme` warnings | One or more pages have silent-blank-section warnings |
| `no_locked_pages` | No published page is `is_locked: true` | A locked page (mid-review) is about to deploy |

#### Booking / forms

| Item | Pass when | Warn when |
|---|---|---|
| `no_orphan_form_embeds` | Every form embed in any page's blocks references an `active` form | A page embeds a `draft` form → renders unavailable |

The set may grow over time — read the `checks: []` array to see what fired.

### The flow — readiness → deploy → visual-check

```
# 1. Readiness — must show ready: true (or you fix blocking items)
content_deploy_readiness()
# → { ready: true, blocking: [], warnings: [...] }

# 2. Review warnings (NOT blocking, but worth knowing)
# - "0 published posts; /blog will be empty" → maybe defer launching /blog
# - "2 pages have render.unused_field_in_default_theme warnings" → consider fixing first

# 3. Deploy preview
content_deploy_site_preview()
# → { preview_url: "https://preview-XXX.sites.spideriq.ai", confirm_token, ... }
# Eyeball the preview URL.

# 4. Confirm production
content_deploy_site_production({ confirm_token })
# → { status: "live", version_id: 50 }

# 5. Visual-check (Rule 62)
content_visual_check({ page_url: "https://<primary>/", viewport: "desktop" })
```

The full sequence on a confident deploy: readiness → preview → production → visual-check. ~10s total wall-clock; saves a wrong-deploy + agent confusion.

### When readiness says `ready: false`

`blocking: [...]` carries the items that MUST be fixed. Common shapes + fixes:

| Blocking | Fix |
|---|---|
| `primary_domain: not_set` | `content_add_domain` → `content_verify_domain` → `content_set_primary_domain`. See [`../content/custom-domain.md`](integrations.md#custom-domain). |
| `domain_verified: false` | `content_verify_domain` (and confirm `success: true`). Customer DNS may not have propagated yet. |
| `home_page_published: missing` | `content_create_page({ slug: "home", title: "..." })` → `content_publish_page`. |
| `site_name: empty` | `content_update_settings({ settings: { site_name: "..." } })`. See [`../content/update-site-settings.md`](content.md#update-site-settings). |
| `nav_targets_exist: dead_link` | Fix the nav item URL via `content_update_navigation`. See [`../content/navigation.md`](content.md#navigation). |
| `no_orphan_form_embeds: <flow_id> not active` | `form_publish` the orphan flow. |

Don't proceed to deploy with blocking items — `content_deploy_site_*` will refuse with the same shape envelope.

### When readiness says `ready: true` but `warnings: [...]`

Warnings DON'T block the deploy — agent's choice whether to address them first. Common cases:

- **`/blog will be empty`**: the dynamic-list page exists but no published posts. Deploy is fine; `/blog` renders "No posts yet" until you publish one.
- **`render.unused_field_in_default_theme` on N pages**: silent-blank-section risk; pages publish, but some sections are blank. Run `content_get_page({ audit_level: "warnings" })` per page to fix.
- **Orphan published pages (in store but not in nav)**: visitors can't navigate to them. Fine for landing pages designed for paid traffic; fix if expected to be discoverable.

Decide case-by-case. The default agent posture: fix warnings BEFORE deploy on production tenants; ignore on dev / staging.

### Run as a daily / weekly health check

```bash
# Cron / CI / scheduled job — fail loudly if readiness drifts
RES=$(curl -s -H "Authorization: Bearer $CLI_ID:$KEY:$SECRET" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PID/content/deploy-readiness")

READY=$(echo "$RES" | jq -r '.ready')
if [ "$READY" != "true" ]; then
  BLOCKING=$(echo "$RES" | jq -c '.blocking')
  echo "Tenant $PID deploy-readiness FAIL: $BLOCKING"
  exit 1
fi
```

Add as a cron on the SpiderIQ ops side for production tenants. Surfaces "settings drifted" / "domain de-verified" / "nav has dead links" before the next deploy attempt.

### Anti-patterns

1. **Skipping readiness, jumping straight to `content_deploy_site_*`.** Deploy refuses with the same blocking envelope. Save a round-trip.
2. **Treating warnings as blocking.** They're advisory. Fix when worth it; ignore otherwise. Production tenants: usually fix. Dev tenants: skip.
3. **Re-running readiness without fixing the blocking items.** It'll return the same shape. Fix → re-check.
4. **Running readiness on a non-existent tenant.** Returns 404 / mismatch error (Lock 1/3 fires). Verify scope first.
5. **Assuming readiness covers visual fidelity.** It checks SETTINGS / DOMAIN / CONTENT — not "the hero looks right." For that, [`visual-check-a-page.md`](audit.md#visual-check-a-page) post-deploy.

### See also

- [`visual-check-a-page.md`](audit.md#visual-check-a-page) — POST-deploy verification (this recipe is PRE-deploy)
- [`link-audit.md`](audit.md#link-audit) — internal link audit (different surface; readiness covers nav broadly)
- [`audit-and-fix.md`](audit.md#audit-and-fix) — end-to-end audit + fix
- [`audit-driven-edit.md`](audit.md#audit-driven-edit) — iterative authoring with audit feedback
- [`../content/custom-domain.md`](integrations.md#custom-domain) — fix `primary_domain` / `domain_verified` blocking
- [`../content/update-site-settings.md`](content.md#update-site-settings) — fix settings blocking
- [`../content/navigation.md`](content.md#navigation) — fix nav blocking
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the two-phase deploy that readiness gates


---

## Link Audit

Find every broken internal link across a site in one HTTP call — before a deploy ships them.

### When to use

- You just reorganized navigation or renamed pages, and want to know what broke.
- You're cleaning up legacy URL patterns (e.g. `/en/*` → `/*` after dropping a locale).
- You're about to `content_deploy_site_production` and want a final check.

### The one-shot call

```bash
GET /api/v1/dashboard/projects/{pid}/content/audit/links
# → { valid_count, broken: [{path, source, reason}], proposed_redirects, known_redirects }
```

**MCP tool:** `content_audit_links()` — ships in `@spideriq/mcp-publish@1.6.0+` and kitchen-sink `@spideriq/mcp@1.6.0+`. No required input args.

**CLI:** `spideriq content audit-links [--json]` — ships in `@spideriq/cli@1.6.0+`. Pretty-prints broken links with their JSONPath-shaped `source` strings + proposed redirects. Exits non-zero when broken links are present so CI / pre-push hooks gate cleanly. `--json` emits the raw envelope.

**Runnable example:** examples/audit-links.sh — covers both the CLI path (preferred) and the raw HTTP path (fallback for shells without Node).

### What gets scanned

| Source | What's inspected |
|---|---|
| Every published `content_pages` row | Every `url`, `href`, `link`, `to`, `target_url`, `destination` string anywhere in the `blocks` JSON tree |
| Every `content_navigation` row (header, footer, docs_sidebar) | Every `url` string in the nested items JSON |

### How validation works

A link is **internal** if it starts with `/` (and isn't `//` — that's protocol-relative). External `https://...`, `mailto:`, `tel:`, fragments (`#section`) are skipped.

For each internal link:

1. Normalize (strip query string, fragment, trailing slash, lowercase).
2. Compare against the set of valid targets:
   - Published page slugs — `home` → `/`, others → `/{slug}`
   - Published post slugs — `/blog/{slug}`
   - Active `content_redirects` from_path entries
3. No match → add to `broken[]` with a `source` string naming the exact tree position.

### Response shape

```json
{
  "valid_count": 42,
  "broken": [
    {
      "path": "/en/about",
      "source": "navigation:header[1].url",
      "reason": "target_not_found"
    },
    {
      "path": "/old-pricing",
      "source": "page:home/block[2].cta_primary.url",
      "reason": "target_not_found"
    }
  ],
  "proposed_redirects": [
    {"from": "/en/about", "to": "/about", "status_code": 301}
  ],
  "known_redirects": [
    {"from": "/legacy", "to": "/new", "status_code": 301}
  ]
}
```

### Follow-up actions

The response tells you where to go next:

1. **Fix at the source** — `source: "page:home/block[2].cta_primary.url"` means `blocks[2].data.cta_primary.url` on the page with slug `home`. Use `content_update_page` to edit that block.
2. **Or create a redirect** — `proposed_redirects` suggests 301s when a broken path's suffix matches an existing slug. Review each one, then `content_create_redirect` for the ones you want.

### Why this matters

Before this tool, cleaning up legacy URL patterns across a 30-page site meant reading every page + every menu manually. Two real reports inspired this:

- **Unavis migration** — drop a multi-language structure (`/en/*` → flat). Without link-audit, clients miss at least one of the ~20 nav entries or CTA buttons.
- **Onyx Radiance migration** — rebuild 16 pages with flat slugs after hitting the nested-slug 404 bug. Several `/product/xxx` → `/product-xxx` references lived in page CTAs and were only discovered by 404 spikes post-deploy.

### Defaults + limits

- No caching — each call does a live SQL walk. Typical run: 50–200ms for a 50-page site.
- Protected by the standard content-scoped auth (session cookie OR PAT).
- Dual-mounted under both the legacy and Phase 11+12 URL forms:
  - `/api/v1/dashboard/content/audit/links` (legacy)
  - `/api/v1/dashboard/projects/{pid}/content/audit/links` (scoped)

### See also

- [recipes/preview-iteration](content.md#preview-iteration) — general edit/preview/deploy cycle
- [recipes/component-update-and-propagate](components.md#update-and-propagate) — the one-shot for changing components across many pages
- [LEARNINGS.md → Apr 2026 Triage](../SKILL.md) — the silent-failure modes this closes


---

## Visual Check A Page

Run a Playwright-sidecar visual check on a deployed page — screenshot, DOM probe, console-error capture. The regression net codified by the W13 incident. Rule 62 lives here.

### When to use

- After every production deploy, to confirm the page actually renders (the silent-200 failure class).
- Verifying a `kind='form'` flow embed renders the form (shadow-DOM host present).
- Smoke-testing a CRO component after insert.
- Verifying a custom-domain swap actually serves your tenant content (not Cloudflare's 404).
- Empirically confirming an agent's edit before declaring "done."

For LINK auditing (404s in nav, dead internal links) → [`link-audit.md`](audit.md#link-audit). For a full pre-deploy checklist → [`deploy-readiness.md`](audit.md#deploy-readiness). For ongoing audits → [`audit-driven-edit.md`](audit.md#audit-driven-edit).

### Prerequisites

1. **Page is publicly reachable.** Visual-check sidecar runs against the public URL — auth-walled pages won't load.
2. **Visual-check sidecar healthy.** It runs as a separate container (`spideriq-visual-check`) on port 8080. If unreachable → 503 / no-screenshot envelope.

### The 1-call path

```
content_visual_check({
  page_url: "https://<tenant>/<page-slug>",      # NOT `url` — `page_url` is the param name
  viewport: "desktop"                            # OR "mobile" — enum, NOT `{width, height}` object
})
// → {
//   success: true,
//   screenshot_url: "https://media.spideriq.ai/visual-check/<sha>/screenshot.png",
//   dom: {
//     shadow_hosts: [ "spideriq-form", "spideriq-cmp" ],
//     elements_seen: 142,
//     scripts_loaded: 8
//   },
//   body_text_preview: "<!doctype html>... [host page chrome] ...",
//   console_errors: [],
//   request_log: [
//     { url: "...", status: 200, type: "script" },
//     ...
//   ],
//   timings: { dom_content_loaded_ms: 423, load_ms: 1234 }
// }
```

The sidecar:
1. Spins up a headless Chromium via Playwright.
2. Sets the viewport (desktop = 1280×800; mobile = 390×844).
3. Navigates to `page_url`.
4. Waits for `load` event + a settle delay.
5. Captures screenshot to R2.
6. Walks the DOM for shadow-host custom elements (`<spideriq-form>`, `<spideriq-cmp>`, …).
7. Captures `console.error` calls.
8. Captures the request log (which scripts/images/etc. loaded; their statuses).
9. Returns the envelope.

### Param shape — exact (codified by Rule 59 / B.2 incident)

Get these wrong and the sidecar 400s through MCP as a 500 INTERNAL_ERROR — the false-FAIL trap:

| ✅ Use | ❌ Don't (will 422/500) |
|---|---|
| `page_url: "https://..."` | `url: "https://..."` |
| `viewport: "desktop"` or `viewport: "mobile"` (enum) | `viewport: { width: 1280, height: 800 }` (object — pre-Rule-59 shape) |

`tenant_id` (optional) for verified-custom-domain allowlist resolution — pass when the page lives on a custom domain that may need explicit allowlist match.

### The assertion rule (Rule 62 — verbatim)

> **When verifying a form is rendering correctly, ALWAYS assert on `dom.shadow_hosts.includes("spideriq-form")`. DO NOT assert on `body_text_preview` for cross-origin iframe contents — the iframe body is opaque to the parent page's DOM, so field labels and button text are NOT in `body_text_preview` even when the form is rendering correctly. Same applies to any custom-element shadow-host: assert on its tag name in `dom.shadow_hosts`, not on body text.**

(Codified in [`learnings_visual_check_assert_on_shadow_hosts.md`](../SKILL.md) — the source incident.)

Applies to ANY Shadow-DOM-hosted custom element:
- Forms → `dom.shadow_hosts.includes("spideriq-form")`
- Components (Tier 2+) → `dom.shadow_hosts.includes("spideriq-cmp")`
- Future custom elements → assert on the host tag name

### Common verifications

#### A standard content page

```
content_visual_check({
  page_url: "https://acme.com/about",
  viewport: "desktop"
})
# Assert:
# - success: true
# - screenshot_url not null
# - body_text_preview contains "About Acme" (the hero headline literal)
# - console_errors: []
# - timings.load_ms < 3000 (reasonable load time)
```

#### A page with an embedded form (`kind='form'` Path B)

```
content_visual_check({
  page_url: "https://acme.com/contact",
  viewport: "desktop"
})
# Assert:
# - success: true
# - dom.shadow_hosts.includes("spideriq-form")   # the form mounted
# - DO NOT assert: body_text_preview contains "First name"  ← Shadow DOM opaque
# - console_errors: [] (no loader script errors)
```

#### A standalone `/f/<flow_id>` URL

```
content_visual_check({
  page_url: "https://spideriq.ai/f/<flow_id>",
  viewport: "desktop"
})
# Assert:
# - success: true
# - dom.shadow_hosts.includes("spideriq-form")
# - body_text_preview probably empty or minimal (form is the page)
```

#### A mobile-shaped verification

```
content_visual_check({
  page_url: "https://acme.com/",
  viewport: "mobile"
})
# Mobile viewport: 390x844 (iPhone 14 Pro)
# Useful for forms with theme.preset 'fullscreen-dark' (mobile collapses left/right media splits)
# Useful for CRO components: sys-bar-sticky-cta-mobile only renders below 768px
```

#### A page with Tier 3 components (CDN deps)

```
content_visual_check({
  page_url: "https://acme.com/landing",
  viewport: "desktop"
})
# Assert:
# - dom.shadow_hosts.includes("spideriq-cmp")   # at least one Tier 2+ component mounted
# - console_errors: []  (no "gsap is not defined" — Tier 3 dep loading failures)
# - request_log shows scripts for declared dependencies loaded with status 200
```

If `request_log` shows a script with status 404 (e.g. `chart.js@4.4.6/...` 404), your component's `dependencies[]` key resolves to a stale CDN URL — fix in `content_cdn_allowlist`.

### Verifying after a deploy (the canonical check-after-publish pattern)

```
# Right after content_deploy_site_production confirms:
content_deploy_status()
# → { status: "live", version_id: 49, ... }

content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
# Confirm the new content is actually visible — silent-200 failure class.
```

The deploy returning 200 means "the request was accepted." It does NOT mean "every visitor sees the new bytes." Edge cache propagation, KV consistency lag, and Workers-for-Platforms cold starts can all create a window where the deploy completed but a fraction of visitors still see the old version. Visual-check confirms the FIRST-visitor experience.

### What the sidecar can't do

- **Click through forms.** Visual-check renders the page; it doesn't fill or submit. For interactive flows, you need an actual browser session ([`agent-browser`](CLAUDE.md#browser-automation-agent-browser) or Playwright directly).
- **Auth-walled pages.** No cookie injection (yet). Public URLs only.
- **JavaScript-driven popups that fire on `mouseleave`.** The screenshot won't capture the popup (no cursor movement). Verify CRO popups manually in a browser.
- **Per-tenant analytics events.** The sidecar's console may show GTM/GA initialisation, but `gtag('event', ...)` calls don't get verified — those need a real visitor session.
- **Real-device fidelity.** Headless Chromium ≠ Safari, real iPhone, real Android. For pixel-perfect mobile or Safari-specific quirks, manual device testing.

### Cost / token budget

Visual-check costs:
- ~1-5s per call (sidecar startup + page load + screenshot).
- Screenshot upload to R2 (~50-300 KB per shot).
- Free at the SpiderPublish API surface; no per-call billing.

Tight-loop usage (e.g. visual-check after every component insert in a long authoring session): cheap; no rate limit currently enforced. Production-deploy verification: always run.

### Anti-patterns

1. **`url:` instead of `page_url:`.** The B.2 incident root cause (Rule 59) — Antigravity Verifier B was given the wrong param name in a spawn prompt; sidecar 400'd, MCP surfaced as 500 INTERNAL_ERROR. Always `page_url`.
2. **`viewport: { width: 1280, height: 800 }`.** Old shape. Now `viewport: "desktop"` / `"mobile"` enum.
3. **Asserting `body_text_preview` includes form field labels.** Cross-origin iframe / Shadow DOM = opaque. Use `dom.shadow_hosts`. Rule 62.
4. **Skipping visual-check after deploy because "the tests passed."** Tests verify code correctness; visual-check verifies feature correctness. Different layer.
5. **Visual-checking a page with auth.** The sidecar gets a login wall, not your page. Public URLs only OR add auth-bypass infrastructure (not yet shipped).
6. **Treating `success: true` as "the page is correct."** `success: true` means "Playwright loaded the page." You still need to assert on `dom.shadow_hosts` / `body_text_preview` / `console_errors` for the actual content checks.

### See also

- [`deploy-readiness.md`](audit.md#deploy-readiness) — pre-deploy checklist (run BEFORE deploy; visual-check runs AFTER)
- [`link-audit.md`](audit.md#link-audit) — audit internal links (different surface; complementary)
- [`audit-and-fix.md`](audit.md#audit-and-fix) — end-to-end audit + fix flow
- [`audit-driven-edit.md`](audit.md#audit-driven-edit) — iterative authoring with audit feedback
- [`../booking/embed-form.md`](forms-booking.md#embed-form) — where Rule 62 most often applies
- [`../booking/form-as-page-section.md`](forms-booking.md#form-as-page-section) — same rule for in-page form embeds
- [`../reference/booking-model.md`](booking-model.md) — Rule 62 verbatim + W13 case study
- catalog/LEARNINGS.md Rules 59 + 62 — source incidents (param-shape drift + shadow-host assertion)
