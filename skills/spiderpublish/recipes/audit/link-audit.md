# recipes/link-audit

Find every broken internal link across a site in one HTTP call — before a deploy ships them.

## When to use

- You just reorganized navigation or renamed pages, and want to know what broke.
- You're cleaning up legacy URL patterns (e.g. `/en/*` → `/*` after dropping a locale).
- You're about to `content_deploy_site_production` and want a final check.

## The one-shot call

```bash
GET /api/v1/dashboard/projects/{pid}/content/audit/links
# → { valid_count, broken: [{path, source, reason}], proposed_redirects, known_redirects }
```

**MCP tool:** `content_audit_links()` — ships in `@spideriq/mcp-publish@1.6.0+` and kitchen-sink `@spideriq/mcp@1.6.0+`. No required input args.

**CLI:** `spideriq content audit-links [--json]` — ships in `@spideriq/cli@1.6.0+`. Pretty-prints broken links with their JSONPath-shaped `source` strings + proposed redirects. Exits non-zero when broken links are present so CI / pre-push hooks gate cleanly. `--json` emits the raw envelope.

**Runnable example:** [examples/audit-links.sh](../../../examples/audit-links.sh) — covers both the CLI path (preferred) and the raw HTTP path (fallback for shells without Node).

## What gets scanned

| Source | What's inspected |
|---|---|
| Every published `content_pages` row | Every `url`, `href`, `link`, `to`, `target_url`, `destination` string anywhere in the `blocks` JSON tree |
| Every `content_navigation` row (header, footer, docs_sidebar) | Every `url` string in the nested items JSON |

## How validation works

A link is **internal** if it starts with `/` (and isn't `//` — that's protocol-relative). External `https://...`, `mailto:`, `tel:`, fragments (`#section`) are skipped.

For each internal link:

1. Normalize (strip query string, fragment, trailing slash, lowercase).
2. Compare against the set of valid targets:
   - Published page slugs — `home` → `/`, others → `/{slug}`
   - Published post slugs — `/blog/{slug}`
   - Active `content_redirects` from_path entries
3. No match → add to `broken[]` with a `source` string naming the exact tree position.

## Response shape

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

## Follow-up actions

The response tells you where to go next:

1. **Fix at the source** — `source: "page:home/block[2].cta_primary.url"` means `blocks[2].data.cta_primary.url` on the page with slug `home`. Use `content_update_page` to edit that block.
2. **Or create a redirect** — `proposed_redirects` suggests 301s when a broken path's suffix matches an existing slug. Review each one, then `content_create_redirect` for the ones you want.

## Why this matters

Before this tool, cleaning up legacy URL patterns across a 30-page site meant reading every page + every menu manually. Two real reports inspired this:

- **Unavis migration** — drop a multi-language structure (`/en/*` → flat). Without link-audit, clients miss at least one of the ~20 nav entries or CTA buttons.
- **Onyx Radiance migration** — rebuild 16 pages with flat slugs after hitting the nested-slug 404 bug. Several `/product/xxx` → `/product-xxx` references lived in page CTAs and were only discovered by 404 spikes post-deploy.

## Defaults + limits

- No caching — each call does a live SQL walk. Typical run: 50–200ms for a 50-page site.
- Protected by the standard content-scoped auth (session cookie OR PAT).
- Dual-mounted under both the legacy and Phase 11+12 URL forms:
  - `/api/v1/dashboard/content/audit/links` (legacy)
  - `/api/v1/dashboard/projects/{pid}/content/audit/links` (scoped)

## See also

- [recipes/preview-iteration](../preview-iteration/) — general edit/preview/deploy cycle
- [recipes/component-update-and-propagate](../component-update-and-propagate/) — the one-shot for changing components across many pages
- [LEARNINGS.md → Apr 2026 Triage](../../../LEARNINGS.md#apr-2026-triage) — the silent-failure modes this closes
