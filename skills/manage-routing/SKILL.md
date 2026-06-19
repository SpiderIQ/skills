---
name: manage-routing
version: 0.1.0
description: >
  Manage SpiderGate's LLM routing — the task-alias → model chains the gateway
  routes through (spideriq/coding, spideriq/extraction, agent/*, …) and the
  self-heal agent's Tier-2 proposals. Trigger on: "fix a dead model in the
  gateway", "a SpiderGate alias is failing / erroring", "swap the model behind
  spideriq/coding", "edit a routing chain", "approve / reject a self-heal
  routing proposal", "roll back a routing change", "which models are probing
  bad", "why is spideriq/opvs failing", "validate a routing chain before I push
  it", "the gateway is using a de-listed model". This is the ADMIN routing
  surface (super_admin, X-Admin-Key) — it changes what the gateway serves for
  EVERY tenant. It is NOT how you send a completion (that's the gateway consumer
  skill use-the-gateway) and NOT how you manage provider API keys (that's the
  key-pool / integrations surface). Read it before touching any gate_routing_*
  tool — a bad chain breaks routing for all clients until rolled back.
client: manage-routing
client_version: "0.1.0"
category: admin
triggers:
  - manage gate routing
  - fix a dead model
  - edit a routing chain
  - approve a routing proposal
  - reject a routing proposal
  - rollback a routing change
  - which models are probing bad
  - validate a routing chain
requires_auth: true
requires_brand: false
---

# Manage SpiderGate Routing (alias chains + self-heal proposals)

SpiderGate routes every `model: "spideriq/<task>"` (and `agent/<task>`) request
through an **ordered chain of `{provider, model}` slots**, served by
`litellm.Router`. Those chains live in the `gate_task_aliases` table and are
**live-editable with no deploy** — you change the chain, the Router hot-reloads,
and the next request routes the new way. This skill is the privileged surface
that reads, validates, edits, rolls back those chains, and adjudicates the
self-heal agent's proposals.

```
gate_routing_catalog_status   ─▶  which models probe ok / no_tools / delisted / error
gate_routing_list_aliases     ─▶  every alias + its live chain + change history
gate_routing_validate (alias, [slots])  ─▶  dry-run probe a chain (NO billing, NO change)
gate_routing_set_alias (alias, slots)   ─▶  replace the WHOLE chain + hot-reload  (422 on known-bad slots)
gate_routing_rollback (alias, history_id) ─▶ restore a prior chain + hot-reload
gate_routing_list_proposals / decide_proposal  ─▶  the self-heal agent's Tier-2 suggestions
```

> **AUTH:** every `gate_routing_*` call carries the platform admin key
> (`X-Admin-Key`, from `SPIDERIQ_ADMIN_API_KEY`) — **not** a client PAT. These
> are **super_admin-only** and apply **platform-wide**: a chain you set serves
> every tenant's traffic for that alias. There is no per-brand scoping here.

## The one mental model that prevents every mistake

**A chain is a LEAST-BUSY POOL, not a priority list.** Only **slot 0** is
load-bearing (the codex bypass fires on slot 0). Every other slot is an equal
peer — `litellm.Router` sends ~1/N of the alias's traffic to *each* live slot.
So **a single dead, throttled, or tool-incapable model anywhere in the chain
draws its full ~1/N share and fails it.** Chain length is not redundancy; a
broken peer is a broken peer wherever it sits. The only reliability lever is
*removing* broken peers (and the probe catalog tells you which are broken).
(This is exactly what bit PR #1783 — see `learnings/`.)

## Approach

- **Diagnose first** — never guess which model is bad. `gate_routing_catalog_status`
  projects every model to its **probe truth** (`supports_tools`,
  `last_probe_status` ∈ ok|no_tools|delisted|error|un-probed, `in_task_aliases`).
  Probe status is the truth, **not** `GET /models`. → [references/manage-a-chain.md](references/manage-a-chain.md)
- **Validate before you set** — `gate_routing_validate` dry-run-probes a proposed
  chain (meter-exempt, changes nothing) and returns a per-slot verdict + `all_ok`.
  Run it on every chain *before* `set_alias`. The write itself 422s
  (`rejected_slots`) on a known-bad tool-class slot, but validate tells you
  *why* before you waste the round-trip. → [references/manage-a-chain.md](references/manage-a-chain.md)
- **Adjudicate proposals** — the self-heal agent files **Tier-2 proposals** it
  will NOT auto-apply (a new model, a primary change, ANY `agent/*` change).
  `approve` APPLIES the proposed chain (history row + reload); `reject` is a pure
  status flip that changes nothing. → [references/proposals-and-rollback.md](references/proposals-and-rollback.md)
- **Recover** — every `set_alias`/`approve` writes an append-only history row, so
  any change is reversible. `gate_routing_rollback` restores a prior chain by
  `history_id`. → [references/proposals-and-rollback.md](references/proposals-and-rollback.md)

<HARD-GATE name="agent-star-is-human-gated">
`agent/*` aliases (the LIVE conversational-agent lanes — `agent/chat`,
`agent/tool-use`, `agent/coding`, …) are **editable by these tools but
human-gated by policy.** Do NOT `set_alias` or `approve` a change to any
`agent/*` chain on your own judgement — surface it to a human owner and apply
only on their explicit say-so. The self-heal agent treats EVERY `agent/*` change
as Tier-2 (proposal-only) for the same reason: a bad `agent/*` chain degrades
live multi-turn agents mid-conversation, where a worker batch would just retry.
(SpiderGate routing policy · the gate-dynamic-routing initiative.)
</HARD-GATE>

## Rules (Non-Negotiable)

**VALIDATE BEFORE SET — ALWAYS.** Run `gate_routing_validate` on the exact
`slots` you intend to write and confirm `all_ok` before `gate_routing_set_alias`.
A `set` is a **wholesale replace** of the whole chain (not a merge) + a live
Router reload — a bad push breaks the alias for every tenant until you roll back.

**PROBE STATUS IS THE TRUTH, NOT `/models`.** `GET /models` (or
`gate_routing_list_aliases`) tells you what a chain *claims*; only the probe
catalog (`gate_routing_catalog_status`) tells you what each model **actually
serves and whether it does tools**. A model can be listed in five chains and be
de-listed at the provider — the probe sees it, the model list doesn't. Pick
slots whose `last_probe_status = ok` (and `supports_tools = true` for any
tool-using alias).

**`approve` APPLIES; `reject` CHANGES NOTHING.** `gate_routing_decide_proposal`
with `decision=approve` runs the proposed chain through the normal write path
(history row + reload) and can 422 if the proposal is stale (empty/catalog-
rejected chain). `decision=reject` is a status flip only — routing is untouched.
Read the `proposed_chain` and `reason` before approving; a proposal can be
hours old and its slots may have gone bad since it was detected.

**`agent/*` IS HUMAN-GATED.** See the HARD-GATE. Never self-apply an `agent/*`
change.

**THESE TOOLS ARE PLATFORM-WIDE + super_admin-ONLY.** No brand scoping. The key
is `X-Admin-Key` (`SPIDERIQ_ADMIN_API_KEY`), never a client PAT — never echo it
into logs or chat.

## Decision tree — pick a reference

| The situation… | Read |
|---|---|
| an alias is erroring / a model went dead, and you need to find + swap the bad slot | [references/manage-a-chain.md](references/manage-a-chain.md) |
| you want to edit a chain safely (diagnose → validate → set → verify) | [references/manage-a-chain.md](references/manage-a-chain.md) |
| the self-heal agent filed a proposal and you must approve or reject it | [references/proposals-and-rollback.md](references/proposals-and-rollback.md) |
| a change made things worse and you need to roll back | [references/proposals-and-rollback.md](references/proposals-and-rollback.md) |
| understand *why* probe-backed routing matters (the worked incident) | [learnings/](learnings/) (PR #1783 kimi/hermes) |

## Surface (quick map)

All under `/api/v1/admin/gate/routing` on `https://spideriq.ai`, `X-Admin-Key`
auth, super_admin-only. The MCP tools ship in the **mcp-admin** slice
(`@spideriq/mcp-admin`); the CLI is `spideriq gate routing …`.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| List aliases + chains + history | `GET /aliases` | `gate_routing_list_aliases` | `spideriq gate routing list` |
| One alias + chain + history | `GET /aliases` (filtered) | `gate_routing_get_alias` | `spideriq gate routing get <alias>` |
| Dry-run probe a chain (no billing) | `POST /aliases/{a}/validate` | `gate_routing_validate` | `spideriq gate routing validate <alias> [--slots …]` |
| Replace a chain + hot-reload | `PUT /aliases/{a}` | `gate_routing_set_alias` | `spideriq gate routing set <alias> --slots …` |
| Restore a prior chain | `POST /aliases/{a}/rollback` | `gate_routing_rollback` | `spideriq gate routing rollback <alias> --history-id …` |
| List self-heal proposals | `GET /proposals` | `gate_routing_list_proposals` | `spideriq gate routing proposals [--status …]` |
| Approve / reject a proposal | `POST /proposals/{id}/{approve\|reject}` | `gate_routing_decide_proposal` | `spideriq gate routing approve\|reject <id>` |
| Model catalog with probe truth | `GET /catalog` | `gate_routing_catalog_status` | `spideriq gate routing catalog` |

> **8 MCP tools, 9 CLI verbs.** The MCP `gate_routing_decide_proposal` (one tool,
> `decision: approve|reject`) is split on the CLI into `approve` + `reject`. They
> hit the same split REST endpoints (`/proposals/{id}/approve` · `/reject`).

## Methods (native tool calls — from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `listAliases` | every alias + live chain + change history | [references/manage-a-chain.md](references/manage-a-chain.md) |
| `getAlias` | one alias + its chain + history | [references/manage-a-chain.md](references/manage-a-chain.md) |
| `validateAlias` | dry-run probe a chain (no billing, no change) | [references/manage-a-chain.md](references/manage-a-chain.md) |
| `setAlias` | replace a chain wholesale + hot-reload | [references/manage-a-chain.md](references/manage-a-chain.md) |
| `rollbackAlias` | restore a prior chain by history_id | [references/proposals-and-rollback.md](references/proposals-and-rollback.md) |
| `listProposals` | self-heal Tier-2 proposals (filter by status) | [references/proposals-and-rollback.md](references/proposals-and-rollback.md) |
| `decideProposal` | approve (applies) / reject (status flip) a proposal | [references/proposals-and-rollback.md](references/proposals-and-rollback.md) |
| `catalogStatus` | model catalog projected to probe-truth columns | [references/manage-a-chain.md](references/manage-a-chain.md) |

The envelope contract (`guidance:` per method — `use`/`next`/`warn`/
`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in
[client/schema.yaml](client/schema.yaml).

## References (loaded on demand)

- **[references/manage-a-chain.md](references/manage-a-chain.md)** — the safe edit
  flow: catalog → validate → set → verify, with the least-busy-pool model and
  WRONG→RIGHT. **Read before your first `set_alias`.**
- **[references/proposals-and-rollback.md](references/proposals-and-rollback.md)** —
  read/approve/reject the self-heal agent's proposals; roll a chain back by
  `history_id`. Steps / Gotchas / Verify.

## See also

- `learnings/` — `probe-backed-routing-2026-06-18` (PR #1783: a de-listed
  `kimi-k2` stayed a live least-busy peer in 5 chains and failed ~1/N of their
  traffic for 48h — the worked example of why the probe catalog exists).
  Starting points, not ground truth — verify against current code.
- **Sibling skills in this package** (`@spideriq/admin-skills`): `opvs-admin`,
  `auth`, `manage-browser-profiles`, `manage-locations`, `integrations`.
- **Not this skill:** sending completions through the gateway is
  `@spideriq/gateway-skills` (`use-the-gateway`); managing provider API keys /
  the key pool is the integrations / vault surface. This skill changes *which
  model the gateway routes to*, for everyone.
