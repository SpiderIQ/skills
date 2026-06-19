# Manage a routing chain (diagnose → validate → set → verify)

The safe loop for changing what model an alias serves. Skipping a step is how a
bad chain ships to every tenant.

## The least-busy-pool mental model (read this first)

`litellm.Router` serves an alias's chain as a **least-busy pool**, not a
priority list:

- **Slot 0 is the only load-bearing position** — the codex bypass fires on slot
  0. Treat slot 0 as "the preferred model."
- **Every other slot is an equal peer.** The Router sends roughly **1/N** of the
  alias's traffic to *each* live slot, picking the least-busy one per request.
- Therefore **one bad peer = ~1/N of that alias's requests failing**, no matter
  where it sits in the chain. Adding slots is **not** redundancy; a dead model
  in slot 4 is just as harmful as one in slot 1.

Reliability comes from *removing broken peers*, and the probe catalog
(`catalogStatus`) is how you know which peers are broken.

## Steps

1. **Find the bad slot — from the probe catalog, not the model list.**

   ```bash
   # which configured models are probing bad, and which aliases use them?
   spideriq gate routing catalog --status error
   spideriq gate routing catalog --status no_tools
   spideriq gate routing catalog --status delisted
   ```

   Read `in_task_aliases` on each bad row — that's the blast radius. MCP:
   `gate_routing_catalog_status({ status: "error" })`.

2. **Read the alias's current chain + history.**

   ```bash
   spideriq gate routing get spideriq/coding
   ```

   MCP: `gate_routing_get_alias({ alias: "spideriq/coding" })`. Note the
   `history` array — each row's `history_id` is a rollback target.

3. **Assemble a replacement chain from healthy slots.** Pick models whose
   `last_probe_status = ok`. For any tool-using alias (coding, tool-use,
   anything that passes `tools[]`), also require `supports_tools = true`.
   A chain is `[{provider, model}, …]`, slot 0 = preferred.

4. **VALIDATE the proposed chain — every time, before writing.**

   ```bash
   spideriq gate routing validate spideriq/coding \
     --slots '[{"provider":"groq","model":"openai/gpt-oss-120b"},{"provider":"mistral","model":"codestral-latest"}]'
   ```

   MCP: `gate_routing_validate({ alias, slots })`. Confirm **`all_ok: true`** and
   every slot's verdict is `ok` (not `no_tools` / `delisted` / `error`).
   This is a dry-run probe: **no billing, no change.**

5. **SET the chain.** Only after `all_ok`:

   ```bash
   spideriq gate routing set spideriq/coding \
     --slots '[{"provider":"groq","model":"openai/gpt-oss-120b"},{"provider":"mistral","model":"codestral-latest"}]' \
     --reason "swap de-listed kimi-k2 → gpt-oss-120b (probe error)"
   ```

   MCP: `gate_routing_set_alias({ alias, slots, reason })`. This is a **wholesale
   replace** of the whole chain + a live Router reload, and writes an append-only
   history row.

6. **VERIFY — re-probe the live chain (omit `slots`).**

   ```bash
   spideriq gate routing validate spideriq/coding   # no --slots = probe the now-live chain
   ```

   Confirm `all_ok: true` against what's actually live.

## WRONG → RIGHT

```
# WRONG — trust the model list, push without probing
spideriq gate routing list                       # "the model's right there in the chain"
spideriq gate routing set spideriq/coding --slots '[…]'   # 422 rejected_slots, or worse: 200 onto a de-listed model
```

```
# RIGHT — probe-truth, validate, then set
spideriq gate routing catalog --status ok        # pick slots that actually serve
spideriq gate routing validate spideriq/coding --slots '[…]'   # all_ok:true ?
spideriq gate routing set spideriq/coding --slots '[…]' -r "reason"
spideriq gate routing validate spideriq/coding   # re-probe live
```

## Gotchas

- **`set` is wholesale, not a merge.** Whatever `slots` you send becomes the
  entire chain. To "add one model" you must send the full existing chain + the
  new slot — read it with `get` first.
- **`set` 422s with `rejected_slots`** if a tool-class slot is catalog-known-bad
  (`supports_tools=FALSE` / `no_tools` / `delisted`). That's the guardrail, not a
  bug — fix the chain. `validate` tells you the same thing one step earlier.
- **Probe ≠ free-tier exception.** A slot can probe `ok` and still be a free-tier
  model that trains on data — routing policy (which aliases may carry PII) is a
  separate concern handled by the gateway-consumer skill, not here.
- **agent/\* is human-gated.** `set` *works* on `agent/*` but policy says don't
  self-apply — get a human owner's sign-off. See the SKILL.md HARD-GATE.
- **Platform-wide.** There is no brand scoping — a chain you set serves every
  tenant's traffic for that alias.

## Verify

- `validate <alias>` (no slots) returns `all_ok: true` against the live chain.
- `get <alias>` shows a fresh `history` row with your `reason`.
- The previously-failing alias stops erroring (check the gate request logs /
  error rate for that alias family over the next sweep).
