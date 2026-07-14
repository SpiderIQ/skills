# Reference — What to propose (and when to decline)

Building a good `proposed_chain` + `reason`, and knowing when NOT to file.

## Build the proposed chain

- **Remove or replace the dead slot** — do not add slots around it. A chain is a
  least-busy POOL: every non-slot-0 peer draws ~1/N of traffic, so a dead peer
  fails its full share no matter how long the chain is. Padding the pool with a
  "backup" does not help; removing the dead peer does.
- **Match the class.** If the alias is a tool alias (its live models have
  `supports_tools=true`), the replacement slot must have `supports_tools=true` in
  `catalogStatus`. A no_tools slot in a tool chain is a fresh outage.
- **Prefer `last_probe_status=ok`.** Pick replacement slots that are probing ok
  now — not un-probed (NULL) and not `error`.
- **Respect slot 0.** Slot 0 is the codex bypass — load-bearing. Don't reorder it
  unless slot 0 itself is the dead slot.

## WRONG / RIGHT

- WRONG: alias `spideriq/extraction` = `[A(ok), B(delisted)]` → propose
  `[A(ok), B(delisted), C(ok)]` (padding — B still fails its share).
  RIGHT: propose `[A(ok), C(ok)]` (B removed) or `[A(ok), C(ok)]` (B→C swap).

- WRONG: file on `catalogStatus(status=error)` for one `openrouter/…:free` slot
  seen once (transient flap).
  RIGHT: skip it this tick; if it is still `error` next tick (or key-failures /
  error-rate corroborate a real outage), then propose.

- WRONG: propose a `no_tools` slot into `agent/coding` (a tool alias).
  RIGHT: propose only `supports_tools=true, last_probe_status=ok` slots for a
  tool alias.

## Write a reason a human can approve in 10 seconds

Name three things: the dead slot, the probe evidence, the fix. Example:

> `mistral/mistral-large` is delisted at the provider (last_probe_status=delisted,
> last_probe_at 2026-07-14T13:02Z) and it sits in spideriq/creative slot 1.
> Proposing to drop it and keep the two ok slots (openrouter/…, x_ai/…). No new
> models added.

## When to DECLINE (don't file)

- The only signal is a lone transient `error`.
- The dead model is in no live alias (`in_task_aliases` empty).
- An open pending proposal already targets the alias.
- You cannot find a same-class `ok` replacement AND removing the dead slot would
  empty the chain — in that case file a proposal with a reason that says "no
  healthy replacement available, human capacity decision needed" rather than
  proposing an empty or degraded chain, OR just the board card + escalate. Never
  propose a chain you know is worse.
