# The watcher proposes; it structurally cannot apply

SpiderGate now self-heals on the server (WS4: it auto-evicts genuinely-dead slots
behind a consecutive-probe-failure debounce). On top of that sits a **24/7
watcher** — an OpenClaw agent ("Kevin") that reads gate health every hour and
**files routing proposals for a human to approve**. It never changes live routing.

## Why the propose/apply split is a scope AND a surface split

Owner-lock #6: the watcher reads + proposes, never sets / rolls back / approves.
Enforced in two independent layers, so no prompt or bug can bypass it:

1. **Scope.** The watcher's PAT carries only `gate:routing:read` +
   `gate:routing:propose`. The routing WRITE endpoints (`PUT /aliases`,
   `POST /rollback`, `POST /proposals/{id}/approve`) have **no scoped-PAT path** —
   they require the master `X-Admin-Key` / a super_admin session. The watcher's
   token is 403'd or simply not accepted there, by construction.
2. **Surface.** This skill (`gate-health-watch`) exposes only `catalogStatus`,
   `listProposals`, `fileProposal`. The set/rollback/approve methods live in the
   separate `manage-routing` skill (X-Admin-Key, human). The watcher never even
   sees them.

`fileProposal` inserts a `status='pending', tier=2` row. `current_chain` is
resolved server-side from the live alias, so the caller cannot spoof state; it is
idempotent per alias (migration-333 partial unique index — one open proposal per
alias).

## The two probe-truth traps (inherited from self_heal)

- **`error` is not "dead".** `last_probe_status` collapses every transient
  (429 / 5xx / auth / timeout) into `error`, and free `:free` slugs flap
  ok↔error every probe cycle. Only `delisted` / `no_tools` are deterministic-dead.
  A proposal filed on a lone `error` wastes a human review — debounce it
  (persistent across ticks, or corroborated by key-failures / error-rate).
- **A chain is a least-busy pool, not a priority list.** Every non-slot-0 peer
  draws ~1/N of traffic, so a dead peer fails its full share regardless of chain
  length. The fix is to REMOVE/REPLACE the dead slot — never pad the pool with a
  redundant tail.

## Take-away for extending gate autonomy

Keep the propose/apply boundary as **both** a scope split and a surface split,
and make the watcher act off the **probe catalog** (the truth) not the chain
listing (which happily lists a slot the provider has delisted).
