# Structured output (JSON) + tool calling

SpiderGate is OpenAI-compatible, so `response_format` (JSON mode / JSON schema) and
`tools` / `tool_choice` (function calling) work exactly as they do against OpenAI —
**over HTTP.** The MCP `gate_chat` tool forwards neither, so these are HTTP-only
([gaps.md](gaps.md)). Tool-using turns on free-tier providers also have a streaming
failure mode worth knowing (below).

## JSON mode

### WRONG → RIGHT

❌ **WRONG** — "respond in JSON" in the prompt and hope; the model wraps it in prose
or a ```json fence and your `json.loads` throws.
```json
{"model":"spideriq/extraction","messages":[{"role":"user","content":"Return JSON with name and city"}]}
```

✅ **RIGHT** — ask the API to constrain the output.
```json
{
  "model": "spideriq/extraction",
  "messages": [
    {"role":"system","content":"Extract fields. Reply with a JSON object only."},
    {"role":"user","content":"Jane Doe runs a bakery in Lyon."}
  ],
  "response_format": { "type": "json_object" }
}
```
For a strict shape, use `json_schema`:
```json
"response_format": {
  "type": "json_schema",
  "json_schema": { "name": "person", "schema": {
    "type": "object",
    "properties": {"name": {"type":"string"}, "city": {"type":"string"}},
    "required": ["name","city"]
  }}
}
```

**Gotcha:** not every provider/model behind every alias honors `json_schema` strictly.
Prefer a model that supports structured outputs (the `gpt-*` family, Mistral) — pin it
or use an alias whose slot-0 is one of those. Always still wrap your `json.loads` in a
guard and retry on parse failure.

## Tool / function calling

### WRONG → RIGHT

❌ **WRONG** — describing the tool in the system prompt and parsing the assistant's prose
for a "call."

✅ **RIGHT** — pass real OpenAI tool definitions; read `message.tool_calls` back.
```json
{
  "model": "spideriq/tool-use",
  "messages": [{"role":"user","content":"What's the weather in Berlin?"}],
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Get current weather for a city",
      "parameters": {"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}
    }
  }],
  "tool_choice": "auto"
}
```
The assistant message comes back with `tool_calls: [{id, function:{name, arguments}}]`.
Execute the tool, then send the result back as a `role:"tool"` message (`tool_call_id` set)
in the next turn — standard OpenAI loop.

Use **`spideriq/tool-use`** or **`agent/tool-use`** — they're biased to models that do
function calling well (Groq Llama 3.3 70B / MiniMax M2.5). `tool_choice` accepts
`"none"`, `"auto"`, `"required"`, or `{type:"function",function:{name}}` to force one tool.

## Gotcha — `tool_use_failed` on streaming + free-tier Groq

A tool-using call that **streams** AND falls through to a **Groq** slot can surface a
provider error `tool_use_failed` (the model emitted a tool call that failed schema
validation — more likely with a large tool inventory). SpiderGate maps it to a clean
**HTTP 400** `invalid_request_error` carrying `failed_generation` — it is **non-retriable**;
repair the tool schema/args and resubmit (don't blind-retry). This is streaming-only;
non-streaming tool calls return the real HTTP status. (SpiderGate LEARNINGS — Groq stream
error patch, 2026-06-08.) Keep tool inventories tight to reduce its frequency.

## Verify

```bash
# JSON mode returns parseable JSON content:
curl -s https://spideriq.ai/api/gate/v1/chat/completions \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"model":"spideriq/extraction","messages":[{"role":"user","content":"name=Jane city=Lyon as JSON"}],"response_format":{"type":"json_object"},"max_tokens":64}' \
  | python3 -c "import json,sys; c=json.load(sys.stdin)['choices'][0]['message']['content']; json.loads(c); print('valid JSON:', c)"
```
If the inner `json.loads(c)` doesn't throw, JSON mode is working for that route.
