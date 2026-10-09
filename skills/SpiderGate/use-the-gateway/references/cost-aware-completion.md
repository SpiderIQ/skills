# Send a completion — and keep its cost bounded

One OpenAI-compatible call. What bounds its cost is `max_tokens` and your token's
budget. What it cost is read afterwards, from usage or the trace.

🔴 **`spidergate_options` does not cap, cache or re-route anything.** The request
accepts that object, and the server reads none of these fields:
`max_cost_usd`, `cache_enabled`, `cache_ttl_seconds`, `fallback_models`,
`preferred_providers`, `excluded_providers`, `timeout_ms`, `retry_count`.
Sending them changes nothing: no cost ceiling, no cache, no extra fallback.
Earlier versions of this skill said the opposite. A loop that relies on
`max_cost_usd` to stop is not bounded.

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

The answer is the OpenAI chat-completion body: `id`, `model`, `choices`, `usage`.
There is **no `spidergate_metadata` block** and no dollar figure in it.

| You want | Read |
|---|---|
| What served the call | `model` in the body. On raw HTTP also the `X-Served-Model-Catalog-Id` response header: the served model, normalised to the catalog's id space. It is sent on streaming and non-streaming answers. |
| Tokens used | `usage.prompt_tokens`, `usage.completion_tokens`, `usage.total_tokens` |
| What it cost | Not in the response. The call's row in the trace list (`gate_traces`, newest first) carries `cost_usd`, and `gate_usage` sums a period. See [read-usage-and-traces.md](read-usage-and-traces.md). |

## WRONG → RIGHT

### Reading cost from the response

❌ **WRONG** — there is no such block. This raises `KeyError`.
```python
cost = resp["spidergate_metadata"]["cost_usd"]
```

❌ **WRONG** — a token count is not dollars.
```python
cost = resp["usage"]["total_tokens"]
```

✅ **RIGHT** — keep what the response does carry, and read cost where it is stored.
```python
served = resp["model"]                      # the model that answered
tokens = resp["usage"]["total_tokens"]      # a count, for your own bookkeeping
# cost: this call's row in the trace list (gate_traces), or gate_usage for a period
```

### Letting an expensive call run unbounded

❌ **WRONG** — trusting a cost ceiling that is not read.
```json
{"model": "spideriq/lead-analysis", "messages": [...], "spidergate_options": {"max_cost_usd": 0.02}}
```

✅ **RIGHT** — bound the output, and bound the token.
```json
{"model": "spideriq/lead-analysis", "messages": [...], "max_tokens": 800}
```

- **`max_tokens`** bounds the output of this one call. It does not bound the
  input: a long prompt is billed whatever `max_tokens` says, so trim the context
  you send.
- **The token's monthly budget** bounds everything the token spends. When a
  token has a `monthly_budget_usd` and its spend reaches it, every request on that
  token is refused with **`402`**, code **`budget_exceeded`**, before a provider is
  contacted. A token with no budget set is not capped. The check runs before the
  request, so the call that crosses the line still completes.
- **In an agent loop**, count the calls yourself and stop on your own limit.
  Nothing on the server stops a loop that stays under the token's budget.

### Re-paying for an identical prompt

❌ **WRONG** — expecting `cache_enabled` to make the second call free. It is not
read, and no request option turns a response cache on.

✅ **RIGHT** — keep your own map from prompt to answer for prompts where the same
input should give the same output (classification, extraction), and do not send
the repeat.

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

### Hand-rolling a fallback

❌ **WRONG** — sending `spidergate_options.fallback_models`. It is not read, and it
adds no model to the alias.

✅ **RIGHT** — send a task alias and let the gateway route. The router retries a
failed attempt up to 3 times and rests a failing deployment for 60 seconds. What
sits behind an alias, and which aliases hand over to another alias when their
own models are exhausted, is in [pick-an-alias.md](pick-an-alias.md). To choose
the models yourself, build a client alias (the `client-aliases` skill).

## Gotchas

- **`temperature`, `max_tokens`, `stop`, `seed`, `response_format`, `tools` and
  `tool_choice`** are standard OpenAI parameters at the top level of the body.
  They are read. None of them goes under `spidergate_options`.
- **The CLI flags `--max-cost` and `--cache` are sent and ignored.**
  `spideriq gate chat` and the MCP `gate_chat` tool both forward
  `spidergate_options` as given; the server does not read the fields above.
- **You cannot steer or ban a provider per request.** `preferred_providers` and
  `excluded_providers` are not read. Choose an alias whose models you accept, or
  build a client alias.

## Verify

```bash
# One tiny call. Headers go to /tmp/h, the body to the Python reader.
curl -s -D /tmp/h https://spideriq.ai/api/gate/v1/chat/completions \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"model":"spideriq/fast","messages":[{"role":"user","content":"say OK"}],"max_tokens":8}' \
  | python3 -c "import json,sys; r=json.load(sys.stdin); print('served:', r.get('model'), '| tokens:', (r.get('usage') or {}).get('total_tokens'), '| spidergate_metadata present:', 'spidergate_metadata' in r)"
grep -i 'x-served-model-catalog-id' /tmp/h
```

It prints the model that served, the token count, and
`spidergate_metadata present: False`. The header line gives the served model's
catalog id.
