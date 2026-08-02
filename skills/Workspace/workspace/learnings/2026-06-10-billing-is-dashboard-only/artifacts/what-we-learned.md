# Billing is dashboard-only — read + redirect, never claim a write

## The lesson
There is **no client-PAT endpoint** for billing. Plan, usage, invoices, and
subscribe/change/cancel/resume are all served by `app/api/v1/dashboard_plans.py`,
which mounts at `prefix="/dashboard/plans"` and gates every route with
`require_tenant_member` — a **session** dependency, not the
`get_user_or_api_client` PAT dependency that `brands.py` uses.

So a `workspace` agent holding a PAT **cannot**:
- read its current plan / usage / invoices, or
- subscribe, upgrade, downgrade, cancel, or resume a subscription.

It **can** read the read-only `subscription` status that `getBrand` returns, and
it **must** redirect the user to the dashboard portal
(`https://app.spideriq.ai/dashboard/plans`) for anything that moves money. This
is the Stripe-Agent-Toolkit / WorkOS-Admin-Portal stance: sensitive/financial
changes happen in a hosted, human-confirmed flow — not by an autonomous token.

**Never tell the user you upgraded/cancelled their plan.** You can't, and the
claim is a trust-breaking hallucination.

## Explaining a spend denial
Limits are enforced by the **Dispatcher**, not by a billing API:
- 24h cost ceiling reached → **429** with `Retry-After` (resets midnight UTC) —
  waiting helps.
- monthly LLM spend cap reached → **402**, **no** `Retry-After` — a billing
  boundary; the user must raise the cap / upgrade in the portal.

When a sibling skill's job returns 429/402, translate it in these terms instead
of saying "the API is down."

## The gap (for the roadmap)
This is the billing half of workspace and it has no surface yet. `gaps.md`
RFCs four **read/redirect-only** PAT endpoints (B1 billing status, B2 usage, B3
invoices, B4 portal-link) for a client billing-VIEW follow-up — subscribe/cancel stay
human-in-the-loop. Until those land, the skill is read+redirect.

> Starting point, not ground truth — re-check `dashboard_plans.py` auth deps and
> the dispatcher plan before trusting specifics.
