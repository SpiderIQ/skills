# recipes/content/restore-page-version

Roll a page back to a historical snapshot — **safely**. The restore tool defaults to dry_run so you see the diff before you spend a confirm_token.

## When to use

- A bad deploy hit production and you need to revert one page without rolling back the whole site (for the site-level rollback see [`../deploy/rollback-deploy.md`](../deploy/rollback-deploy.md)).
- A client edit dropped a hero / CTA and you want to bring back the previous version's `blocks[]`.
- A teammate landed a draft on the wrong page and you need the original copy back.
- Auditing what changed between version N and N+1 before deciding whether to restore.

## Prerequisites

- A PAT scoped to the tenant that owns the page (see [`../../_shared/auth.md`](../../_shared/auth.md)).
- The page's `page_id` (UUID). Get it from `content_list_pages` or the dashboard URL.
- A historical `version_number` to target. `content_list_page_versions({ page_id })` returns the full ledger; each row carries `{version_number, snapshot_block_count, snapshot_created_at, change_summary}`.
- If the page is currently **locked** (a teammate parked it for review), you need either the lock holder's session OR `super_admin` / `brand_admin` to pass `force=true`. See [`lock-page-during-review.md`](lock-page-during-review.md).

## Steps

### 1. List versions to find your target

```
content_list_page_versions({ page_id: "<uuid>" })
# → [
#     { version_number: 7, snapshot_block_count: 14, snapshot_created_at: "...", change_summary: "Updated hero copy" },
#     { version_number: 6, snapshot_block_count: 12, ... },
#     ...
#   ]
```

Pick the version you want to land — usually the one immediately before the bad change.

### 2. Inspect the target version (optional, recommended)

Before restoring, see what the snapshot actually looks like:

```
content_get_page_version({ page_id: "<uuid>", version_number: 6 })
# → { page: {<full snapshot>}, version_number: 6, snapshot_created_at: "..." }
```

Useful when version numbers are dense and you're not sure which one carries the wording you remember.

### 3. Dry-run the restore

```
content_restore_page_version({
  page_id: "<uuid>",
  version_number: 6
})
# → {
#     dry_run: true,
#     preview: {
#       before: { block_count: 14, status: "published", title: "Pricing" },
#       after:  { block_count: 12, status: "draft",     title: "Pricing" },
#       diff:   { blocks_removed: 3, blocks_added: 1, snapshot_created_at: "..." }
#     },
#     confirm_token: "cft_01HXXXXXXXXXX",
#     expires_at: "...",
#     snapshot_hash: "sha256:..."
#   }
```

This is `safe-default gate` — dry_run is **on by default** (see [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) → "Safe-default gate"). The preview lists `snapshot_block_count` vs `current_block_count` + `snapshot_created_at`. Verify the deltas match your intent.

### 4. Consume the token

```
content_restore_page_version({
  page_id: "<uuid>",
  version_number: 6,
  confirm_token: "cft_01HXXXXXXXXXX"
})
# → { success: true, page: {<new draft>}, new_version_number: 8 }
```

The restored page lands as **status='draft'** — never auto-publishes over the live page. A new version row is appended (here `8`) recording the restore so the audit chain stays intact: 6 → 7 (bad change) → 8 (restore from 6). You can always re-restore to 7 if the restore itself was wrong.

### 5. Verify, then publish

```
content_get_page({ page_id: "<uuid>" })
# → confirm blocks[] match the version 6 snapshot you expected

content_publish_page({ page_id: "<uuid>" })
# → safe-default dry_run; preview the diff, then confirm with token
```

If this page is part of a published site, follow with `content_deploy_site_preview` → `content_deploy_site_production` to push the change live. See [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md).

## Gotchas

- **The restore always lands as draft.** If the live version was 7 and you restore from 6, visitors still see 7 until you publish 8 (the restore). That's by design — same reason the dry_run is on; gives you a chance to compare.
- **`snapshot_hash` is bound to the page state at dry_run time.** If a teammate edits the page between your dry_run and confirm, you get a 403 `snapshot_mismatch`. Re-run dry_run; the diff will reflect their edit.
- **Token TTL is 7 days** for tool-level dry_runs (5 minutes for the deploy pipeline). Sitting on a restore token over a weekend is fine; sitting on it for two weeks is not.
- **Locked pages refuse restore without `force`.** A 423 envelope returns `{ locked_by_actor_id, locked_reason, unlock_endpoint }`. Either call `unlock_page` first (if you own the lock) or pass `force=true` if you have `super_admin` / `brand_admin`.
- **Page slug doesn't roll back** — the restore brings back `blocks[]`, `title`, `seo_title`, `seo_description`. The current slug stays. If you also need to roll back the slug (rare), follow up with `content_update_page({ page_id, slug: "<old-slug>" })`.

## Verify

After publishing the restored version, eyeball the live page if the tenant has a custom domain attached:

```
content_visual_check({
  page_url: "https://<tenant-domain>/<page-slug>",
  viewport: "desktop"
})
# → { ok: true, body_text_preview: "...the restored copy you expect..." }
```

If the page contains a form, assert on `dom.shadow_hosts.includes("spideriq-form")`, **NOT** `body_text_preview` — see Rule 62 in [`../reference/booking-model.md`](../reference/booking-model.md).

## Anti-patterns

- **Calling restore without listing versions first.** `version_number` is 1-indexed and dense. Guessing "the previous one" picks the wrong row half the time. Always list, then `get_page_version` to confirm, then restore.
- **Treating restore as a delete-and-recreate.** It's not. Restore re-emits `blocks[]` from the snapshot into a **new draft** on the same page row — same `page_id`, same primary key. No URLs break, no inbound links rot.
- **Skipping the dry_run** because "I'm sure." The safe-default gate exists for exactly the case where you're sure and wrong. Cost is one extra round-trip; benefit is the diff envelope catching a wrong-tenant call (Lock 1) or wrong-page-id (Lock 5 — see [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md)).
- **Forgetting to publish + deploy after restoring.** The restored page sits as draft until you publish; the site visitors still see the old version until `content_deploy_site_production` runs. Restore is two steps in STORE; visitors don't see anything until SERVE redeploys.
- **Using `force=true` to bypass another reviewer's lock without coordinating.** The lock holder will see your restore land mid-review. Ping them in chat first; locks exist precisely to avoid this surprise.

## See also

- [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md) — verify the restored page renders correctly before/after deploy
- [`lock-page-during-review.md`](lock-page-during-review.md) — pair with restore: lock → restore → unlock
- [`../deploy/rollback-deploy.md`](../deploy/rollback-deploy.md) — site-level rollback (every page in one shot)
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — `safe-default gate`, confirm-token envelopes, `ConfirmTokenError` map
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT scope + tenant binding
