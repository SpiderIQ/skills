# Competitor patterns — Clerk · WorkOS · Stripe (what "great" looks like)

Studied 2026-06-10 to set the bar for workspace. Three lessons shaped the
skill: role-gated mutations, hosted-UI redirect for sensitive ops, and
read-first/write-narrow for billing.

## Clerk — Organizations (the closest analogue to our brands)

- Two default roles: **`org:admin`** (full management of the org + memberships)
  and **`org:member`** (read-only by default — limited to "Read members" and
  "Read billing"). Only admins invite or change roles. Invitations sit **pending**
  until accepted or revoked.
- **What we adopted:** our `owner`/`brand_admin` ↔ `org:admin`, `client_user` ↔
  `org:member`. The `<HARD-GATE>` "check membership_role before mutate" is the
  Clerk model — a member who tries to mutate is denied, so read the role first.
  The send-vs-accept split (invite is pending until the invitee acts) is identical
  to ours.
- Source: [Clerk — Roles & permissions](https://clerk.com/docs/guides/organizations/control-access/roles-and-permissions),
  [Clerk — Manage invitations](https://clerk.com/docs/guides/organizations/add-members/invitations).

## WorkOS — Organizations + Admin Portal

- The **Admin Portal** is a WorkOS-hosted UI you link the customer to for
  privileged setup (SSO, directory, domain verification). Roles are reassignable
  via API; invitations are programmatic OR dashboard.
- **What we adopted:** the "redirect to a hosted portal for sensitive config"
  pattern is exactly our billing answer — the agent hands the user the dashboard
  portal link rather than performing the privileged change itself
  ([billing.md](billing.md)). Day-to-day membership/invitation management stays on
  the API (our `members`/`invitations` methods); the high-blast-radius stuff is a
  redirect.
- Source: [WorkOS — Admin Portal](https://workos.com/docs/admin-portal),
  [WorkOS — Invitations](https://workos.com/docs/authkit/invitations).

## Stripe — Agent Toolkit / MCP (billing)

- 27 tools split into **Read / Write / Financial / Destructive**; **start
  read-only**, add narrow write scopes only once trusted. Scopes are **enforced
  server-side** (a read-only key can't refund even if the model tries). Billing is
  driven through **billing-portal sessions** (create a session → user manages
  payment method/invoices there).
- **What we adopted:** billing in workspace is **read + redirect** — no
  write methods at all (`schema.yaml` has zero billing methods by design), and the
  RFC'd future endpoints ([gaps.md](gaps.md) B1–B4) are read/portal-link only.
  Subscribe/change/cancel stay human-in-the-loop, exactly like Stripe keeps
  money-moving behind explicit, scoped, often-hosted flows.
- Source: [Stripe — MCP](https://docs.stripe.com/mcp),
  [stripe/ai agent toolkit](https://github.com/stripe/ai).

## Net design stance

| Dimension | Their pattern | Ours |
|---|---|---|
| Roles | admin vs member, admin-only writes | owner/brand_admin vs client_user, owner/admin-only writes |
| Invites | send → pending → accept (by invitee) | identical; PAT sends, session accepts |
| Sensitive/billing | hosted portal redirect; read-first | read `subscription` signal + redirect to `/dashboard/plans` |
| Safety | server-enforced scopes | server-enforced brand-access + role checks (403/429/402) |
