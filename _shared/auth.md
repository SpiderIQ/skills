# _shared/auth

Shared across `spiderpublish`, `spidermail`, and `spidergate`. The PAT auth pattern, the "which auth do I use?" decision tree, the five-lock tenant defense, the brand-admin-email lookup (v0.7.8 fix), and the 600s token TTL.

## TL;DR

- **One auth header for tenant-scoped agentic calls:** `Authorization: Bearer cli_<id>:<api_key>:<api_secret>` (a PAT — Personal Access Token).
- **PATs are stored at `~/.spideriq/credentials.json`** after `spideriq auth request -e <admin-email>` → the email recipient clicks the approval link → `spideriq auth check`. From then on, every CLI / MCP tool reads it automatically.
- **`spideriq.json` at the repo root** declares which tenant the session is scoped to. Walks UP from cwd. Required for all `/dashboard/projects/{project_id}/...` calls (Lock 3).
- **Verify before mutating.** Run `./scripts/verify-tenant-scope.sh` and paste its output. Exit 0 → safe. Exit non-zero → stop.

## The decision tree: which auth do I use?

Pick by **where the operation runs**, not by what it does.

| Where? | Auth | Example |
|---|---|---|
| **Inside the api-gateway container** (or sidecars sharing its lifespan) | None — direct service call | `docker exec spideriq-api-gateway python -m scripts.redeploy_tier3_tenants` — calls Python services directly, no HTTP, no token. |
| **External admin script / one-shot ops from a host shell** | `X-Admin-Key: $ADMIN_API_KEY` header | `curl -H "X-Admin-Key: $ADMIN_API_KEY" https://spideriq.ai/api/v1/admin/...` — for super-admin endpoints (`/admin/*`). Load from `/root/SpiderIQ/app/.env` line ~75. |
| **External client / MCP / SDK (per-tenant agentic op)** | `Authorization: Bearer cli_<id>:<api_key>:<api_secret>` | Every `/dashboard/projects/{pid}/content/*` call. What `@spideriq/cli` and `@spideriq/mcp` do for you. |
| **Browser dashboard (human session)** | Better Auth session cookie (`better-auth.session_token`) | `apps/web/` mutations via `app/middleware/dashboard_auth.py` — adds `super_admin` / `brand_admin` / `client_user` role gates. Only your browser holds this. |

For SpiderPublish recipes the answer is almost always **row 3 (PAT)**. The other rows exist for ops + admin scripts + the dashboard, and you can mostly ignore them when authoring content.

## Getting a PAT (one-time, per workspace)

`@spideriq/cli` and `@spideriq/mcp` ship an AI-native PAT flow. No magic links to paste, no copy-the-secret-from-a-webpage:

```bash
# 1. Request access. SpiderPublish emails the brand admin a one-click approval link.
spideriq auth request \
  --email admin@<tenant-domain>.com \
  --project "Acme demo site"

# 2. Brand admin clicks "Approve" in the email. PAT is provisioned server-side.

# 3. Your CLI session polls the server-side state and writes the credential to
#    ~/.spideriq/credentials.json automatically.
spideriq auth check

# 4. Confirm.
spideriq auth whoami
# → { client_id: "cli_...", brand_name: "...", role: "..." }
```

`spideriq auth check` runs as a poll loop (default 60s timeout); call it repeatedly if the admin hasn't clicked yet. The MCP equivalent is `request_access` + `check_access_status`. Both write to the same `~/.spideriq/credentials.json`.

### The brand-admin-email lookup (v0.7.8 fix)

`--email` must be a real brand-admin email — the server checks `users.role IN ('super_admin', 'brand_admin')` AND the email belongs to a user whose `brand_id` matches the requested project's brand. If you don't know the brand admin email:

- Ask the tenant owner (often the same person you're working with).
- Or `gh issue create` / Slack the SpiderIQ team and ask.

**Don't guess.** Before v0.7.8 the server returned a generic 404 on unknown emails — agents would loop forever calling `check_access_status`. The 0.7.8 fix returns a structured envelope (`{error: "no_brand_admin", suggested_action: "..."}`) but you should never hit it if you're sourcing the email from the user.

### Token TTL — 600s (10 min) for the approval link

The approval link in the email is single-use and expires 10 minutes after generation. The PAT itself (once provisioned) has no expiry by default — it lives in `~/.spideriq/credentials.json` until you `spideriq auth logout` or rotate it. If `auth check` 410s, restart from `auth request`.

## `spideriq.json` — session binding (Lock 3)

After you've got a PAT covering multiple projects, **bind your shell session to ONE** with:

```bash
spideriq use cli_ov5fdhwseewjf4y9
```

This writes `spideriq.json` to the current directory (vercel-style):

```json
{
  "project_id": "cli_ov5fdhwseewjf4y9",
  "project_name": "Acme demo site",
  "api_url": "https://spideriq.ai",
  "created_at": "2026-04-14T12:34:56.000Z"
}
```

`@spideriq/core` / `@spideriq/mcp` walk UP from cwd looking for the file on every call. The walk-up means you can have one PAT covering 10 projects and `spideriq.json` in each project's dir — each session is scoped to its dir. **Commit `spideriq.json` to the project repo** so any agent that clones into the dir is auto-scoped.

If you're in a dir without `spideriq.json`, every dashboard call resolves the project via the legacy header-based path (X-Brand-ID / X-Selected-Client-Id). That path is deprecated (`Deprecation` + `Sunset` headers on responses) — the project-scoped URL `/dashboard/projects/{project_id}/...` is the future. Use `spideriq use` to set it.

## The five-lock tenant defense

Every dashboard mutation flows through five independent tenant checks. These are server-side enforcement; you can't bypass them client-side. Knowing they exist:

```
Lock 1 — token.client_id == URL project_id     (auth dep)
Lock 2 — URL project_id resolves to a known client
Lock 3 — session binding (spideriq.json) matches URL
Lock 4 — confirm_token valid + unconsumed + matches (client, action, snapshot)
Lock 5 — resource row.client_id == URL project_id (every SQL WHERE clause)
```

Lock 1 is the PAT scope check — your `cli_X:key:secret` only works for `cli_X`. Lock 2 ensures the URL `project_id` isn't a typo. Lock 3 ensures your `spideriq.json` agrees with the URL (catches the cross-session footgun where you `cd` into another project's dir but forget to `spideriq use`). Lock 4 is the dry_run/confirm_token gate — see [`../spiderpublish/reference/deploy-protocol.md`](../spiderpublish/reference/deploy-protocol.md). Lock 5 is the deep server-side check that the row you're mutating actually belongs to your tenant.

**Why five locks instead of one:** any one of them can fail open (typo in code, missing middleware, expired token, race condition). All five failing open simultaneously requires an active attack across multiple layers. The cost is recipe complexity; the benefit is no silent cross-tenant writes.

Full breakdown: catalog/CLAUDE.md → "Multi-Tenant Safety (Phase 11+12 — Five-Lock Tenant Defense)".

## Pre-flight script — paste output before mutating

Don't reason about whether your auth is right; verify with the script:

```bash
./scripts/verify-tenant-scope.sh
# {"ok":true,"project_id":"cli_xxx","spideriq_json":"/path/spideriq.json","verified_at":"2026-05-24T..."}
```

Exit codes (documented in [`../spiderpublish/scripts/README.md`](../scripts/README.md)):

| Exit | Meaning | What to do |
|---|---|---|
| 0 | spideriq.json + PAT + auth/me all agree on the same client_id | Safe to mutate |
| 1 | spideriq.json client_id ≠ PAT client_id (MISMATCH) | Stop. Either `spideriq use <correct-project>` or re-auth into the right tenant |
| 2 | No spideriq.json found by walk-up | `spideriq use <project_id>` first |
| 3 | No PAT in credentials.json | `spideriq auth request` first |

The script is the canonical pre-mutation gate. The whole `<HARD-GATE name="tenant-scope">` block in SKILL.md is just "run this script + paste the output." Compliance is auditable.

## Permissions model (roles)

Inside your tenant, the PAT inherits the role of the user who provisioned it:

| Role | Can do |
|---|---|
| `super_admin` | Everything across all tenants. Reserved for SpiderIQ-internal ops; almost never the right role for a tenant PAT. |
| `brand_admin` | Everything within their brand: settings, billing, members, every tenant in the brand. The default role for tenant owners. |
| `client_user` | Most authoring ops — pages, posts, components, navigation, forms. Cannot change settings, add domains, add brand members, or `force=true` an unlock they don't own. |

If a tool returns 403, check `whoami`. If your role isn't sufficient, the user has to provision a new PAT under a higher-role user.

## Workspaces (multi-tenant from one PAT)

`@spideriq/cli` and `@spideriq/mcp` support multiple "workspaces" — each is a `{api_url, client_id, api_key, api_secret}` tuple stored in `~/.spideriq/credentials.json`. The `workspace` parameter on every tool defaults to `"default"`:

```
content_create_page({ title: "...", workspace: "staging" })
```

Most agents only need the default workspace. Use named workspaces when you're authoring across two tenants in one session (uncommon — usually safer to open two terminals with different cwds + different `spideriq.json` files).

## Anti-patterns

1. **Hard-coding `cli_id:api_key:api_secret` in scripts.** They're per-developer credentials, not service accounts. If a CI job needs to call SpiderPublish, ask SpiderIQ for a service-account PAT scoped to one tenant.
2. **Sharing a `spideriq.json` between unrelated repos.** Each project gets its own `spideriq.json`. If you `cd` between repos, the walk-up resolves the nearest one — easy to mis-target if the nearest one isn't your intended tenant. ALWAYS verify with the script.
3. **Bypassing the verify script "to save time."** It costs 200ms and 200 tokens. The Hyperframes commit `190f1ec` proved that prose-only "remember to check scope" rules get skipped under ship pressure. The script makes it auditable.
4. **Using the `X-Admin-Key` for tenant-scoped ops.** It's super-admin only; tenant data writes through it lose the per-tenant audit trail. PAT first, X-Admin-Key only for `/admin/*`.
5. **Mixing CLI + MCP in the same session without flushing.** Both read the same `~/.spideriq/credentials.json` and walk-up `spideriq.json`. Re-run `./scripts/verify-tenant-scope.sh` after every `spideriq use` or `spideriq auth request`.
6. **Putting credentials in `spideriq.json`.** The file is non-sensitive (it's a project_id + URL — commit it). Credentials live in `~/.spideriq/credentials.json` (NOT committed; in `.gitignore`).

## See also

- [`../spiderpublish/reference/deploy-protocol.md`](../spiderpublish/reference/deploy-protocol.md) — Lock 4 (dry_run/confirm_token)
- [`../spiderpublish/reference/tool-surface.md`](../spiderpublish/reference/tool-surface.md) — MCP package picker + workspace param
- [`../spiderpublish/scripts/README.md`](../scripts/README.md) — `verify-tenant-scope.sh` + the "scripts not prose" rationale
- catalog/CLAUDE.md → "Multi-Tenant Safety" — internal canonical spec
- fastapi/CLAUDE.md → "Authentication" — full per-auth-mode reference
