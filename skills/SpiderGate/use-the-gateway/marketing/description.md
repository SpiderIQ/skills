## use-the-gateway

Teach an agent to use **SpiderGate as its LLM provider** — the consumer side of the
gateway. Point any OpenAI-compatible client at `https://spideriq.ai/api/gate/v1`, send a
**task alias** (`spideriq/coding`, `spideriq/fast`, `spideriq/extraction`, …) instead of a
fixed model, and SpiderGate routes across 100+ providers and retries on failure. One PAT replaces juggling OpenRouter + Groq + Mistral
keys and their six rate-limit policies.

### What this skill teaches

- **Pick a task alias** — the two families (`spideriq/*` cost-biased for workers, `agent/*`
  subscription-biased for live agents), and how to choose. Includes the PII-safe lane.
- **Keeping a call's cost bounded** — `max_tokens` and the token's monthly budget bound it.
  `spidergate_options` does not: no cost cap, no cache, no extra fallback. Cost is read
  afterwards from the trace row or the usage read.
- **Structured output + tools** — JSON mode (`response_format`) and function calling, with the
  free-tier streaming `tool_use_failed` gotcha.
- **Account for spend, honestly** — usage over a *real* date range (calendar months, not just a
  rolling lookback), `turns` vs `attempts` so retries don't read as demand, and a four-state
  outcome split where **`unknown` is reported as "we cannot tell"** rather than folded into
  success. Plus per-call cost and the LangFuse-backed trace surface.
- **Decide whether more keys would help — including when they would not.** Key-pressure
  verdicts that are allowed to refuse (`not_quota`, `account_capped`), so a failure spike that
  is not a rate limit stops turning into a purchase recommendation.
- **Stream** — token-by-token SSE, and how it differs from the job-event stream.

### The one rule that matters most

Cost-biased aliases (`spideriq/fast`, `spideriq/free`, `spideriq/extraction`, …) route to
free-tier providers that **may use request data for training**. The skill's HARD-GATE refuses
client PII on those and routes it to `spideriq/lead-analysis` (the PII-safe lane) instead — a
silent leak the competitors leave entirely to you.

### Honest about the tooling

JSON mode and tool-calling are **first-class on CLI + MCP** (`gate_chat`,
`spideriq gate chat --json`), and the analytics surface is complete:
`gate_usage` takes `from`/`to`/`bucket`/`compare`, and `gate_capacity` + `gate_flow` ship at
**`@spideriq/mcp-gate` ≥ 1.10.0** (`@spideriq/cli` ≥ 1.71.0) — on an older client those two
tools simply do not exist. Still **HTTP-only**: token-by-token streaming, embeddings, and the
rest of the multimodal endpoints. `references/gaps.md` documents exactly what's missing and
the raw-HTTP workaround every recipe uses.

### Scope

This is the **consumer** skill — using the gateway. To administer the key pool (add provider
keys, health, billing) use the sibling `spidergate-manager`; to subscribe to job lifecycle
events use `events-stream`.
