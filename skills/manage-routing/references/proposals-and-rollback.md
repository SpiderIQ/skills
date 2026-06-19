# Self-heal proposals + rollback

The self-heal agent watches routing health and **auto-applies only reversible,
low-risk fixes**. Anything riskier — a brand-new model, a change to the
preferred (slot-0) model, or **ANY `agent/*` change** — it files as a **Tier-2
proposal** and leaves for a human/super_admin to adjudicate. This reference is
how you read, approve, reject, and undo those.

## Proposal anatomy

Each proposal row (`listProposals` / `gate_routing_list_proposals`) carries:

| Field | Meaning |
|---|---|
| `current_chain` | what the alias serves now |
| `proposed_chain` | what the agent wants it to become |
| `reason` | why it was proposed |
| `detected_from` | `errorrate` (the alias is failing) · `drift` (chain drifted from catalog truth) · `probe` (a slot started probing bad) |
| `status` | `pending` · `approved` · `rejected` · `applied` · `auto-rolled-back` |

## Steps — approve or reject

1. **List what's pending.**

   ```bash
   spideriq gate routing proposals --status pending
   ```

   MCP: `gate_routing_list_proposals({ status: "pending" })`.

2. **Read `proposed_chain` + `reason` + `detected_from`.** Understand what
   changes and why. Is this an `agent/*` alias? → **stop and get human sign-off**
   (HARD-GATE) before approving.

3. **Validate the proposed chain — it may be stale.** A proposal can be hours
   old; its slots may have gone bad since detection.

   ```bash
   spideriq gate routing validate <alias> --slots '<proposed_chain>'
   ```

   If `all_ok` is false, **reject** it (it's stale/bad) and fix the chain
   manually via [manage-a-chain.md](manage-a-chain.md) instead.

4. **Decide.**

   ```bash
   spideriq gate routing approve 42     # APPLIES proposed_chain (history row + reload)
   spideriq gate routing reject 42      # status flip only — routing UNCHANGED
   ```

   MCP (one tool, both paths): `gate_routing_decide_proposal({ proposal_id: 42, decision: "approve" | "reject" })`.

5. **Verify an approve** — `approve` runs the normal write path, so confirm:

   ```bash
   spideriq gate routing validate <alias>   # re-probe the now-live chain, expect all_ok
   spideriq gate routing get <alias>        # fresh history row recording the apply
   ```

## Steps — rollback

Every `set` and every approved proposal writes an append-only
`gate_alias_history` row, so any change is reversible.

1. **Find the good history_id.**

   ```bash
   spideriq gate routing get spideriq/coding   # read the `history` array → pick the row to restore
   ```

2. **Restore it.**

   ```bash
   spideriq gate routing rollback spideriq/coding --history-id 118 -r "approve #42 regressed extraction"
   ```

   MCP: `gate_routing_rollback({ alias, history_id, reason })`. This restores that
   row's chain + hot-reloads, and writes a NEW history row recording the rollback.

3. **Verify** — `validate <alias>` (no slots) → `all_ok` against the restored
   live chain.

## Gotchas

- **`approve` APPLIES; `reject` changes NOTHING.** `reject` is a pure status
  flip — it does not roll anything back, it just dismisses the suggestion. To
  undo an *already-applied* chain, use `rollback`, not `reject`.
- **`approve` can 422.** If the `proposed_chain` is empty or catalog-rejected
  (stale), the apply fails the same way a manual `set` would. Validate first
  (step 3) to catch it before the round-trip.
- **Rollback restores a point in time.** If the models in that historical chain
  have ALSO gone bad since, the restored chain can probe bad too — always
  `validate` after a rollback.
- **`agent/*` proposals are human-gated.** The agent never auto-applies them, and
  neither should you on your own judgement — get the owner's say-so. See the
  SKILL.md HARD-GATE.

## Verify

- After `approve`: `validate <alias>` → `all_ok: true`; `get <alias>` shows the
  apply in `history`; the proposal's `status` is now `applied`.
- After `reject`: the proposal's `status` is `rejected`; `get <alias>` shows the
  chain **unchanged**.
- After `rollback`: `validate <alias>` → `all_ok: true` on the restored chain; a
  new rollback row is in `history`.
