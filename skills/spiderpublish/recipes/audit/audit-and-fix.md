# recipes/audit-and-fix

Export a page with its audit, parse the findings, fix the most-confident ones, push back. Closes the loop where an AI agent edits a page without ever seeing what's already on it.

## When to use

- You're about to edit a page and only have its slug — no inlined component bodies, no idea what's currently shipping.
- A client reports "the website looks broken" and you want a structured diagnostic before opening the editor.
- You're about to `content_deploy_site_production` and want a per-page health check across the whole site.
- You want to round-trip a page through your IDE — export as archive, edit on disk with native diffs, push back.

## The one-shot call

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

**Runnable example:** [examples/content-export-and-audit.sh](../../../examples/content-export-and-audit.sh) — covers all three formats end-to-end.

## What gets audited

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

## Audit summary shape

```json
{
  "summary": { "errors": 7, "warnings": 24, "info": 2 },
  "site_level": [...],
  "page_level": [...],
  "block_level": [...],
  "component_level": [...]
}
```

## Fix-at-source workflow

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

## Format decision tree

| Format | When | Returns |
|---|---|---|
| `json` (default) | Agent inspecting / parsing programmatically — pull `audit.summary` + walk findings + take action | flat JSON envelope |
| `md` | Human review (paste into chat / a doc) | text/markdown — every component fenced, audit findings as a checklist |
| `archive` | Round-trip via the SpiderPublish VSCode extension | ZIP byte stream matching the extension's local registry layout |

## Idempotency + cost

The endpoint is read-only — call it as often as needed. The audit runs every time (no cache yet); plan for ~50–500 ms per page depending on component count. Component bodies for global components are deduplicated within the response (one entry per unique `(slug, version)` pair).

## Anti-patterns

- **Don't** call `content_get_page` then loop calling `content_get_component` once per block — that's the slow path and produces no audit. Use `content_export_page` instead.
- **Don't** ignore `info`-severity findings on first pass. They're often signals of intentional choices, but a sweep across the site will surface what's actually unintentional.
- **Don't** assume `audit.errors == 0` means "ready to deploy" — some failures (e.g. broken external links) live in different rule families and ship in P5.
