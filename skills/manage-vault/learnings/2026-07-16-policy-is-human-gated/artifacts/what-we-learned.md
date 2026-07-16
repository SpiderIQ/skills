# A key's usage policy is human-gated — an agent proposes, a human approves

## What happened

VAULT.1 5.3 shipped the agent surface for SpiderGate **key ToS-usage-policy**
management. The load-bearing design choice: an agent can **never** self-apply a
policy to a key. `setKeyPolicy` files a *pending proposal*; a human super_admin (or
`X-Admin-Key` holder) applies it with `decidePolicyProposal(approve)`.

## Why it's built this way

`allowed_activities` / `allowed_consumers` are **filters on key selection** in the
gateway's `get_next_available_key`. A restriction narrows which keys can serve an
activity. An over-broad one — e.g. locking a widely-used key to `[live_agent]` —
can empty a provider's usable pool for `scrape` / `worker_batch` and **starve the
163-worker hot path** (design §13 S3: fleet starvation on over-denial, the
would-deny cascade). A worker batch would 503; a live agent would fail
mid-conversation. That blast radius is why the change is human-gated.

So the surface splits the job:

- **Measure** — `listWouldDeny` is a DARK shadow log (nothing is blocked yet) that
  counts how often each key's policy WOULD have denied real traffic if enforcement
  were armed. It is the agent's blast-radius estimate.
- **Recommend** — `setKeyPolicy` files a proposal (idempotent per key). It writes
  nothing to the key.
- **Decide** — a human `decidePolicyProposal(approve|reject)`. Approve is the only
  apply path; it backfills `allowed_activities` from a coarse `usage_policy` exactly
  like the direct `update_key` PATCH does.

`updateKey` deliberately **omits** the policy fields, so there is exactly one
audited door for policy. The decrypted account password has **no tool at all** — a
super-admin-only reveal endpoint (design §5.4 D2).

## The rule

Policy changes are propose→approve, mirroring the routing self-heal Tier-2 split
(`gate_routing_proposals`) and the `[[agent-proposes-human-approves-gate]]` owner
lock: the approve dependency is `require_super_admin_or_admin_key` (no PAT branch),
the gate lives in the dependency (not the handler body), and there is no
approve-without-human tool. An automated caller's terminal action is
`setKeyPolicy` — file the proposal, surface it, stop.

## Verify against current code

- `app/api/v1/admin_gate/key_policy_proposals.py` — propose (`gate:vault:policy` PAT
  or X-Admin-Key) + approve/reject (`require_admin_or_session`, no PAT).
- `app/database/migrations/444_gate_key_policy_proposals.sql` — the store.
- `app/services/gate/usage_policy.py` — the 6-activity domain + the DARK shadow log.
- `app/core/admin_scopes.py` — `gate:vault:policy` (read+propose only).
