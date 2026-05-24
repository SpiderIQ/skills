# recipes/lock-during-review

Lock a page against further edits during client review or scheduled launch. Other agents (and dashboard users) see **423 Locked** with the lock provenance and an `unlock_endpoint` URL until the lock-holder (or a super_admin via `force=true`) unlocks. Closes the gap where two agents race on the same page mid-review.

## When to use

- Designer or agency hands a page off for client review and doesn't want any agent to keep editing.
- Scheduled launch — page is "frozen" until a specific date/time; lock is set at the start and unlocked at go-live.
- An incident — a published page is misbehaving and you want to stop further mutations while you investigate.
- Pre-restore — before calling `content_restore_page_version`, lock the page so a parallel agent doesn't apply more edits between the dry-run preview and the confirm.

## The one-shot calls

```bash
# Lock
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/lock
Body: { "reason": "client review week of 2026-05-12" }
# → { id, slug, is_locked: true, locked_by_actor_id, locked_at, locked_reason }

# Unlock (lock-holder OR super_admin / brand_admin with ?force=true)
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/unlock
# → { id, slug, is_locked: false, locked_by_actor_id: null }

# List versions
GET /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/versions
# → { page_id, versions: [{version_number, title, block_count, blocks_size, change_summary, created_at, ...}], total }

# Get one version (full body)
GET /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/versions/{N}

# Restore — Phase 11+12 dry_run/confirm_token gated
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/restore?version_number=N&dry_run=true
# → { dry_run: true, preview: {snapshot_block_count, current_block_count, snapshot_created_at, will_become}, confirm_token, expires_at }
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/restore?version_number=N&confirm_token=cft_xxx
# → restored page row (status=draft; new version row appended with change_summary='Restored from vN')
```

**MCP tools** — ship in `@spideriq/mcp-publish@1.11.0+` and kitchen-sink `@spideriq/mcp@1.11.0+` (94 atomic tools total):

- `content_lock_page({page_id, reason?})`
- `content_unlock_page({page_id, force?})` — `force=true` requires super_admin or brand_admin (server-enforced)
- `content_list_page_versions({page_id})`
- `content_get_page_version({page_id, version_number})`
- `content_restore_page_version({page_id, version_number, dry_run?, confirm_token?, force?})`

## The 423 Locked envelope (what other agents see)

When the page is locked and a mutation comes in (`PATCH /pages/{id}`, `/publish`, `/unpublish`, `DELETE`, `/insert-section`, `/restore`), the server returns **HTTP 423 Locked** with this body:

```json
{
  "detail": {
    "error": "page_locked",
    "message": "Page is locked by api:cli_xxx.",
    "locked_by_actor_id": "api:cli_xxx",
    "locked_at": "2026-05-09T21:11:00Z",
    "locked_reason": "client review week of 2026-05-12",
    "unlock_endpoint": "/api/v1/dashboard/projects/cli_xxx/content/pages/<id>/unlock"
  }
}
```

**Recovery path for the receiving agent:**

1. Parse `locked_by_actor_id` and `locked_reason`. If the reason indicates a deadline ("client review week of 2026-05-12"), the right move is to back off and revisit later.
2. If you are the lock-holder (your `actor_id` matches), call `content_unlock_page({page_id})` and retry.
3. If you have super_admin or brand_admin role and the lock-holder is unavailable, call `content_unlock_page({page_id, force: true})`. This emits an audit row.
4. Otherwise: do not retry mechanically. Use `content_list_page_versions` if you need to inspect history during the lock window — that endpoint is read-only and works on locked pages.

## Authorization model

| Actor | Can lock? | Can unlock (own lock)? | Can unlock (someone else's lock)? |
|---|---|---|---|
| `client_user` | yes | yes | no |
| `brand_admin` | yes | yes | yes (with `?force=true`) |
| `super_admin` | yes | yes | yes (with `?force=true`) |
| `api_client` (PAT) | yes | yes | no — even with `force=true`, server returns 403 (`force=true requires super_admin or brand_admin role.`) |

## Idempotency

- **Lock** is idempotent — re-locking refreshes `locked_at` and `locked_reason`. The previous lock-holder loses the lock provenance but mutations stay refused.
- **Unlock** on an already-unlocked page returns the current page state (no error).
- **Restore** appends a NEW version row recording the restore — the audit chain stays linear. Calling restore against the same `version_number` twice creates two new version rows.

## Anti-patterns

- **Don't** call `content_unlock_page({force: true})` reflexively when you see a 423. Read the `locked_reason` first; if it names a deadline, the lock is intentional. Force-unlocking around an active client review breaks the trust model the lock exists to enforce.
- **Don't** loop on a 423 retry-without-backoff. The lock provenance won't change until someone explicitly unlocks. If your agent is the lock-holder (matched `actor_id`), call unlock; otherwise back off.
- **Don't** call `content_publish_page` to "force" through a lock. Publish is gated by the same lock check; you'll get the same 423.
- **Don't** assume `versions[]` is unbounded — `version_number` is monotonically increasing and a long-lived page can accumulate hundreds of versions. Use the `block_count` + `blocks_size` summary in the list to decide which versions to fetch in full.

## Idempotency / cost notes

- Lock toggle is a single `UPDATE content_pages` — sub-millisecond.
- Versions list uses `idx_content_pages_locked` partial index for the cross-tenant "what's locked" query (super_admin admin dashboard).
- `versions/{N}` returns the full snapshot blocks — can be tens of KB; prefer the summary list for browsing, fetch the full version only when you need to diff.
