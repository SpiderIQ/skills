# Reference — Billing (read + redirect, NOT PAT-writable)

**The one thing to get right:** there is **no PAT/CLI/MCP endpoint that changes a
subscription, payment method, or invoice.** Every billing mutation lives behind
**session-auth** dashboard endpoints (`/api/v1/dashboard/plans/*`,
`require_tenant_member` — see [gaps.md](gaps.md)). The agent's job is **read the
state, then redirect to the portal.** This matches how Stripe's own agent toolkit
and WorkOS Admin Portal are designed — money-moving / sensitive config is done in
a hosted UI, not by an autonomous token ([competitors.md](competitors.md)).

## What the agent SHOULD do

1. **Read** what it legitimately can: `getBrand` returns a read-only
   `subscription` status signal; `getBrand`/`listBrands` give the plan-bearing
   brand.
2. **Redirect** for anything that changes money:
   > "Subscriptions, invoices and payment methods are managed in your dashboard's
   > billing portal: **https://app.spideriq.ai/dashboard/plans** — open it and I
   > can walk you through the options."
3. **Never** claim you subscribed/upgraded/cancelled. You can't, and saying so is
   a trust-breaking hallucination.

## What actually exists (dashboard-only, session auth — for context)

These are **not** callable with a PAT; listed so you can describe what the portal
does. Source: `app/api/v1/dashboard_plans.py` (`prefix="/dashboard/plans"`,
`require_tenant_member`).

| Portal capability | Dashboard endpoint (session-only) |
|---|---|
| Current plan + monthly usage bars | `GET /dashboard/plans/me` |
| Browse available tariffs / bundles | `GET /dashboard/plans/browse[/bundles]` |
| Invoices (last 20, Stripe) | `GET /dashboard/plans/invoices` |
| Open Stripe customer portal (payment method, invoices) | `POST /dashboard/plans/billing-portal` |
| Subscribe / change / cancel / resume | `POST /dashboard/plans/{subscribe,change,cancel,resume}` |
| Recent quota denials (support) | `GET /dashboard/plans/recent-denies` |

## How metering & limits actually work (so you can explain a denial)

SpiderIQ does **not** bill per-call in real time. The **Dispatcher** enforces
ceilings at job/LLM submission
(`docs/services/fastapi/dispatcher/dispatcher_master_plan.md`):

- `unified_24h = job_cost_24h + llm_spend`. When it reaches
  **`cost_ceiling_usd_per_24h`** → **HTTP 429** with `Retry-After` (seconds until
  the 24h window rolls at midnight UTC). Waiting helps.
- When LLM spend reaches **`monthly_spend_cap_usd`** → **HTTP 402 Payment
  Required**, **no `Retry-After`** — it's a billing-period boundary, so waiting
  the day out won't help; the user must raise the cap / upgrade in the portal.
- Tariffs are seeded per `service_type` (e.g. SpiderSite $29/$149/$599;
  SpiderGate is `monthly_spend_cap_usd`-based). Quotas read at check-time from
  `tariff_quotas`.

So when a sibling skill's job fails with **429**, tell the user "you've hit your
24h cost ceiling, it resets at midnight UTC (Retry-After: N s)"; on **402**, "your
monthly spend cap is reached — raise it or upgrade in the dashboard."

## WRONG → RIGHT

**WRONG**
> "Done — I've upgraded you to the $149 plan."  *(no PAT endpoint can do this)*

**RIGHT**
> "I can't change the plan directly — billing is managed in the portal. Open
> **app.spideriq.ai/dashboard/plans**, pick the $149 tier, and confirm there.
> Your current plan shows as `active` on brand Acme (id 42)."

## Verify

- You only ever **read** billing signal here; there is nothing to verify-after-write.
- If asked to "show my invoices/usage" programmatically: there is no PAT route —
  point to the portal and log the gap (it's the top RFC in [gaps.md](gaps.md)).
