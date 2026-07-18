---
name: manage-vault
version: 0.1.0
description: >
  Manage SpiderGate's provider API-KEY vault — edit a key's non-policy config,
  refresh its billing snapshot, reset its health, and run the ToS-usage-POLICY
  PROPOSE→DECIDE flow (which activities/consumers a key may serve). Trigger on:
  "restrict a gateway key to worker traffic", "set / change a key's usage policy",
  "propose a key policy change", "approve / reject a key-policy proposal", "which
  keys would be denied under enforcement", "review the would-deny shadow log",
  "does this provider have a billing API", "reset a gateway key's health", "sync a
  key's balance". This is the ADMIN key-vault surface (super_admin, X-Admin-Key) —
  it changes which activities a key serves for EVERY tenant. It is NOT how you
  change the alias→model ROUTING (that's manage-routing) and NOT how you send a
  completion (that's use-the-gateway). A key's usage policy is HUMAN-GATED: an
  agent PROPOSES, a human APPROVES — there is no self-apply.
client: manage-vault
client_version: "0.1.0"
category: admin
triggers:
  - manage gate keys
  - restrict a key to workers
  - set a key usage policy
  - propose a key policy change
  - approve a key policy proposal
  - reject a key policy proposal
  - which keys would be denied
  - review the would-deny shadow log
  - does this provider have a billing api
  - reset a key's health
requires_auth: true
requires_brand: false
---

# Manage SpiderGate Key Vault (keys + ToS-usage-policy propose/decide)

SpiderGate selects a provider **API key** for every gateway request from the
`api_integrations` vault. Each key can carry a **ToS usage policy** — which
**activities** (`scrape`, `worker_batch`, `live_agent`, `interactive_cli`,
`embedding`, `media`) and which named **consumers** it is allowed to serve — so a
key whose provider's terms forbid, say, agent traffic never gets picked for it.
This skill is the privileged surface that edits a key's config, refreshes its
billing, resets its health, reviews the **would-deny shadow log**, and runs the
**policy propose→decide** flow.

```
updateKey (key_id, …)        ─▶ non-policy config (label/active/priority/pool/limits/billing_mode+subscription_tier) — applies now
syncKeyBilling (key_id)      ─▶ refresh cached balance/usage from the provider adapter
resetKeyHealth (key_id)      ─▶ clear consecutive_failures → back to the healthy pool
setKeyPolicy (integration_id, …)         ─▶ PROPOSE a usage-policy change  (files a pending row — NEVER applies)
listPolicyProposals / decidePolicyProposal  ─▶ a HUMAN approves (applies) / rejects
listWouldDeny                ─▶ how often a policy WOULD deny real traffic (DARK, blocks nothing)
listBillingCapabilities      ─▶ which providers have a live billing adapter
```

> **AUTH:** every call carries the platform admin key (`X-Admin-Key`, from
> `SPIDERIQ_ADMIN_API_KEY`) — **not** a client PAT. These are **super_admin-only**
> and apply **platform-wide**: a policy you get applied to a key changes key
> selection for every tenant. There is no per-brand scoping here.

## The one mental model that prevents every mistake

**A key's usage POLICY is never self-applied.** `setKeyPolicy` writes **nothing**
to the key — it files a *pending proposal*. The policy only changes when a human
runs `decidePolicyProposal(approve)`. Why: `allowed_activities` is a filter on key
selection, and an over-broad restriction can **empty a provider's usable pool and
starve the 163-worker hot path** (a would-deny cascade). So the agent's job is to
*measure* (`listWouldDeny`) and *recommend* (`setKeyPolicy`); a human decides. This
mirrors the routing self-heal split — the vault's whole thesis
(`[[agent-proposes-human-approves-gate]]`).

## Approach

- **Measure before you restrict** — `listWouldDeny` is the DARK shadow log: for
  each key it counts how often its policy WOULD have denied real traffic if
  enforcement were armed. Read it for the activity you'd exclude *before* proposing
  a restriction. → [references/policy-propose-decide.md](references/policy-propose-decide.md)
- **Propose, never apply** — `setKeyPolicy` files a pending proposal (idempotent
  per key). It changes nothing. → [references/policy-propose-decide.md](references/policy-propose-decide.md)
- **A human decides** — `listPolicyProposals` shows the current-vs-proposed diff;
  `decidePolicyProposal(approve)` APPLIES it (backfilling the array from a coarse
  `usage_policy`), `reject` discards it. → [references/policy-propose-decide.md](references/policy-propose-decide.md)
- **Operate the key** — `updateKey` (non-policy config), `resetKeyHealth` (after a
  fix), `syncKeyBilling` / `listBillingCapabilities` (balance, where supported). →
  [references/manage-keys.md](references/manage-keys.md)

<HARD-GATE name="policy-is-propose-only">
A key's ToS usage policy (`allowed_activities` / `allowed_consumers` /
`usage_policy`) can ONLY change through **`setKeyPolicy` (propose) → a human
`decidePolicyProposal(approve)`**. Do **NOT** look for a way to apply a policy in
one step — `updateKey` deliberately cannot set it, and there is no other door. If
you are an automated caller, your terminal action is `setKeyPolicy`; **stop
there** and surface the proposal for a human to approve. Applying a policy narrows
which keys can serve an activity, and a wrong restriction denies live traffic for
every tenant — that is why it is human-gated. (SpiderGate vault policy · VAULT.1.)
</HARD-GATE>

## Rules (Non-Negotiable)

**POLICY IS PROPOSE-ONLY.** See the HARD-GATE. `setKeyPolicy` files a proposal and
applies nothing; only a human `decidePolicyProposal(approve)` writes the key. Never
imply a policy took effect just because you proposed it.

**MEASURE WOULD-DENY FIRST.** Before proposing a restrictive policy, run
`listWouldDeny` for the key/activity. A `would_deny_count > 0` means real traffic
would be denied under enforcement — your proposal's blast radius. The log is DARK
(nothing is blocked yet), but it is the only safe estimate you have.

**`approve` APPLIES; `reject` CHANGES NOTHING.** `decidePolicyProposal(approve)`
writes `allowed_activities`/`allowed_consumers`/`usage_policy` onto the key (and
backfills the array from a coarse `usage_policy`); it 409s if the proposal isn't
pending. `reject` is a pure status flip. Re-read the proposed values + reason
before approving — a proposal can be stale.

**ACTIVITIES ARE A FIXED 6-VALUE DOMAIN.** `allowed_activities` must be a subset of
`scrape, worker_batch, live_agent, interactive_cli, embedding, media`. A
NULL/omitted array = "any" (no restriction). An unknown value is a 422.

**NO PASSWORD TOOL.** A key's decrypted account password has **no method** here
(super-admin-only reveal endpoint, never an agent surface). Don't look for it.

**PLATFORM-WIDE + super_admin-ONLY.** No brand scoping. The key is `X-Admin-Key`
(`SPIDERIQ_ADMIN_API_KEY`), never a client PAT — never echo it into logs or chat.

## Decision tree — pick a reference

| The situation… | Read |
|---|---|
| you want a key to serve only some activities/consumers (restrict a key) | [references/policy-propose-decide.md](references/policy-propose-decide.md) |
| a policy proposal is queued and a human must approve or reject it | [references/policy-propose-decide.md](references/policy-propose-decide.md) |
| you need to size how much traffic a policy would deny (would-deny log) | [references/policy-propose-decide.md](references/policy-propose-decide.md) |
| edit a key's config, reset its health, or check/sync its billing | [references/manage-keys.md](references/manage-keys.md) |
| understand *why* policy is human-gated (the hot-path-starvation risk) | [learnings/](learnings/) |

## Surface (quick map)

All under `/api/v1/admin/gate` on `https://spideriq.ai`, `X-Admin-Key` auth,
super_admin-only. The MCP tools ship in the **mcp-admin** slice
(`@spideriq/mcp-admin`); the CLI is `spideriq gate keys …`.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| Update a key's non-policy config | `PATCH /keys/{id}` | `gate_key_update` | `spideriq gate keys update <id>` |
| Refresh a key's billing | `POST /keys/{id}/sync-billing` | `gate_key_sync_billing` | `spideriq gate keys sync-billing <id>` |
| Reset a key's health | `POST /keys/{id}/reset-health` | `gate_key_reset_health` | `spideriq gate keys reset-health <id>` |
| **Propose** a policy change | `POST /key-policy/proposals` | `gate_key_set_policy` | `spideriq gate keys set-policy <id>` |
| List policy proposals | `GET /key-policy/proposals` | `gate_key_list_proposals` | `spideriq gate keys proposals` |
| Approve / reject a proposal | `POST /key-policy/proposals/{id}/{approve\|reject}` | `gate_key_decide_proposal` | `spideriq gate keys approve\|reject <id>` |
| Would-deny shadow log | `GET /would-deny` | `gate_would_deny_list` | `spideriq gate keys would-deny` |
| Billing-capability map | `GET /billing-capabilities` | `gate_billing_capabilities` | `spideriq gate keys billing-capabilities` |

> **8 MCP tools, 10 CLI verbs.** The MCP `gate_key_decide_proposal` (one tool,
> `decision: approve|reject`) is split on the CLI into `approve` + `reject` (same
> split REST endpoints). The would-deny/billing reads are `require_admin_or_session`;
> the propose/list use `gate:vault:policy` (X-Admin-Key satisfies it); approve/reject
> are super_admin/X-Admin-Key only.

## Methods (native tool calls — from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `updateKey` | non-policy config (label/active/priority/pool/limits + billing_mode/subscription_tier) | [references/manage-keys.md](references/manage-keys.md) |
| `syncKeyBilling` | refresh a key's cached balance/usage | [references/manage-keys.md](references/manage-keys.md) |
| `resetKeyHealth` | clear failures → healthy pool | [references/manage-keys.md](references/manage-keys.md) |
| `setKeyPolicy` | **PROPOSE** a usage-policy change (never applies) | [references/policy-propose-decide.md](references/policy-propose-decide.md) |
| `listPolicyProposals` | pending/filtered proposals (current vs proposed) | [references/policy-propose-decide.md](references/policy-propose-decide.md) |
| `decidePolicyProposal` | approve (applies) / reject (status flip) | [references/policy-propose-decide.md](references/policy-propose-decide.md) |
| `listWouldDeny` | DARK would-deny counts (blast-radius estimate) | [references/policy-propose-decide.md](references/policy-propose-decide.md) |
| `listBillingCapabilities` | which providers have a billing adapter | [references/manage-keys.md](references/manage-keys.md) |

The envelope contract (`guidance:` per method + skill-level `intent_aliases`) lives
in [client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

- **[references/policy-propose-decide.md](references/policy-propose-decide.md)** —
  the measure→propose→approve flow with WRONG→RIGHT. **Read before your first
  `setKeyPolicy`.**
- **[references/manage-keys.md](references/manage-keys.md)** — key config, health
  reset, and billing (Steps / Gotchas / Verify).

## See also

- `learnings/` — `policy-is-human-gated-2026-07-16` (why a one-step key-policy
  apply was deliberately NOT built — the hot-path starvation risk). Starting
  points, not ground truth — verify against current code.
- **Sibling skills in this package** (`@spideriq/admin-skills`): `manage-routing`
  (the alias→model chains), `opvs-admin`, `auth`, `manage-browser-profiles`,
  `manage-locations`, `integrations`.
- **Not this skill:** changing *which model* the gateway routes to is
  `manage-routing`; sending completions is `@spideriq/gateway-skills`
  (`use-the-gateway`). This skill governs *which keys serve which activities*.
