# Send a completion — cost-aware

The headline reason to route through SpiderGate instead of a raw provider: a
**per-request dollar cap**, a **response cache**, an **explicit fallback chain**, and
the **actual cost handed back** (`spidergate_metadata.cost_usd`, when present). The first
three live in the `spidergate_options` body block and are now forwarded by **MCP
`gate_chat` and `spideriq gate chat`** (≥ cli@1.25.0 / mcp@1.31.0; `--max-cost`/`--cache`
on the CLI) — the curl examples below are the raw-HTTP form, equivalent to the tool args.

## The minimal call

```bash
curl -s https://spideriq.ai/api/gate/v1/chat/completions \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "spideriq/extraction",
    "messages": [{"role":"user","content":"Extract the company name: Acme Corp ships widgets."}],
    "max_tokens": 64
  }'
```

Response is OpenAI-shaped, plus a `spidergate_metadata` block:

```json
{
  "choices": [{"message": {"role":"assistant","content":"Acme Corp"}, "finish_reason":"stop"}],
  "usage": {"prompt_tokens": 18, "completion_tokens": 3, "total_tokens": 21},
  "spidergate_metadata": {
    "provider": "groq", "provider_model": "llama-3.1-8b-instant",
    "latency_ms": 640, "cost_usd": 0.000004, "cache_hit": false, "fallback_used": false
  }
}
```

## WRONG → RIGHT

### Reading cost from the wrong place

❌ **WRONG** — `usage` is tokens only; there is no dollar figure in it.
```python
cost = resp["usage"]["total_tokens"]        # that's a token COUNT, not dollars
```

✅ **RIGHT** — the dollar cost of THIS call is in `spidergate_metadata`.
```python
meta = resp["spidergate_metadata"]
cost = meta["cost_usd"]                      # e.g. 0.000004
served = meta["provider_model"]             # what actually answered (may differ from slot-0)
```

### Letting an expensive call run unbounded

❌ **WRONG** — a long-context prompt on a premium model with no ceiling.
```json
{"model": "spideriq/lead-analysis", "messages": [...huge...]}
```

✅ **RIGHT** — cap the spend; the gateway aborts/avoids a route that would exceed it.
```json
{
  "model": "spideriq/lead-analysis",
  "messages": [...],
  "spidergate_options": { "max_cost_usd": 0.02 }
}
```
`max_cost_usd` is bounded `0.001 .. 100.0`. Use it as a circuit-breaker on agent loops
that could otherwise fan out into many premium calls.

### Re-paying for an identical prompt

❌ **WRONG** — the same system+user prompt sent 50× in a batch, paid 50×.

✅ **RIGHT** — enable the exact-match cache for idempotent prompts.
```json
{
  "model": "spideriq/classification",
  "messages": [...],
  "spidergate_options": { "cache_enabled": true, "cache_ttl_seconds": 3600 }
}
```
A cache hit returns `spidergate_metadata.cache_hit: true` and `cost_usd: 0`. `cache_ttl_seconds`
is bounded `60 .. 86400`. Only cache when identical inputs SHOULD give identical outputs
(classification/extraction — yes; creative generation — usually no).

### When nothing can serve your budget — `422 no_qualifying_model`

Before dispatching, the gateway checks each candidate model against what it has been **measured
doing** at your completion budget. A model measured returning an empty completion at that budget is
removed from the pool for this request, and another model behind the alias serves instead — you see
an ordinary `200`.

If **no** candidate qualifies you get a typed refusal, and **nothing is billed** because no provider
was contacted:

```json
{
  "error": {
    "type": "invalid_request_error",
    "code": "no_qualifying_model",
    "message": "No model behind 'MiniMax-M2.5' can serve a completion budget of 16 tokens. Every candidate is measured to fail at this budget — raise max_tokens or request a different model."
  },
  "spidergate_error": {
    "requested_model": "MiniMax-M2.5",
    "completion_budget": 16,
    "candidates": [
      { "model": "MiniMax-M2.5", "provider": "openai", "verdict": "known_empty_at_budget" }
    ]
  }
}
```

❌ **WRONG** — retrying it. There is no `Retry-After`, the verdict is deterministic, and the same
request fails the same way every time. A retry loop never terminates.

✅ **RIGHT** — raise `max_tokens`, or send a different model/alias. Read
`spidergate_error.candidates[]` to see what was ruled out and why:
`known_empty_at_budget` (measured returning nothing at this budget) ·
`exceeds_tier_ceiling` (budget above the model's measured ceiling on its tier).

**Pinning one concrete model removes the reroute.** Rerouting works by narrowing a pool, so a single
pinned model has no alternative to move to and a disqualification becomes a refusal immediately. Use
a task alias if you want the reroute.

**On the streaming path this is a real `422` with `content-type: application/json`** — not a `200`
carrying an error frame in the SSE body. Assert the status code, not merely "did I get an error".

### Hand-rolling a fallback chain the alias already gives you

❌ **WRONG** — catching an error client-side and re-POSTing to a second model.

✅ **RIGHT** — let the alias chain do it, or declare your own:
```json
{
  "model": "spideriq/coding",
  "messages": [...],
  "spidergate_options": { "fallback_models": ["spideriq/chat", "gpt-4o"] }
}
```
SpiderGate already does 3 retries + 60 s cooldown per failed deployment and walks the
alias chain. `fallback_models` *extends* that with your own preferences. `fallback_used: true`
in the metadata tells you a fallback fired; `original_model` shows what you asked for.

## Gotchas

- **`max_cost_usd` is a guard, not a quote.** It prevents a route whose estimated cost
  exceeds the cap; it does not pre-quote the call. Read `cost_usd` after to see the real number.
- **`temperature`/`max_tokens`/`stop`/`seed`** are standard OpenAI params and pass straight
  through — they are NOT under `spidergate_options`.
- **`preferred_providers` / `excluded_providers`** (inside `spidergate_options`) steer or
  ban providers by name (e.g. exclude a provider whose ToS you can't accept) — analogous to
  OpenRouter's `provider.order` / `provider.ignore` ([competitor-landscape.md](competitor-landscape.md)).
- **MCP + CLI now do all of the above** (≥ cli@1.25.0 / mcp@1.31.0): pass `spidergate_options`
  to `gate_chat`, or `--max-cost`/`--cache` to `spideriq gate chat`. Older clients: raw HTTP.

## Verify

```bash
# Confirm the cap + cost-readback path on a tiny call:
curl -s https://spideriq.ai/api/gate/v1/chat/completions \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"model":"spideriq/fast","messages":[{"role":"user","content":"say OK"}],"max_tokens":8,"spidergate_options":{"max_cost_usd":0.01}}' \
  | python3 -c "import json,sys; m=json.load(sys.stdin)['spidergate_metadata']; print('served:', m['provider_model'], '| cost_usd:', m['cost_usd'], '| cache_hit:', m['cache_hit'])"
```
A printed `cost_usd` (even `0.0` on a cache hit) confirms the metadata path works.
