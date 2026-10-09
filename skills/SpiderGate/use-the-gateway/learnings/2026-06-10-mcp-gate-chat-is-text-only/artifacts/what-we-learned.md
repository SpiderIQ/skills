# The MCP gate_chat tool was text-only (resolved)

## What was true until 2026-06-11

An agent connected to `@spideriq/mcp-gate` saw a `gate_chat` tool and took it for a
full OpenAI client. The wrapper forwarded **only** `model` and `messages`, so through
MCP you could not set `temperature` / `max_tokens` / `stop` / `seed`, use
`response_format` (JSON mode / json_schema), or pass `tools` / `tool_choice`.

## What is true now

From `@spideriq/mcp@1.31.0` / `@spideriq/mcp-gate@1.3.0` / `@spideriq/core@1.26.0` the
tool forwards every one of those fields, and `spideriq gate chat` has `--json`.
Streaming is still not available through the tool: it returns one whole response.
For token-by-token output use raw HTTP with `stream: true`, or the OpenAI SDK.

## The part of this note that was wrong

The first version of this note said the missing piece that mattered most was
`spidergate_options` — "no `max_cost_usd` cap, no `cache_enabled`, no
`fallback_models`" — and called those the reason to use the gateway. The tool and
the CLI (`--max-cost`, `--cache`) forward that object now. The server reads none of
those fields, so forwarding them changed nothing. See
`2026-10-08-spidergate-options-are-not-read`.

## How to apply

- Text, JSON mode or tool calling: `gate_chat` does it.
- Streaming: raw HTTP or the OpenAI SDK.
- A cost ceiling: `max_tokens` on the call and a monthly budget on the token. Not
  `spidergate_options`.
- The lesson that holds: when a wrapper forwards a subset of a request, the basic
  call still works and its tests still pass. Check what reaches the wire.
