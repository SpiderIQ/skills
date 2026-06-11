---
name: workspace
description: >
  Administer YOUR OWN SpiderIQ workspace as a client (a brand_admin). Use when the
  user wants to manage their account/organization/workspace, team or seats: list
  the brands they belong to, add or remove teammates, send/resend/cancel
  invitations, change a member's role (brand_admin vs client_user), rename a brand,
  edit brand profile/settings/business-info/logo, manage per-brand API-key
  integrations (OpenRouter/Mistral provider keys), or VIEW their plan, subscription
  and usage. Verbs: invite, add/remove member, change role, promote, off-board,
  rename workspace, update settings, set logo, connect API key, add provider key,
  see my plan, check usage, view billing, upgrade. Client SELF-SERVICE only — it
  never leaves the brands the caller belongs to and has no cross-tenant or platform
  powers (those are separate super-admin skills).
version: "0.1.0"
category: admin
requires_auth: true
requires_brand: false
---

# workspace

The client's own **workspace control panel** — brands, team, invitations,
settings, per-brand API-key integrations, and a read-and-redirect view of
billing. Mirrors the dashboard's WORKSPACE tile; modeled on Clerk/WorkOS
organization management and the Stripe Customer Portal, scoped to the brands the
caller's PAT belongs to.

```
listBrands ─┬─► getBrand / settings / information / logo      (the workspace)
            ├─► members:  list → update-role → remove           (the team)
            ├─► invitations: send → resend → cancel             (growing the team)
            ├─► integrations: list → create → test → delete     (provider API keys)
            └─► billing:  VIEW plan/usage  ──►  dashboard portal (managed there, not by PAT)
```

## Scope (read this first)

This skill is **client self-service** for a `brand_admin`. Every call uses the
caller's own PAT and touches **only brands the caller is a member of**. It has
**no** cross-tenant, fleet, or platform surface.

| You want to… | Use |
|---|---|
| Manage **my own** workspace (this skill) | `workspace` |
| Manage **all tenants** / platform / founder ops (super-admin) | the secret super-admin skills (`X-Admin-Key`) |
| Manage **my own identity** (profile, OAuth, sessions, switch brand) | `@spideriq/admin-skills` → `auth` |

<HARD-GATE name="role-and-id-before-mutate">
Before ANY mutating call (update/remove/invite/cancel/role-change/integration),
you MUST: (1) have the INTEGER `brand_id` from `listBrands` — it is NOT the
`cli_` public client id, and the wrong one 404s or hits the wrong brand; and
(2) know the caller's `membership_role` for that brand. **Only `owner`/`brand_admin`
may mutate.** A `client_user` is read-only and every write returns 403 — check the
role and tell the user plainly rather than firing a call that will be denied.
</HARD-GATE>

## Rules (Non-Negotiable)

**ROLE-GATED WRITES:** every mutation requires `owner`/`brand_admin`. Read the
caller's `membership_role` (from `listBrands`) first — silently firing a write as
a `client_user` returns 403 and confuses the user about why "nothing happened".

**INTEGER brand_id:** `brand_id` is the integer id from `listBrands`, never the
`cli_…` public id. Wrong id → wrong brand or 404. Always resolve it first.

**BILLING IS VIEW + REDIRECT:** there is **no PAT endpoint that changes a
subscription, payment method, or invoice**. NEVER tell the user you subscribed,
upgraded, or cancelled their plan — you can't. Surface the current plan/usage as
read-only signal and hand them the dashboard portal link. See
[references/billing.md](references/billing.md).

**INVITES SEND ≠ ACCEPT:** a PAT can send/resend/cancel an invitation, but
acceptance happens only in a **logged-in session** (the invitee). Never promise
to auto-accept on someone else's behalf.

**API KEYS ARE SECRETS:** when adding a provider integration, treat `api_key` as
a secret — never echo it back, and confirm with `testIntegration` after create.

## Decision tree — pick a reference

| The user wants to… | Read |
|---|---|
| Rename a brand, edit settings/profile/logo | [references/manage-brands.md](references/manage-brands.md) |
| Invite/remove teammates, change roles, manage invitations | [references/manage-team.md](references/manage-team.md) |
| Add/test/remove a provider API key (OpenRouter, Mistral…) | [references/manage-integrations.md](references/manage-integrations.md) |
| VIEW the plan/usage, or "upgrade/cancel my subscription" | [references/billing.md](references/billing.md) |
| Know what this skill CANNOT do yet (missing CLI/MCP/PAT tools) | [references/gaps.md](references/gaps.md) |
| Understand how this compares to Clerk/WorkOS/Stripe | [references/competitors.md](references/competitors.md) |

## Method map (client/schema.yaml)

- **Brands:** `listBrands` · `createBrand` · `getBrand` · `updateBrand`
- **Settings/profile:** `getBrandSettings` · `updateBrandSettings` · `getBrandInformation` · `updateBrandInformation` · `uploadBrandLogo` · `deleteBrandLogo`
- **Members:** `listBrandMembers` · `updateBrandMember` · `removeBrandMember`
- **Invitations:** `listBrandInvitations` · `sendBrandInvitation` · `resendBrandInvitation` · `cancelBrandInvitation` · `getPendingInvitations`
- **Integrations:** `listIntegrations` · `createIntegration` · `testIntegration` · `deleteIntegration`
- **Billing:** *(none — VIEW + redirect; see references/billing.md)*

Auth: `Authorization: Bearer <client_id:api_key:api_secret>` (PAT in `OPVS_PAT`).
All on `https://spideriq.ai/api/v1`. Add `?format=yaml` for token-efficient reads.

## See also
- **Sibling packages:** `@spideriq/admin-skills` (`auth` for identity; `integrations` for the richer provider/spend surface; `opvs-admin`/super-admin for platform ops).
- **learnings/** — institutional memory (the `membership_role` drop incident, the billing-is-dashboard-only gap). Treat as starting points; verify against current code.
- Consolidates the former `manage-brands` skill from `@spideriq/publish-skills`.
