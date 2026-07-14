# Reference — Run the hourly gate-health watch

The procedure the watcher runs once an hour. Read-heavy, one deliberate write
(a proposal) only when a real problem is found.

## Steps

1. **Pull the problem slots.** Call `catalogStatus` three times (cheap, bounded
   table) or once and filter client-side:
   - `catalogStatus(status=delisted)` — model dropped at the provider. DETERMINISTIC dead.
   - `catalogStatus(status=no_tools)` — model can't do tool-calls. DETERMINISTIC dead for a tool alias.
   - `catalogStatus(status=error)` — SUSPECT. A transient (429/5xx/auth/timeout) collapses to `error`; free `:free` slugs flap. Do NOT act on a lone `error` unless it is persistent across ticks or corroborated.

2. **Keep only slots that matter.** A dead model matters only if
   `in_task_aliases` is non-empty — it sits in a live chain. A delisted model
   referenced by no alias is not your problem (the catalog sync will drop it).

3. **De-dup against the queue.** For each affected alias, call
   `listProposals(status=pending)`. If a pending proposal already targets that
   alias, STOP for that alias — filing again is a harmless no-op (created=false)
   but you should interpret it, not re-derive the problem.

4. **Assemble the proposed chain.** Take the alias's CURRENT chain (visible via
   `in_task_aliases` membership + `manage-routing` history is a human tool — you
   don't need it; the server fills current_chain for you). Build `proposed_chain`
   = the current chain with the dead slot removed, or swapped for a
   `catalogStatus(status=ok)` slot of the same class (tool-capable if the alias is
   a tool alias — check `supports_tools`). See `what-to-propose.md`.

5. **File the proposal.** `fileProposal(alias, proposed_chain, reason, detected_from)`.
   - `reason` names the dead slot + the probe evidence + the fix.
   - `detected_from` = `probe` (default), or `errorrate` if you acted on a
     corroborated error-rate signal.
   - `created=true` (201) → queued. `created=false` (200) → already pending.

6. **File the board card.** On board `424629e2` (gate-dynamic-routing), create a
   card summarising the proposal so a human sees it immediately (the DB proposal
   only emails super_admins on the proposals digest tick). Link the alias + the
   proposal reason.

## Verify

- After a tick with a real problem: `listProposals(status=pending)` shows your
  proposal; a board card exists on 424629e2.
- After a clean tick: `catalogStatus` shows no delisted/no_tools in a live alias,
  and you filed nothing. That is the correct, common outcome.

## Gotchas

- **Never** call a set/rollback/approve method — they aren't in this skill and
  your token would be rejected anyway. That rejection is the safety rail, not a bug.
- The catalog is the truth; the chain listing lies (a listed slot can be delisted).
- One proposal per alias per problem. Don't thrash the queue.
