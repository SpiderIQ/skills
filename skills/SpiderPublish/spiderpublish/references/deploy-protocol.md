# reference/deploy-protocol

The full two-phase pipeline — `?dry_run=true` → preview → `?confirm_token=cft_…` — and the five-lock tenant defense around it. Cited by every mutation recipe. Read once per session; don't repeat it inside individual recipes.

## TL;DR — the three things to remember

1. **`?dry_run=true` is OPT-IN, not the default.** A `POST /pages` without flags creates the page **immediately**. Pass `?dry_run=true` (or `dry_run: true` on the MCP tool) when you want a preview first. (F-8 / Rule 60 — production `guidance.warn` was lying about this until 2026-05-20.)
2. **Destructive ops default to `dry_run=true`.** `content_delete_page`, `content_publish_page`, `content_unpublish_page`, `form_delete`, `form_publish`, `template_apply_theme`, `content_deploy_site_production` — first call returns a preview + `confirm_token`; second call with `?confirm_token=cft_…` actually mutates.
3. **A `confirm_token` is single-use, snapshot-bound, expires.** 7-day TTL on tool-level dry_runs, 5-min TTL on the deploy pipeline. 410 = expired, 409 = consumed, 403 = mismatch.

If you only remember those three, the rest of this doc clarifies edge cases.

## The two flavours of gate

SpiderPublish has two slightly different gate behaviours. Know which one you're calling.

| Flavour | Default | Endpoints | Why |
|---|---|---|---|
| **Opt-in gate** (most tools) | dry_run **off** — immediate write | `content_create_page`, `content_update_page`, `content_update_post`, `content_create_component`, `content_update_component`, `form_create`, `form_update`, `template_upsert`, `template_delete`, `content_delete_post` | These are the high-traffic editing tools. Forcing a two-phase flow on every keystroke breaks the authoring loop. Pass `dry_run: true` explicitly when you want a preview. |
| **Safe-default gate** (destructive) | dry_run **on** — preview first | `content_delete_page`, `content_publish_page`, `content_unpublish_page`, `content_archive_component`, `content_delete_component`, `content_publish_component`, `content_restore_page_version`, `form_delete`, `form_publish`, `form_restore_version`, `template_apply_theme`, `content_deploy_site_production`, `content_deploy_site` | These are one-shot, hard-to-undo, or "this is what end users see now" — defaulting to a preview catches the wrong-tenant or wrong-flag case before it lands. Pass `confirm_token` (from the dry_run response) to mutate. |

There's no third flavour. Reads have no gate (`content_get_page`, `form_get`, `content_list_components`).

## The dry_run envelope

Every dry_run call returns the same shape:

```json
{
  "dry_run": true,
  "preview": {
    "before": { /* the row as it is today */ },
    "after":  { /* the row as it WILL be if you confirm */ },
    "diff":   { /* keys changed, count, summary */ }
  },
  "confirm_token": "cft_01HXXXXXXXXXXXXXXXXX",
  "expires_at": "2026-05-31T14:00:00Z",
  "snapshot_hash": "sha256:b8d5…",
  "_rules": { /* present when the mutation targets a component — see catalog/CLAUDE.md P5 */ }
}
```

To actually apply, call the same tool again, passing **only** the token plus whatever the tool needs to identify the resource:

```
content_publish_page({
  page_id: "<uuid>",
  confirm_token: "cft_01HXXXXXXXXXXXXXXXXX"
})
```

Do NOT pass `dry_run: true` AND `confirm_token` on the same call — the token consumption path wants `dry_run` absent (or `false`).

## Why a confirm_token

A `cft_…` is bound to **(client, action, resource, payload-hash)** at issue time. That means:

- You cannot use a token from `cli_X` against `cli_Y`'s identical-looking page (cross-tenant 403).
- You cannot use a deploy-preview token to delete a page (action 403).
- You cannot edit `blocks[]` between dry_run and confirm and still use the same token (snapshot-hash 403 — re-run dry_run after every edit).
- You cannot use the same token twice (409 — fresh dry_run required).
- A token sitting unused past its TTL fails with 410 — fresh dry_run.

This closes the silent-write window where the agent confirms a stale preview that no longer matches reality.

## Error mapping (`ConfirmTokenError`)

| HTTP | Code | Meaning | What to do |
|---|---|---|---|
| **410** | `expired` | Token sat past TTL (5 min for deploy, 7 days for tool-level) | Re-run dry_run; use the new token immediately |
| **409** | `consumed` | Token already redeemed | Re-run dry_run for the new mutation |
| **409** | `replayed` | Same token, same payload, second call within a few seconds | Idempotent guard — your mutation likely already landed. Read the resource to confirm |
| **403** | `client_mismatch` | PAT scoped to one tenant; token issued under another | Stop. Check [`../_shared/auth.md`](../_shared/auth.md) — you're in the wrong session |
| **403** | `action_mismatch` | Token was for "publish"; you called "delete" | Use the right tool, get a fresh token |
| **403** | `resource_mismatch` | Token's `page_id` ≠ the one you're confirming | Wrong resource — re-run dry_run on the right one |
| **403** | `snapshot_mismatch` | Resource changed between dry_run and confirm (something else edited it) | Re-run dry_run; surface the diff to the user |

## The wrapper script — use it

Don't write the two-phase flow by hand for production tenants. The shipped wrapper handles every envelope:

```bash
./scripts/dry-run-then-confirm.py \
  --url https://spideriq.ai/api/v1/dashboard/projects/$PID/content/deploy \
  --method POST \
  --description "Deploy demo.spideriq.ai to production" \
  --body '{}' \
  --auto
```

The `--auto` flag confirms immediately after dry_run if the diff is non-empty; omit it for human-in-the-loop review. The script's exit codes are documented in [`../../../scripts/README.md`](../../../scripts/README.md).

For MCP calls, the kitchen-sink dispatcher does the same — call the tool with `dry_run: true`, read the response, then call again with the returned `confirm_token`.

## The site-deploy two-step

`content_deploy_site` (and its split siblings `content_deploy_site_preview` / `content_deploy_site_production`) is the only gated mutation that's destructive *to end users*, not just to a row. Treat it accordingly.

The recommended shape:

```
# Stage 1 — preview the deploy. Returns a temporary preview URL on
# preview-XXX.sites.spideriq.ai so you can eyeball it before pushing.
content_deploy_site_preview()
# → { preview_url, confirm_token, expires_at, preview: {pages: 12, …}, snapshot_hash }

# Stage 2 — consume the token. Site goes live on the tenant's primary domain
# in ~2-5 seconds.
content_deploy_site_production({ confirm_token: "cft_…" })
# → { status: "live", version_id: 48 }
```

The legacy `content_deploy_site({ dry_run: true })` is kept for back-compat but routes through the same gate.

### Always run `content_deploy_readiness` first

Before any deploy:

```
content_deploy_readiness()
# → { ready: false, blocking: [...], warnings: [...] }
```

The readiness check returns a checklist of what's configured (settings, domain, templates, pages) and what's missing. **Deploy will reject if any `severity: 'error'` item is present.** Cheaper than failing mid-pipeline; surfaces "you forgot to verify the domain" before you spend a confirm_token.

## The five-lock tenant defense (the deeper why)

Every mutation goes through five independent tenant checks. Breaking one requires compromising a different layer. No silent cross-tenant writes. (Full breakdown: [catalog/CLAUDE.md → Multi-Tenant Safety](https://github.com/SpiderIQ/SpiderIQ/blob/master/docs/services/catalog/CLAUDE.md#multi-tenant-safety-phase-1112--five-lock-tenant-defense).)

```
Lock 1 — token.client_id == URL project_id     (auth dep)
Lock 2 — URL project_id resolves to a known client
Lock 3 — session binding (spideriq.json) matches URL
Lock 4 — confirm_token valid + unconsumed + matches (client, action, snapshot)
Lock 5 — resource row.client_id == URL project_id (WHERE client_id = $X in every SQL)
```

The `confirm_token` is Lock 4. The other four are always on, even for opt-in-gated tools. So even when you bypass the gate (`dry_run: false`), you still get 4 of the 5 locks. The gate exists for the "you confirmed the wrong thing" failure mode that the other four can't catch.

## The 10 gated endpoints (canonical list)

Lock 4 is enforced on these endpoints by default:

1. `DELETE /pages/{id}` — `content_delete_page`
2. `POST /pages/{id}/publish` — `content_publish_page`
3. `POST /pages/{id}/unpublish` — `content_unpublish_page`
4. `POST /pages/{id}/restore?version_number=N` — `content_restore_page_version`
5. `PATCH /settings` — `content_update_settings`
6. `POST /templates/apply-theme` — `template_apply_theme`
7. `DELETE /components/{id}` — `content_delete_component`
8. `POST /components/{id}/publish` — `content_publish_component`
9. `POST /components/{id}/archive` — `content_archive_component`
10. `POST /deploy` (legacy) and the split `POST /deploy/preview` + `POST /deploy/production`

Plus the booking-mutation siblings: `form_delete`, `form_publish`, `form_restore_version`, `booking_flow_delete`, `booking_flow_publish`.

## Verification — after every deploy

Don't trust a 200 from `content_deploy_site_production`. The deploy is a multi-step pipeline (template upload → KV write → CF Worker recreate); a 200 means "the request was accepted," not "every visitor sees the new bytes."

After every production deploy, run `content_visual_check`:

```
content_visual_check({
  page_url: "https://<tenant-domain>/<key-page>",
  viewport: "desktop"
})
```

For form-rendering pages, the assertion is on `dom.shadow_hosts.includes("spideriq-form")`, **NEVER** on `body_text_preview` — see [`booking-model.md → Visual-check`](booking-model.md#visual-check) and Rule 62. Without the visual check, silent-200 failures slip through (the W13-class incident the visual-check sidecar was built to catch).

## When dry_run is overkill

On `dev` or `staging` tenants where mistakes are cheap, the opt-in gate is genuinely opt-in — go ahead and write directly. Reserve the dry_run flow for:

- Production tenants (anything with a verified custom domain serving real users).
- Bulk operations where you're about to mutate ≥10 rows in a loop.
- Any operation initiated by an autonomous agent acting on a user request — the human deserves to see the diff.

On dev tenants, `content_create_page({ title: "test" })` immediately is fine. On `demo.spideriq.ai` or any client domain, opt in.

## See also

- [`../../../scripts/README.md`](../../../scripts/README.md) — the `dry-run-then-confirm.py` wrapper + exit codes
- [`../../../scripts/verify-tenant-scope.sh`](../../../scripts/verify-tenant-scope.sh) — Locks 1+3 pre-flight
- [`booking-model.md`](booking-model.md) — gated mutations on the booking surface
- [`../_shared/auth.md`](../_shared/auth.md) — which auth (X-Admin-Key vs PAT vs session) goes where
- [`tool-surface.md`](tool-surface.md) — full tool catalog with per-tool gate flavour
- [catalog/CLAUDE.md → Multi-Tenant Safety](https://github.com/SpiderIQ/SpiderIQ/blob/master/docs/services/catalog/CLAUDE.md#multi-tenant-safety-phase-1112--five-lock-tenant-defense) — canonical internal spec
