# The MCP gate_chat tool is text-only

## The trap

An agent connected to `@spideriq/mcp-gate` sees a `gate_chat` tool and assumes it's a
full OpenAI client. It isn't. The wrapper forwards **only** `model` and `messages`:

```ts
// packages/mcp-tools/src/gate/gate.ts
return client.gateChat(args.model, args.messages);
```

So through MCP you **cannot**:

- set `temperature` / `max_tokens` / `stop` / `seed`
- `stream` the response
- use `response_format` (JSON mode / json_schema)
- pass `tools` / `tool_choice` (function calling)
- set `spidergate_options` — i.e. **no `max_cost_usd` cap, no `cache_enabled`, no
  `fallback_models`**

Those `spidergate_options` are precisely the features that make SpiderGate worth using
over hitting a provider directly. Via MCP, you lose them.

## The workaround

For anything beyond a plain text completion, **use raw HTTP** (or the OpenAI SDK pointed
at the gateway base URL):

```bash
curl -s https://spideriq.ai/api/gate/v1/chat/completions \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"model":"spideriq/coding","messages":[...],
       "response_format":{"type":"json_object"},
       "spidergate_options":{"max_cost_usd":0.02,"cache_enabled":true}}'
```

```python
from openai import OpenAI
client = OpenAI(base_url="https://spideriq.ai/api/gate/v1", api_key=SPIDERIQ_PAT)
# full params available: stream=, tools=, response_format=, extra_body={"spidergate_options": {...}}
```

## How to apply

- Plain text answer, no cost cap → `gate_chat` is fine.
- Cost-capped / cached / streamed / JSON / tool-calling → drop to HTTP.
- This is logged as **Gap 2** in `references/gaps.md` with the proposed `inputSchema`
  widening for the CLI/MCP owners. Until that ships, the references in this skill all use
  raw HTTP for the advanced paths on purpose.

> Verify against the live tool: if a future `@spideriq/mcp-gate` version widens
> `gate_chat`'s inputSchema (check `packages/mcp-tools/src/gate/gate.ts`), prefer the tool
> again and update this note.
