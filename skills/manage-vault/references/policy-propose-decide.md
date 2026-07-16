# Key ToS-usage-policy — measure → propose → approve

The one flow that governs **which activities/consumers a gateway key may serve**.
It is deliberately two-step: an agent **proposes**, a human **approves**. There is
no one-step apply.

## The 6-activity domain

`allowed_activities` is a subset of exactly these (design §3.1):

| Activity | What it is |
|---|---|
| `scrape` | SpiderSite worker LLM extraction (the 163-worker hot path) |
| `worker_batch` | other batch worker LLM (maps-enrich, verify, …) |
| `live_agent` | agent chains (spideragent, campaign orchestration) |
| `interactive_cli` | the owner's own claude-code / opvsRunner (human-in-loop) |
| `embedding` | vector embeddings |
| `media` | image / video / speech generation |

A **NULL / omitted** array = **"any"** (no restriction, fail-open). The coarse
`usage_policy` rollup (`any` | `agents_only` | `workers_only`) is a display
convenience — on approve, a coarse `usage_policy` with no explicit array **backfills**
the array (`workers_only` → `[scrape, worker_batch]`, `agents_only` → `[live_agent]`).

## Steps

1. **Measure the blast radius.** Before restricting a key, read the DARK would-deny
   shadow log for it:
   `listWouldDeny(integration_id=<key>)` (or by `surface`/`provider_name`). Each row
   is a `(key × activity × consumer × reasons)` aggregate with a `would_deny_count`
   — how often that key's policy WOULD have denied real traffic if enforcement were
   armed. **A count > 0 for the activity you'd exclude is traffic you'd deny.**
2. **Propose.** `setKeyPolicy(integration_id=<key>, proposed_allowed_activities=[…],
   reason="…")` (or `proposed_usage_policy` / `proposed_allowed_consumers`). At least
   one proposed field is required. This files a **pending** proposal and changes
   **nothing** on the key. It is idempotent per key — a re-file while one is pending
   returns the existing proposal (`created=false`).
3. **A human reviews.** `listPolicyProposals(status="pending")` shows each proposal's
   **current vs proposed** policy, `reason`, and `proposed_by`.
4. **A human decides.** `decidePolicyProposal(proposal_id=<id>, decision="approve")`
   writes the proposed policy onto the key and marks it `applied`; `decision="reject"`
   discards it (key unchanged). 409 if the proposal isn't pending.

## Gotchas

- **`setKeyPolicy` applies nothing.** It is the terminal action for an automated
  caller. Do not report the policy as changed — report that a proposal was filed.
- **`updateKey` cannot set policy.** The policy fields exist only on `setKeyPolicy`.
  There is exactly one audited door.
- **Approve can 409, not overwrite.** If the proposal was already approved/rejected,
  approving again 409s — re-list to see its current status.
- **Backfill surprise.** Proposing `usage_policy="workers_only"` with no
  `proposed_allowed_activities` results, on approve, in `allowed_activities =
  [scrape, worker_batch]`. If you want a different set, pass the array explicitly.
- **Consumer-locking is strict.** A non-NULL `allowed_consumers` denies any request
  with no consumer identity (e.g. shared-pool traffic) — check `listWouldDeny`
  `surface=path_b` before consumer-locking a pooled key.

## Verify

- After `setKeyPolicy`: `listPolicyProposals(status="pending")` shows your proposal
  with the right `proposed_*` and `current_*` snapshot.
- After `decidePolicyProposal(approve)`: the proposal is `applied`
  (`listPolicyProposals(status="applied")`), and a follow-up `listWouldDeny` reflects
  the new policy's effect on subsequent traffic.

## WRONG → RIGHT

- **WRONG:** call `setKeyPolicy(...)` and tell the user "the key is now restricted to
  workers." → **RIGHT:** "I filed a proposal to restrict key #N to `[scrape,
  worker_batch]`; it needs a human to `approve` it. would-deny shows 0 denied for
  those activities, so it's safe."
- **WRONG:** restrict a key to `[live_agent]` because it *looks* like an agent key. →
  **RIGHT:** `listWouldDeny(integration_id=N)` first — if `scrape` has a
  `would_deny_count` in the thousands, that restriction would starve the scrape pool.
- **WRONG:** try `updateKey(key_id=N, allowed_activities=[…])`. → **RIGHT:** policy
  goes through `setKeyPolicy` → `decidePolicyProposal(approve)`; `updateKey` rejects
  unknown fields.
