# Probe-backed routing: the kimi/hermes incident (PR #1783)

The worked example behind every rule in this skill — why the probe catalog
exists, why "validate before set," and why chain length is not redundancy.

## What happened

By 2026-06-18 SpiderGate's error rate had regressed to **~48% per attempt**
(16.9% true client-facing once you collapse fallback churn to one row per
request). The failures weren't spread evenly — they pooled in the **`spideriq/*`
worker family**:

- `spideriq/opvs` — **69%** failing
- `spideriq/creative` — **50%** failing
- `agent/*` — **<2%** (healthy; untouched)

## The trap: a chain is a least-busy POOL, not a priority list

`litellm.Router` does **not** try the chain top-to-bottom and stop at the first
success. It treats every live slot as an **equal least-busy peer** and sends
roughly **1/N** of the alias's traffic to *each* one. (Only slot 0 is special —
the codex bypass fires there.)

Two models were quietly broken but still **listed** in 5+ worker chains:

1. `groq/moonshotai/kimi-k2-instruct` — **de-listed at the provider** (404 +
   60s cooldown on every hit). It had been de-listed for a while; the chain
   still named it.
2. `nousresearch/hermes-3-llama-3.1-405b:free` — **throttled (429) AND
   tool-incapable** (404 when a request carried `tools[]`).

Because each was an equal peer, each drew its full ~1/N share of traffic and
failed it — for **48 hours**. Chain position didn't matter; "there are other
models in the chain" was not redundancy.

## Why the model list lied

`GET /models` (and the chain definition) showed both models as members of the
chain — they *were* configured. What the model list **cannot** tell you is that
kimi-k2 was de-listed at the provider and hermes-3 couldn't do tools. **Only a
probe** — actually calling the model (and calling it with `tools[]`) — reveals
that. The chain said "fine"; the provider said "gone."

## The fix → the tooling this skill teaches

PR #1783 swapped the broken peers for **probe-verified** slots:

- kimi-k2 → `groq/openai/gpt-oss-120b` (probe-verified: 200 + tool_calls)
- hermes-3-405b:free → `google/gemma-4-31b-it:free` (the only free OpenRouter
  model that both serves and does tools — the free cost tail was kept by policy)

Result (smoke): `spideriq/opvs` 69%→0 and `spideriq/creative` 50%→0, both clean
to codestral with no fallback.

That manual SQL-and-redeploy fix is exactly what the gate-dynamic-routing
initiative productized into the tools this skill wraps:

- **`gate_routing_catalog_status`** — every model projected to `supports_tools`,
  `last_probe_status` (ok / no_tools / delisted / error / un-probed), and
  `in_task_aliases`. This is how you'd have *found* kimi-k2 and hermes-3 in
  seconds.
- **`gate_routing_validate`** — dry-run-probe a proposed chain before writing it,
  so a de-listed/tool-incapable slot is caught *before* it serves a single
  request.

## How to apply

- **Find a bad slot from the probe catalog, never the model list.**
  `gate_routing_catalog_status({ status: "error" | "no_tools" | "delisted" })`,
  then read `in_task_aliases` for the blast radius.
- **Removing a broken peer is the reliability lever** — not adding more slots.
  One dead peer fails ~1/N of traffic wherever it sits.
- **Validate every proposed chain** (`all_ok` + per-slot `ok`, plus
  `supports_tools` for tool aliases) before `set_alias`.
- A separate root cause that day — a revoked key (Mistral #29) thrashing
  healthy↔unhealthy hourly — was a **key-pool** problem (`deactivate_dead_api_keys()`),
  not a routing-chain one. Don't conflate "the key is dead" with "the chain is
  wrong"; they're different surfaces (this skill is the chain; the integrations/
  vault surface is the keys).

> Verify the probe-column shapes against
> `packages/mcp-tools/src/admin/gate-routing.ts` and the
> `/api/v1/admin/gate/routing/catalog` response — they're the source of truth and
> may gain columns over time.
