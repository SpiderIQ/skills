# Gaps — what workspace needs that the CLI/MCP/PAT surface lacks

> **Primary deliverable (Session 1.7, task `b57c0ac2`).** Every claim below
> carries grep/curl provenance. Two classes of gap: **(A) BILLING — no client-PAT
> surface at all** (the billing-VIEW half of the skill has nothing to call yet —
> a follow-up; note the *super-admin* billing surface is a separate secret skill,
> board task `3.2 superadmin-billing`, and is NOT this client skill), and
> **(B) MCP/CLI coverage** of endpoints that DO exist on PAT but aren't wrapped as
> tools. The skill ships covering brands/members/invites/settings/integrations
> today; billing is documented as VIEW + redirect ([billing.md](billing.md)).

## A. BILLING — zero client-callable (PAT) endpoints — **the big gap**

Every billing capability is behind **session-auth** dashboard routes; **none** is
reachable with a client PAT.

- Evidence: `app/api/v1/dashboard_plans.py` → `router = APIRouter(prefix="/dashboard/plans")`
  and `from middleware.dashboard_auth import ... require_tenant_member`; all 11
  routes use `require_tenant_member` (session), not the PAT dependency
  (`get_user_or_api_client`) that `brands.py` uses.
- Consequence: an agent with a PAT **cannot** read its plan/usage/invoices or
  subscribe/upgrade/cancel. The skill can only **read the `subscription` signal on
  `getBrand`** and **redirect to the portal**.

### RFCs to close it (client billing-VIEW follow-up — new read/redirect PAT endpoints + MCP tools)

| # | Proposed PAT endpoint | Returns | Maps to existing session route |
|---|---|---|---|
| B1 | `GET /api/v1/brands/{id}/billing` | current plan, period-end, `cost_ceiling_usd_per_24h`, `monthly_spend_cap_usd`, status | `GET /dashboard/plans/me` |
| B2 | `GET /api/v1/brands/{id}/usage` | rolling 24h/30d cost + quota consumption per service_type | (dispatcher counters; no route today) |
| B3 | `GET /api/v1/brands/{id}/invoices` | paginated Stripe invoices | `GET /dashboard/plans/invoices` |
| B4 | `POST /api/v1/brands/{id}/billing-portal` | short-lived Stripe portal URL (so the agent can hand the user a deep link) | `POST /dashboard/plans/billing-portal` |

B1–B4 are **read/redirect only** by design — subscribe/change/cancel stay
human-in-the-loop in the portal (the Stripe-toolkit / WorkOS-Admin-Portal model,
[competitors.md](competitors.md)). They need: the routes added to `brands.py` (or
a new `app/api/v1/billing.py`) under `get_user_or_api_client` + brand-access
check, then `billing.ts` MCP tools + `client.ts` methods + CLI commands.

## B. MCP / CLI coverage gaps (endpoint EXISTS on PAT, no tool/command)

The `@spideriq/mcp-admin` `brands.ts` exposes 16 tools but the served PAT surface
in `brands.py` is larger. The skill's `client/schema.yaml` documents the full
PAT surface; these are the items with **no MCP tool** yet (and **no CLI command
at all** — there is no `packages/cli/src/commands/brands.ts`):

| Capability | Served PAT endpoint (exists) | In `brands.ts` MCP? | CLI? |
|---|---|---|---|
| Create a brand | `POST /brands` (`brands.py:161`) | ❌ | ❌ |
| Brand business profile (get/update) | `GET/PATCH /brands/{id}/information` (`:450`/`:473`) | ❌ | ❌ |
| Brand logo (upload/delete) | `POST/DELETE /brands/{id}/logo` (`:326`/`:399`) | ❌ | ❌ |
| Change a member's role/status | `PATCH /brands/{id}/members/{member_user_id}` (`:542`) | ❌ | ❌ |
| Resend an invitation | `POST /brands/{id}/invitations/{id}/resend` (`:763`) | ❌ | ❌ |
| "Invites waiting for me" | `GET /brands/invitations/pending` (`:936`) | ❌ | ❌ |

These are **not phantom tools** — they're real served endpoints (line-cited
above) that the skill teaches via raw HTTP/`schema.yaml`, but they should be
wrapped as MCP tools (`packages/mcp-tools/src/admin/brands.ts`) + a new
`packages/cli/src/commands/brands.ts` so non-HTTP agents get them too.

### Recommended MCP additions to `brands.ts` (coverage follow-up)

`create_brand`, `update_brand_information` / `get_brand_information`,
`upload_brand_logo` / `delete_brand_logo`, `update_brand_member` (role change),
`resend_brand_invitation`, `get_pending_invitations`.

## C. Acceptance asymmetry (by design, document don't "fix")

`POST /brands/invitations/accept` is **session-only** (`brands.py:862`,
`get_session_user`). A PAT can send but not accept. This is correct (acceptance
must be the invitee's own authenticated act) — the skill documents it
([manage-team.md](manage-team.md)); no RFC.

---

**Provenance:** surface mapped 2026-06-10 against `app/api/v1/brands.py`,
`app/api/v1/dashboard_plans.py`, `packages/mcp-tools/src/admin/brands.ts`,
`packages/core/src/client.ts`, and
`docs/services/fastapi/dispatcher/dispatcher_master_plan.md`. Filed on board
`skill-suite-build` task b57c0ac2 as a comment; client billing-VIEW (class A) is a
follow-up — distinct from the secret super-admin billing skill (task 3.2).
