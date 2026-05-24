# recipes/deploy/rollback-deploy

A bad deploy hit production and visitors see broken pages. Roll back — **fast, safely, and with an audit trail**. The mechanic is per-page version restore + redeploy; there's no "undo deploy" big red button.

## When to use

- A `content_deploy_site_production` call landed and visitors are reporting broken pages.
- A theme apply pushed the wrong colours / fonts and you need yesterday's look back.
- A migration script touched 20 pages with a typo and you need them all reverted.
- An automation overwrote SEO titles and search rankings are about to drop.

## Honest framing — no single "undo deploy" tool

SpiderPublish doesn't have a `content_rollback_deploy({ to_version_id })` tool. A deploy is a multi-step pipeline (KV write → CF Worker recreate); rolling it back means **restoring the underlying pages + components to their previous versions, then redeploying**. That's three primitives:

| Primitive | What it does |
|---|---|
| `content_list_page_versions({ page_id })` | Find the version BEFORE the bad deploy |
| `content_restore_page_version({ page_id, version_number })` | Bring back that snapshot as a new draft |
| `content_deploy_site_production({ confirm_token })` | Push the restored state live |

For a multi-page rollback, loop over the affected pages.

## Prerequisites

- A PAT scoped to the tenant.
- The deploy timestamp (or `version_id` from `content_deploy_status`) so you know what time the bad deploy happened.
- Optionally: list of pages affected (if it's not "everything").

## Step 1 — Identify the bad deploy

```
content_deploy_status()
# → {
#     latest: { version_id: 48, deployed_at: "2026-05-24T14:32:00Z", status: "live" },
#     history: [
#       { version_id: 47, deployed_at: "2026-05-24T13:01:00Z", status: "superseded" },
#       { version_id: 46, deployed_at: "2026-05-23T09:15:00Z", status: "superseded" },
#       ...
#     ]
#   }
```

If the bad deploy is `48`, you want to land the state from `47` (the previous good deploy).

## Step 2 — Decide the scope

**Option A — Single page is broken:** restore just that page, redeploy.

**Option B — Everything is broken** (theme apply, settings update, mass migration): identify ALL affected pages.

```
content_list_pages({ limit: 500 })
# → for each, content_list_page_versions to see if it was modified in the bad-deploy window
```

The bad-deploy window is `[history[0].deployed_at, latest.deployed_at]`. Any page version landed in that window is suspect.

## Step 3 — Restore each affected page

For one page:

```
# Find the version BEFORE the bad change
content_list_page_versions({ page_id: "<uuid>" })
# → [
#     { version_number: 12, snapshot_created_at: "2026-05-24T14:25:00Z" },   # bad
#     { version_number: 11, snapshot_created_at: "2026-05-23T16:40:00Z" },   # last good
#     ...
#   ]

# Restore (safe-default gated)
content_restore_page_version({ page_id: "<uuid>", version_number: 11 })
# → { dry_run: true, preview: {...}, confirm_token: "cft_..." }

# Confirm
content_restore_page_version({ page_id: "<uuid>", version_number: 11, confirm_token: "cft_..." })
# → restored as draft (new version_number 13 in the audit chain: 11 → 12 → 13)

# Publish so it'll deploy
content_publish_page({ page_id: "<uuid>" })
# → safe-default gated; preview + confirm
```

For a multi-page rollback, loop:

```python
for page_id in affected_pages:
    versions = content_list_page_versions(page_id)
    # find last version with snapshot_created_at < bad_deploy_at
    target = next(v for v in versions if v.snapshot_created_at < bad_deploy_at)

    # dry-run
    preview = content_restore_page_version(page_id, target.version_number)
    # confirm
    content_restore_page_version(page_id, target.version_number, confirm_token=preview.confirm_token)
    # publish (also gated)
    publish_preview = content_publish_page(page_id)
    content_publish_page(page_id, confirm_token=publish_preview.confirm_token)
```

## Step 4 — Theme / settings rollback (if applicable)

If the bad deploy included a theme change or `content_update_settings`:

```
# For theme: re-apply the previous theme by slug
template_apply_theme({ theme_slug: "<previous-theme-slug>" })
# → dry_run; confirm

# For settings: PATCH back to the previous values
content_update_settings({ settings: { default_meta_title: "<previous>", ... } })
# → safe-default gated
```

## Step 5 — Redeploy

Once all pages + theme + settings are restored, redeploy:

```
content_deploy_readiness()
# → confirm no blocking issues (e.g. the bad version didn't leave settings in a half-state)

content_deploy_site_preview()
# → { preview_url, confirm_token, ... }

# Eyeball the preview URL — confirm the restore actually landed visually

content_deploy_site_production({ confirm_token: "cft_..." })
# → { status: "live", version_id: 49 }
```

You now have **`version_id: 49`** that contains the state of `version_id: 47`. The bad deploy (`48`) is in the history, marked superseded, but its rows aren't gone — re-restorable if needed.

## Step 6 — Verify with visual-check

Don't trust a 200. Run [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md):

```
content_visual_check({
  page_url: "https://<tenant>/<key-page>",
  viewport: "desktop"
})
# → confirm the rolled-back content actually shows
```

For form-bearing pages: `dom.shadow_hosts.includes("spideriq-form")`, NOT `body_text_preview` — Rule 62, [`../reference/booking-model.md`](../reference/booking-model.md).

## Gotchas

- **There is no `undo_deploy` tool.** Rollback = restore pages + redeploy. Anyone looking for "the rollback button" needs this recipe.
- **Restore lands as draft.** You MUST `content_publish_page` after, then `content_deploy_site_production`. Three gated steps per page; budget time.
- **Theme apply rollback re-applies the previous theme**, but the previous theme's tokens may have been mutated since. Capture the actual previous tokens via `template_get_config` BEFORE the bad theme apply if you can; otherwise you're restoring "the slug that was active" not "the exact tokens."
- **Component rollback is its own primitive.** If the bad deploy included `content_update_component` mutations, also use `component_rollback({ slug, target_version })` — see [`../components/rollback-component.md`](../components/rollback-component.md).
- **CF Worker cache** holds the bad bundle for ~30s after deploy. Visitors who load during the cache window still see the bad version. `content_visual_check` from a fresh edge does NOT hit cache; eyeball from a real browser to confirm cache purge.
- **Some clients receive instant push notifications / emails based on page state.** A rollback may trigger a "back to old version" notification cycle. Audit your automations before rolling back live.
- **Database-side, the bad version is preserved.** This is intentional — re-restorable, audit-loggable. Don't try to "delete" the bad version row.

## Verify

```
# Page-level
content_get_page({ page_id })
# → confirm blocks[] match what you expected from the restored version

# Site-level
content_deploy_status()
# → latest.version_id should be your new rollback deploy (e.g. 49)

# Live verification
curl -sI "https://<tenant>/<key-page>" | grep -E "etag|last-modified"
# → confirm the response is from the new deploy

content_visual_check({ page_url: "..." })
# → confirm rolled-back content renders
```

## Anti-patterns

- **Trying to "undeploy" by deleting the deploy version row.** The row IS the audit chain. Restore + redeploy preserves history.
- **Skipping the dry_run on `content_restore_page_version`.** Safe-default gated for a reason — the dry_run shows you EXACTLY what's coming back. Skip it and you might restore the wrong version on the wrong page (Lock 5 catches the wrong-tenant case but not wrong-page).
- **Rolling back without first identifying scope.** If a theme apply broke 50 pages and you restore one, the other 49 still look broken. List + filter affected pages first.
- **Forgetting the `content_publish_page` step.** Restore creates a draft; visitors still see the bad live version until you publish + redeploy.
- **Redeploying without `content_visual_check`.** A 200 from `content_deploy_site_production` means "request accepted." Visual check confirms visitors actually see the restored content.
- **Rolling back during peak traffic without notifying stakeholders.** Even a clean rollback may show the wrong content for ~30s during cache transition. Coordinate.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "roll back a bad deploy"
# Top-1 should be: recipes/deploy/rollback-deploy.md
```

## See also

- [`../content/restore-page-version.md`](../content/restore-page-version.md) — the per-page primitive used in Step 3
- [`../components/rollback-component.md`](../components/rollback-component.md) — when the bad change was inside a component, not on a page
- [`deploy-preview-only.md`](deploy-preview-only.md) — use this BEFORE production deploys to catch the issue early
- [`../audit/deploy-readiness.md`](../audit/deploy-readiness.md) — pre-deploy checklist to prevent needing a rollback
- [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md) — post-rollback verification
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the full gate + token semantics
