## manage-routing

SpiderGate's LLM-routing control surface. 8 tools to read, validate, edit, and
roll back the task-alias → model chains the gateway serves
(`spideriq/coding`, `spideriq/extraction`, `agent/*`, …), and to adjudicate the
self-heal agent's proposals. Chains live in `gate_task_aliases` and are
**live-editable with no deploy** — change the chain, the Router hot-reloads.

super_admin-only (`X-Admin-Key`), platform-wide: a chain you set serves every
tenant's traffic for that alias.

### What this skill does

- **Diagnose** — `catalogStatus` projects every model to its **probe truth**
  (`supports_tools`, `last_probe_status` ∈ ok/no_tools/delisted/error, plus
  `in_task_aliases` for the blast radius). Probe status is the truth, not
  `GET /models`.
- **Inspect** — `listAliases` / `getAlias` show every alias's live chain + its
  append-only change history (the `history_id`s you roll back to).
- **Validate** — `validateAlias` dry-run-probes a proposed chain (meter-exempt,
  changes nothing) and returns a per-slot verdict + `all_ok`. Run it before
  every write.
- **Edit** — `setAlias` replaces a chain wholesale + hot-reloads the Router,
  writing a rollback-able history row. Rejects (422) known-bad tool-class slots.
- **Self-heal** — `listProposals` / `decideProposal` review and approve/reject
  the agent's Tier-2 suggestions (`approve` applies + reloads; `reject` changes
  nothing).
- **Recover** — `rollbackAlias` restores any prior chain by `history_id`.

### The mental model that prevents every mistake

A chain is a **least-busy pool, not a priority list.** Only slot 0 is
load-bearing (codex bypass); every other slot is an equal peer drawing ~1/N of
traffic. So one dead/throttled/tool-incapable model anywhere in the chain fails
its full share — chain length is not redundancy. The fix is *removing* broken
peers, and the probe catalog tells you which they are. (See the `learnings/`
worked example: PR #1783, where a de-listed `kimi-k2` sat in 5 chains and failed
~1/N of their traffic for 48h.)

### Guardrails

- **`agent/*` is human-gated** — editable by these tools but never self-applied;
  the self-heal agent files every `agent/*` change as proposal-only.
- **Validate before set** — a bad push breaks the alias for every tenant until
  rollback.
- **Probe-backed** — pick slots that actually serve (and do tools, for tool
  aliases), not slots that merely appear in the model list.

### Typical workflows

- **A worker alias is erroring** — `catalog --status error` → find the bad slot
  and its aliases → assemble a healthy chain → `validate` → `set` → re-`validate`.
- **The self-heal agent filed a proposal** — `proposals --status pending` →
  read `proposed_chain`/`reason` → `validate` it (may be stale) → `approve` /
  `reject`.
- **A change regressed quality** — `get <alias>` → pick a good `history_id` →
  `rollback`.
