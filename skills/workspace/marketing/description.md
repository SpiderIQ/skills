# workspace

A client's self-service control panel for **their own** SpiderIQ workspace —
the brands they belong to, the team on each (members, roles, invitations), and
brand settings/profile/logo. Modeled on Clerk/WorkOS organization management:
admin-gated mutations, send-then-accept invitations, and billing handled as
read-and-redirect to the dashboard portal (the Stripe-toolkit stance — no
autonomous subscription changes).

Scoped strictly to the caller's PAT — it never touches another tenant. For
cross-tenant/fleet operations use `opvs-admin`; for the signed-in person's own
identity use `auth`; for third-party API keys use `integrations`.
