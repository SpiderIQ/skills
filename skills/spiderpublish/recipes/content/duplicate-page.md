# recipes/content/duplicate-page

Make a new page by copying an existing one — **one call, not gated**, fresh draft, fresh UUIDs on every block.

## When to use

- The client wants a new page that's similar to an existing one — duplicating saves 80% of the build (faster than rebuilding from blocks, lower variance than a template apply).
- You're applying a template by cloning master pages into the tenant (template-gallery pattern).
- Internal A/B testing — fork a published page, edit copy, publish under a new slug, route a slice of traffic with the redirect block.
- Spinning up a per-event landing page that reuses the main marketing page's structure with one section swapped.

## Prerequisites

- A PAT scoped to the tenant that owns the source page.
- The source page's `page_id` (UUID).

## The one call

```
content_duplicate_page({
  page_id: "<source-uuid>"
})
# → {
#     id: "<new-uuid>",
#     slug: "<original-slug>-copy",      # or -copy-2, -copy-3, ... lowest unused
#     title: "<original-title> (Copy)",
#     status: "draft",                    # always
#     blocks: [...with fresh UUIDs...],
#     ...
#   }
```

That's it. Not Phase 11+12 gated — duplicates create **new rows** rather than overwriting state, so no confirm_token is needed. Just call once and you get the new page.

### With a chosen slug

```
content_duplicate_page({
  page_id: "<source-uuid>",
  new_slug: "black-friday-2026"
})
# → { id: "<new-uuid>", slug: "black-friday-2026", ... }
```

`new_slug` must match `^[a-z0-9][a-z0-9-]*$` — no `/`, no leading dash, no uppercase. The MCP tool enforces the pattern; a bad slug returns a 422 with the regex.

## What gets cloned vs regenerated

| Field | Behavior |
|---|---|
| `id` | **Regenerated** — new page UUID |
| `slug` | Auto: `{original}-copy[-N]`. Explicit: `new_slug`. |
| `title` | `<original> (Copy)` so the dashboard list shows it distinctly |
| `status` | Forced to `draft` regardless of the source's state |
| `blocks[].id` | **Regenerated** for every block (fresh UUIDs) so the new page is independent of the source |
| `blocks[].component_slug`, `props`, `data` | Identical to source |
| `blocks[].anchor_block_id` | Rewritten to point at the new block UUIDs (preserves intra-page anchor links) |
| `seo_title`, `seo_description` | Copied verbatim — **edit these before publishing** to avoid duplicate-content SEO hits |
| `template` | Copied |
| `version_number` | Resets to `1` on the new page (the duplicate is a fresh history) |

## Steps

```
1. content_get_page({ page_id: "<source-uuid>" })   — confirm the source is what you think
2. content_duplicate_page({ page_id, new_slug? })    — get the new draft
3. content_update_page({ page_id: "<new-uuid>", seo_title, seo_description })
                                                      — fix SEO so the duplicate doesn't compete with the source
4. content_publish_page({ page_id: "<new-uuid>" })   — safe-default dry_run; review + confirm
5. content_deploy_site_preview() → content_deploy_site_production(confirm_token)
                                                      — push live
```

## Gotchas

- **SEO will collide if you publish the duplicate as-is.** `seo_title` + `seo_description` copy verbatim. If both pages are indexed, Google penalises duplicate content. Always edit SEO on the new page before publishing — Step 3 is non-optional for production.
- **Slug auto-generation is lowest-N.** First duplicate of `pricing` → `pricing-copy`. Second → `pricing-copy-2`. Tenth → `pricing-copy-10`. If `pricing-copy-3` was deleted, the next call still picks `pricing-copy-3` (lowest unused). Predictable but easy to confuse with stale lists.
- **Cross-tenant duplication is refused 404.** A PAT scoped to `cli_A` cannot duplicate a page from `cli_B` — Lock 5 (the WHERE clause) rejects the read, so the duplicate never reaches the INSERT. Use the marketplace `content_apply_site_template` flow for cross-tenant copies of curated content.
- **Block-internal references survive but external page refs don't.** `anchor_block_id` (intra-page) is rewritten to the new UUIDs. But if a block has a `data.next_page_id` pointing at another page on the source, the duplicate still points at THAT page (not a duplicate of it). Audit `data.*_page_id` fields after duplication.
- **Duplicating a page with a `kind='form'` flow block** copies the block (with its `component_slug: "form"` and `data.flow_id`) — but you now have **two pages embedding the same flow**. Submissions from both pages land in the same flow. If you want them isolated, duplicate the flow too with `form_duplicate({ flow_id })` and rewire the new page's block.

## Verify

```
content_get_page({ page_id: "<new-uuid>" })
# → confirm status=draft, fresh block UUIDs, slug matches what you asked for

# Diff against the source to confirm only id/slug/title changed:
diff <(content_get_page({page_id: "<source-uuid>"}) | jq .blocks) \
     <(content_get_page({page_id: "<new-uuid>"})    | jq '.blocks | map(.id = "REDACTED")')
# Should be empty (modulo the .id redaction).
```

After publish + deploy, eyeball the new URL:

```
content_visual_check({
  page_url: "https://<tenant-domain>/<new-slug>",
  viewport: "desktop"
})
```

## Anti-patterns

- **Publishing the duplicate without editing SEO.** Duplicate-content penalty. Always edit `seo_title` + `seo_description` first.
- **Treating `content_duplicate_page` as "copy and edit in place."** It's "copy to a new row." If you wanted to edit the source, just call `content_update_page` on the source.
- **Duplicating to "back up" a page before edits.** Use [`export-page-roundtrip.md`](export-page-roundtrip.md) for a true snapshot, or [`restore-page-version.md`](restore-page-version.md) to roll back if needed. The version history is already there — don't pollute the page list.
- **Looping `content_duplicate_page` 50× to seed a directory.** Use [`../directory/import-listings.md`](../directory/import-listings.md) for bulk SEO pages — that hits a single bulk endpoint instead of 50 round-trips.
- **Forgetting that `content_publish_page` is safe-default-gated.** Even though duplicate isn't gated, publishing the new page is. Review the preview, then confirm with the token.

## See also

- [`duplicate-block.md`](duplicate-block.md) — same primitive at block granularity (deep-copy one section inside the same page)
- [`apply-site-template.md`](apply-site-template.md) — duplicate a CURATED set of pages from the marketplace in one call
- [`export-page-roundtrip.md`](export-page-roundtrip.md) — when you need an offline copy rather than a STORE duplicate
- [`landing-page.md`](landing-page.md) — building a new page from scratch (alternative path)
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — publish + deploy gate flavours
