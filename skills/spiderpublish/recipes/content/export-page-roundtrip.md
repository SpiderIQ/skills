# recipes/content/export-page-roundtrip

Pull the **full page envelope** — page row + every referenced component inlined + settings + domains + audit walk — in one call. Use this when you need the whole picture before editing, or for a VSCode-extension round-trip (export → edit locally → push back).

## When to use

- You need to understand what a `vp-hero` block actually is (its `html_template`, `css`, `js`, `props_schema`) before editing the page that uses it.
- A page references a Tier 3 component (GSAP / ScrollTrigger / Three.js) and you want to know about latent dependencies before redeploying.
- Surfacing broken sections before pushing — the PageAuditor walk catches scroll-sequence empty frames, missing primary domain, SEO holes, etc.
- Round-tripping a page through the **VSCode extension** for offline editing: export → `spideriq pull` into local registry → edit JSON/Markdown → `spideriq push` back.
- Backing up a page for archival before a high-risk template-apply or theme swap.

## Prerequisites

- A PAT scoped to the tenant (see [`../../_shared/auth.md`](../../_shared/auth.md)).
- The page's `page_id` (UUID).

## The one call

```
content_export_page({
  page_id: "<uuid>",
  format: "json"   # default; alternatives: "md" | "archive"
})
```

That single MCP call returns a **flat envelope** containing:

1. **`page`** — the full row (title, slug, status, `blocks[]`, seo_*, template, version_number).
2. **`components`** — for every component referenced by `page.blocks`, the FULL component body inlined: `html_template`, `js`, `css`, `props_schema`, `dependencies`, `agent_meta`, `kind`, `layouts`.
3. **`settings`** — the tenant's `content_settings` row (default_meta_title, default_meta_description, brand_colors, font_family, etc.).
4. **`domains`** — the tenant's `content_domains` rows (primary + aliases, verified status, CF zone IDs).
5. **`audit`** — a PageAuditor walk with **10 v1 rules**:
   - scroll-sequence empty frames
   - missing primary domain
   - page SEO holes (no `seo_title`, no `seo_description`)
   - latent Tier 3 components (CDN deps not in `dependencies`)
   - duplicate `block.id` values
   - orphan `anchor_block_id` references
   - … (full list in the response under `audit.rules`)
6. **`manifest`** — `{exported_at, exporter_version, snapshot_hash}` so a downstream `spideriq push` can detect divergence.

## The three output formats

| Format | Use when | Returns |
|---|---|---|
| **`json`** (default) | Programmatic consumption — feeding the envelope into another tool, building a backup pipeline | Flat JSON object |
| **`md`** | Human review, code review on a PR, sharing context with a teammate via chat | Single Markdown document with sections per slice |
| **`archive`** | VSCode-extension round-trip; matches the local-registry layout 1:1 | ZIP byte stream: `page.json` + `components/<slug>@<version>.json` (one file per component) + `settings.json` + `domains.json` + `audit.md` + `manifest.json` |

The `archive` shape matches what `spideriq pull` writes to disk, so:

```bash
# Pull the export → local registry
spideriq content pages export <page-id> --format archive --out ./tenant-snapshot.zip
unzip ./tenant-snapshot.zip -d ./tenant-snapshot/

# Edit files locally with the VSCode extension
# (the extension watches ./tenant-snapshot/page.json and the components/*.json files)

# Push back when done
spideriq content pages push ./tenant-snapshot/
```

`spideriq push` runs the same `content_export_page` against the live page first, diffs the local copy against the fresh export, and emits `content_update_page` + per-component `content_update_component` mutations only for changed slices. If the live page diverged between your pull and push, you get a merge prompt — not a silent overwrite.

## Choosing between `content_get_page` and `content_export_page`

| Tool | Returns | Cost | Use when |
|---|---|---|---|
| `content_get_page` | The page row alone (blocks reference components by slug + version, body NOT inlined) | Cheap — single SELECT | You only need page metadata, blocks, SEO. The components themselves are already known. |
| `content_export_page` | Page + ALL referenced components inlined + settings + domains + audit | Heavier — N+1 SELECTs + audit walk | You need the FULL picture before editing, OR you're doing a round-trip, OR you want the audit walk |

Default to `content_get_page`. Reach for `content_export_page` when you actually need the components inlined.

## Gotchas

- **The envelope is a snapshot, not a live view.** Two seconds after export, the page might have moved. The `manifest.snapshot_hash` lets a downstream push detect this; without it, you're flying blind.
- **`audit` is informational, not blocking.** A page with audit findings can still be edited and republished. The audit is your hint about what to fix; SpiderPublish doesn't reject mutations based on it.
- **Component inlining can be large.** A page with 12 Tier 3 components can produce a 500 KB envelope (each component's `js` can be ~30 KB). The `archive` format zips this; the `json` and `md` formats don't.
- **Archive format isn't a backup substitute.** It's a point-in-time export of one page + its components. For tenant-wide backups, run R2 backups (see `CLAUDE.md` → Backups in the main repo).
- **Setting `format: "md"` flattens the JSON tree** for readability but loses the round-trip path. Use `json` or `archive` if you intend to push changes back.

## Verify

For a JSON export, sanity-check the envelope before consuming:

```bash
jq 'keys' export.json
# → ["audit", "components", "domains", "manifest", "page", "settings"]

jq '.audit.findings | length' export.json
# → 0   (clean) or N (issues to surface to the user)

jq '.components | keys' export.json
# → ["hero-gradient", "cta-button", "faq-accordion", ...]
```

For an archive export:

```bash
unzip -l snapshot.zip
# Archive: snapshot.zip
#   page.json
#   components/hero-gradient@v3.json
#   components/cta-button@v2.json
#   settings.json
#   domains.json
#   audit.md
#   manifest.json
```

## Anti-patterns

- **Using `content_export_page` for a quick metadata read.** Use `content_get_page` instead — 10× cheaper.
- **Pushing back a modified `md` export.** The Markdown format is one-way (export only); the `spideriq push` path only consumes `archive` (preferred) or `json`. Edit those.
- **Editing the inlined component body inside `components[]` and expecting it to land on the component row.** The exporter inlines for context; round-trip push routes component edits through `content_update_component` separately. Mixing semantics breaks the push diff.
- **Treating the audit walk as authoritative.** It's 10 lightweight rules. For a deeper analysis run [`../audit/audit-and-fix.md`](../audit/audit-and-fix.md) — that adds visual-check, link-audit, and tenant-scope verification.
- **Skipping the manifest check on push.** `manifest.snapshot_hash` is the safety net against "I edited locally for two days; live page moved underneath." Always check it.

## See also

- [`../audit/audit-and-fix.md`](../audit/audit-and-fix.md) — full audit suite (this recipe's `audit` slice is a subset)
- [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md) — Playwright sidecar for live-render verification
- [`duplicate-page.md`](duplicate-page.md) — when you want a copy in STORE rather than an offline export
- [`restore-page-version.md`](restore-page-version.md) — roll back to a historical snapshot (different semantic; no offline edit)
- [`../reference/block-types.md`](../reference/block-types.md) — block model + component reference shape (what gets inlined)
