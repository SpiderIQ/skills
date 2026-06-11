## use-the-gateway

Teach an agent to use **SpiderGate as its LLM provider** — the consumer side of the
gateway. Point any OpenAI-compatible client at `https://spideriq.ai/api/gate/v1`, send a
**task alias** (`spideriq/coding`, `spideriq/fast`, `spideriq/extraction`, …) instead of a
fixed model, and SpiderGate routes across 100+ providers, retries + falls back on failure,
and hands back the real per-call cost. One PAT replaces juggling OpenRouter + Groq + Mistral
keys and their six rate-limit policies.

### What this skill teaches

- **Pick a task alias** — the two families (`spideriq/*` cost-biased for workers, `agent/*`
  subscription-biased for live agents), and how to choose. Includes the PII-safe lane.
- **Cost-aware completions** — cap spend per call (`max_cost_usd`), cache idempotent prompts,
  declare a fallback chain, and read the dollar cost back from `spidergate_metadata.cost_usd`.
- **Structured output + tools** — JSON mode (`response_format`) and function calling, with the
  free-tier streaming `tool_use_failed` gotcha.
- **Account for spend** — usage rollups, per-call cost, and the LangFuse-backed trace surface.
- **Stream** — token-by-token SSE, and how it differs from the job-event stream.

### The one rule that matters most

Cost-biased aliases (`spideriq/fast`, `spideriq/free`, `spideriq/extraction`, …) route to
free-tier providers that **may use request data for training**. The skill's HARD-GATE refuses
client PII on those and routes it to `spideriq/lead-analysis` (the PII-safe lane) instead — a
silent leak the competitors leave entirely to you.

### Honest about the tooling

The full cost-control / streaming / JSON / tool-calling power is **HTTP-only** today: there is
no `gate` CLI command and the MCP `gate_chat` tool is text-only. `references/gaps.md`
documents exactly what's missing and the raw-HTTP workaround every recipe uses.

### Scope

This is the **consumer** skill — using the gateway. To administer the key pool (add provider
keys, health, billing) use the sibling `spidergate-manager`; to subscribe to job lifecycle
events use `events-stream`.
