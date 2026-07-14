## gate-health-watch

The autonomous SpiderGate health watcher's **read + propose** surface. Once an
hour the watcher reads the probe-truth routing catalog, spots a model that has
gone bad (`delisted` / `no_tools` / persistently `errored`) inside a **live**
alias chain, and **files a Tier-2 routing proposal** for a human to approve.

Least privilege by design: **it proposes a fix, it never applies one.** Setting,
rolling back, and approving a chain are not reachable with this skill's token —
those routing writes stay on the human `manage-routing` surface (`X-Admin-Key`).

### What this skill does

- **`catalogStatus`** — every model projected to its probe truth
  (`supports_tools`, `last_probe_status`, `in_task_aliases`). The truth source
  for finding dead slots — not `GET /models`.
- **`listProposals`** — the routing-proposal queue, so the watcher never files a
  duplicate for an alias that already has one open.
- **`fileProposal`** — the only write: insert a `status='pending', tier=2` row
  (current chain resolved server-side; idempotent per alias). Queues a fix; a
  human approves it in `manage-routing`.

### The rules that keep it safe

- **You propose, a human applies.** The write endpoints reject this token by
  construction — that rejection is the safety rail.
- **Debounce `error`.** Only `delisted` / `no_tools` are deterministic-dead; a
  lone `error` is usually a transient flap. Corroborate before filing.
- **A chain is a least-busy pool, not a priority list.** Fix by removing/replacing
  the dead slot — never pad the pool with a redundant tail.
- **`agent/*` is human-gated by definition** — file the proposal, never expect it
  to auto-apply.
