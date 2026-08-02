# Stream a completion (and where job events live)

Two different "streams" — don't confuse them:

| You want… | Use | Skill |
|---|---|---|
| **completion tokens** as the LLM generates them | `POST /chat/completions` with `stream: true` (SSE) | **this skill** (below) |
| **job lifecycle** events (`job.queued/started/completed/failed`) | `GET /api/v1/events/stream?token=<pat>` | the **events-stream** sibling skill |

Streaming completions is about *one LLM call's tokens*. The event stream is about
*background jobs you submitted* (scrapes, campaigns). If the user says "stream the
answer" → here. "Notify me when my job finishes" → events-stream.

## Streaming a completion

```bash
curl -N -s https://spideriq.ai/api/gate/v1/chat/completions \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "spideriq/chat",
    "messages": [{"role":"user","content":"Write a haiku about routing."}],
    "stream": true,
    "stream_options": { "include_usage": true }
  }'
```

You get OpenAI-format SSE: a sequence of `data: {chat.completion.chunk}` lines, each
with `choices[].delta.content`, terminated by `data: [DONE]`. With
`stream_options.include_usage: true`, the **final** chunk carries the `usage` block
(otherwise streaming omits token counts).

Python (the standard OpenAI SDK works — just repoint `base_url`):
```python
from openai import OpenAI
client = OpenAI(base_url="https://spideriq.ai/api/gate/v1", api_key=SPIDERIQ_PAT)
stream = client.chat.completions.create(
    model="spideriq/chat",
    messages=[{"role":"user","content":"Write a haiku about routing."}],
    stream=True,
)
for chunk in stream:
    delta = chunk.choices[0].delta.content
    if delta: print(delta, end="", flush=True)
```

## Gotchas

- **MCP can't stream.** `gate_chat` is non-streaming only ([gaps.md](gaps.md)). To stream,
  use raw HTTP or the OpenAI SDK pointed at the gateway base URL.
- **Never reconnect per token.** It's ONE long-lived connection; iterate it. Opening a new
  request per chunk hammers the gateway and breaks the stream.
- **Streaming + tool calls + a Groq fallback** can surface `tool_use_failed` as a clean HTTP
  400 (`failed_generation` in the body) — non-retriable, repair-and-resubmit. See
  [structured-output-and-tools.md](structured-output-and-tools.md).
- **Cost on a stream** still arrives in `spidergate_metadata` on the response, and token usage
  only if you set `stream_options.include_usage`.
- **Proxy buffering** can stall a stream if you front the gateway with your own nginx — disable
  `proxy_buffering` and raise `proxy_read_timeout` (SpiderGate LEARNINGS #10). Calling
  `spideriq.ai` directly, this is already handled.

## Verify

```bash
# See chunked deltas arrive (the -N disables curl buffering):
curl -N -s https://spideriq.ai/api/gate/v1/chat/completions \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"model":"spideriq/fast","messages":[{"role":"user","content":"count to 5"}],"stream":true}' \
  | head -5
# Multiple `data: {"object":"chat.completion.chunk",...}` lines = streaming works.
```
