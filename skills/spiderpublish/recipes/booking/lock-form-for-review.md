# recipes/booking/lock-form-for-review

Park a form against accidental edits while a human reviews it — `form_lock` / `form_unlock`. Idempotent, returns 423 to other editors with the unlock endpoint baked in. Pairs with [`../content/lock-page-during-review.md`](../content/lock-page-during-review.md) for the page-level twin.

## When to use

- An agent (or another teammate) is about to send the form to a client for approval and you don't want a second editor accidentally mutating fields between "sent" and "approved."
- You're running a live A/B with two field orderings and want one variant frozen while the other iterates.
- A regulated form (legal, compliance, KYC) needs a "no changes after this point" guarantee before going to audit.
- Pattern: "freeze this exactly the way it is for the next 48 hours."

## Prerequisites

- A PAT scoped to the tenant that owns the form.
- The form's `flow_id` (UUID). Works for both `kind='form'` and `kind='booking'` (same `booking_flows` table).
- For unlock: either the lock holder's session, OR `super_admin` / `brand_admin` with `force=true`.

## Lock — the one call

```
form_lock({
  flow_id: "<uuid>",
  reason:  "Sent to client for approval — do not edit until ack"
})
# → {
#     success: true,
#     flow: {
#       ...,
#       is_locked: true,
#       locked_by_actor_id: "act_...",   # your PAT's actor id
#       locked_at: "2026-05-24T12:34:56Z",
#       locked_reason: "Sent to client for approval — do not edit until ack"
#     }
#   }
```

Idempotent — re-locking refreshes `locked_at` and `locked_reason`. Any role with form-CRUD access can lock; unlock is more restrictive.

## Unlock — the same shape

```
form_unlock({ flow_id: "<uuid>" })
# → { success: true, flow: { is_locked: false, ... } }
```

The lock holder can unlock unconditionally. Other callers get **403** (or **404** if they aren't the holder — the API does NOT leak the lock-holder identity to unprivileged callers; you'd see "not found" rather than "you can't").

### Force-unlock (`super_admin` / `brand_admin` only)

```
form_unlock({
  flow_id: "<uuid>",
  force:   true
})
# → { success: true, flow: { ... } }    (overrides any holder)
```

`force=true` is rejected for non-super_admin / non-brand_admin callers regardless of who locked. Use sparingly — there's an audit log row for every force-unlock.

## What lock blocks vs allows

| Operation | Blocked when locked? |
|---|---|
| `form_update`, `form_add_field`, `form_remove_field`, `form_update_field`, `form_reorder_fields` | **Yes** — 423 Locked with the unlock endpoint in the envelope |
| `form_add_choice`, `form_add_logic_rule`, `form_remove_logic` | **Yes** — 423 |
| `form_publish`, `form_delete`, `form_restore_version` | **Yes** — 423 |
| `form_duplicate` | **No** — duplicates are NEW rows; the new flow is unlocked |
| `form_get`, `form_preview_url`, `form_get_embed_snippet`, `form_validate` | **No** — reads always allowed |
| `form_test_submit` | **No** — submissions to the locked form's public URL still work (lock blocks AUTHORING, not USE) |
| `form_lock` (re-lock by holder) | **No** — idempotent refresh of reason/timestamp |

The 423 envelope returns:

```json
{
  "status": 423,
  "code": "form_locked",
  "locked_by_actor_id": "act_xxx",
  "locked_reason": "Sent to client for approval",
  "locked_at": "2026-05-24T12:34:56Z",
  "unlock_endpoint": "/api/v1/booking/flows/<uuid>/unlock"
}
```

Use the `unlock_endpoint` field to compose a "request unlock" UI affordance rather than hardcoding the path.

## Steps — typical review flow

```
1. form_update / form_add_field / ...     — finalize the form
2. form_publish                            — flip to status='active' (safe-default gated)
3. form_lock({ flow_id, reason })          — freeze for review
4. form_preview_url({ flow_id })           — share the /f/<id> URL with the reviewer
5. (reviewer eyeballs, sends ack)
6. form_unlock({ flow_id })                — reopen for edits
   OR
6'. form_unlock({ flow_id, force: true })  — admin override if the lock holder is unavailable
```

## Gotchas

- **404 vs 403 on unlock is intentional.** Non-holders get 404, not "you can't" — protects the lock holder's identity. If you expected 200 and got 404, check if you're actually the lock holder (`form_get` returns `locked_by_actor_id`).
- **Lock survives form duplication, but the duplicate is unlocked.** `form_duplicate` creates a new row with `is_locked=false`. If you want the duplicate locked too, call `form_lock` on the new flow_id.
- **Lock does NOT freeze the live `/f/<flow_id>` URL.** Submissions keep landing in the same flow's responses. The lock is editor-side only. If you need to STOP accepting submissions, call `form_unpublish` (separate from `form_lock`).
- **No TTL — locks persist until explicitly unlocked.** Forget to unlock and the form sits frozen indefinitely. Pair every lock with a calendar reminder or a follow-up task.
- **`reason` is free-text shown in the dashboard.** Keep it short and actionable ("Sent to ACME for approval — Slack #client-acme") so the next teammate doesn't have to chase context.

## Verify

```
form_get({ flow_id })
# → { ..., is_locked: true, locked_by_actor_id, locked_reason, locked_at }
```

Try to mutate as another user to confirm the gate:

```
form_update({ flow_id, changes: { name: "test" } })
# → 423 Locked envelope (if you're not the holder)
```

## Anti-patterns

- **Locking a form and forgetting to unlock for weeks.** No TTL. Always set a follow-up.
- **Using `force=true` to bypass a teammate's lock without coordinating.** Force-unlock is logged. Ping the holder in chat first; locks exist precisely to avoid this surprise.
- **Locking to "stop submissions."** Wrong primitive. Lock freezes authoring; `form_unpublish` freezes submissions.
- **Treating 404-on-unlock as "form doesn't exist."** It probably means you aren't the lock holder. Run `form_get` to check `is_locked` + `locked_by_actor_id`.
- **Composing the unlock URL by hand.** Use the `unlock_endpoint` field from the 423 envelope — the path may change; the field is canonical.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "freeze a form during review"
# Top-1 should be: recipes/booking/lock-form-for-review.md
```

## See also

- [`../content/lock-page-during-review.md`](../content/lock-page-during-review.md) — page-level twin (same primitive on `content_pages`)
- [`share-form-standalone.md`](share-form-standalone.md) — share the `/f/<id>` URL with reviewers (lock-friendly: reads are allowed)
- [`build-form.md`](build-form.md) — author the form before locking it
- [`../reference/booking-model.md`](../reference/booking-model.md) — `booking_flows` schema (lock columns are on the same row)
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT actor identity + role check for `force=true`
