---
name: use-the-gateway
description: >
  Route your agent's OWN LLM calls through SpiderGate — SpiderIQ's
  OpenAI-compatible LLM gateway over 100+ providers (litellm.Router).
  Trigger on: "use SpiderGate as my LLM provider", "send a chat completion",
  "call an LLM through the gateway", "pick a model / task alias", "route my
  prompt to the cheapest model", "spideriq/coding", "spideriq/fast",
  "spideriq/extraction", "cap the cost of an LLM call", "cache an LLM
  response", "fall back to another model", "list available models / aliases",
  "what did my agent spend on LLMs", "read my gateway usage / traces / cost",
  "stream a completion", "JSON mode / structured output via the gateway",
  "tool calling through SpiderGate". One OpenAI-compatible endpoint replaces
  juggling OpenRouter + Groq + Mistral keys: send `model: "spideriq/<task>"`,
  SpiderGate routes to the best available model, falls back on failure, and
  hands back the real per-call cost. This skill teaches the CONSUMER surface
  (use the gateway as a provider) — NOT key-pool administration (that's
  spidergate-manager) and NOT job-lifecycle event streaming (that's
  events-stream). Read it before sending the first completion.
version: "0.1.0"
category: ai-gateway
---

# Use the Gateway (SpiderGate as your LLM provider)

SpiderGate is an **OpenAI-compatible** LLM gateway. Point any OpenAI client at
`https://spideriq.ai/api/gate/v1`, send a **task alias** (`spideriq/coding`,
`spideriq/fast`, …) or a real model id as `model`, and SpiderGate picks the best
available model across 100+ providers, retries + falls back on failure, and
returns the actual per-call cost. You bring one PAT — not six provider keys.

```
your agent ──Bearer PAT──▶ POST /api/gate/v1/chat/completions
   model: "spideriq/extraction"          (a TASK, not a vendor)
        │
        ▼  litellm.Router  →  Groq · Mistral · Cerebras · NVIDIA NIM · OpenRouter (100+)
   picks slot-0 model → on error falls through the alias chain → 3 retries, 60s cooldown
        │
        ▼  OpenAI-shaped response  +  spidergate_metadata { provider, provider_model,
                                       cost_usd, latency_ms, cache_hit, fallback_used }
```

## Approach

- **Send a completion** — the 90% case. Pick a task alias, POST messages, read
  the answer. → [references/pick-an-alias.md](references/pick-an-alias.md), then
  [references/cost-aware-completion.md](references/cost-aware-completion.md).
- **Make it cheap + safe** — cap cost per call (`max_cost_usd`), cache repeats,
  declare a fallback chain, read `cost_usd` back. → [references/cost-aware-completion.md](references/cost-aware-completion.md).
- **Structured output / tools** — JSON mode + function calling (HTTP only — the
  MCP `gate_chat` tool can't). → [references/structured-output-and-tools.md](references/structured-output-and-tools.md).
- **Account for spend** — read usage, per-call cost, and traces. → [references/read-usage-and-traces.md](references/read-usage-and-traces.md).
- **Stream** — token-by-token SSE, and where job events live. → [references/stream-and-events.md](references/stream-and-events.md).

<HARD-GATE name="no-pii-on-free-tier">
Free-tier providers (Groq, Mistral-free, OpenRouter `:free`) may use request data
for **model training**, especially outside the EU. The cost-biased aliases route
there by design: **`spideriq/fast`, `spideriq/free`, `spideriq/extraction`,
`spideriq/classification`, and `spideriq/summarization` are NOT safe for client
PII** (names, emails, phone numbers, account data, anything a data-subject could be
identified by). This fails **silently** — the call 200s and the leak is invisible.
Before sending content that contains PII, route it to a premium / BYOK-backed alias
(**`spideriq/lead-analysis`** is the designated PII-safe lane) OR strip the PII
first. When unsure whether a payload carries PII, treat it as if it does.
([references/pick-an-alias.md](references/pick-an-alias.md) · SpiderGate LEARNINGS #12)
</HARD-GATE>

## Rules (Non-Negotiable)

**AUTH:** every call carries `Authorization: Bearer <client_id>:<api_key>:<api_secret>` (or a `spideriq_pat_…`). CLI/MCP load it from `~/.spideriq/credentials.json`; for raw HTTP never echo the secret into logs or chat.

**ALIASES ARE TASKS, NOT VENDORS — and the chain matters.** `model: "spideriq/coding"` means "route this *coding* task," not "use a fixed model." The served model can differ from slot-0 (a fallback fired); **read `spidergate_metadata.provider_model` to know what actually answered** — don't assume. Bare model ids (`gpt-4o`) pin one model and lose the fallback chain.

**COST LIVES IN `spidergate_metadata`, NOT `usage`.** `usage` gives token counts; the per-call **dollar cost is `spidergate_metadata.cost_usd`** (provider-priced on the model that actually served) **when the field is present** — it rides non-streaming responses and is provider-dependent, so guard for its absence rather than assuming it. The aggregate `/usage` endpoint needs your numeric `brand_id`. ([references/read-usage-and-traces.md](references/read-usage-and-traces.md))

**`max_cost_usd`, cache, JSON, and tools are first-class on CLI + MCP (≥ cli@1.25.0 / mcp@1.31.0).** The per-request budget cap, response cache, fallback chain, `response_format`, and `tools`/`tool_choice` are forwarded by `gate_chat` and `spideriq gate chat` (`--max-cost`/`--cache`/`--json`). **Only token-by-token streaming is still HTTP-only** — use the raw endpoint with `stream: true` (or the OpenAI SDK) for that. Older clients: use raw HTTP for all of the above. ([references/gaps.md](references/gaps.md))

**NEVER tight-loop a stream or a poll.** Streaming uses one long-lived SSE connection — consume it, don't reconnect per token. Don't re-`/models` on every turn; the catalog is stable (cache it).

## Decision tree — pick a reference

| The user wants to… | Read |
|---|---|
| understand the task-alias families and pick the right one (incl. the PII lane) | [references/pick-an-alias.md](references/pick-an-alias.md) |
| send a completion cheaply — cap cost, cache, fall back, read cost back | [references/cost-aware-completion.md](references/cost-aware-completion.md) |
| get strict JSON (JSON mode / schema) or call tools/functions through the gateway | [references/structured-output-and-tools.md](references/structured-output-and-tools.md) |
| read how much was spent — usage, per-call cost, traces, p95 latency | [references/read-usage-and-traces.md](references/read-usage-and-traces.md) |
| stream tokens as they generate — or watch *job* events (not completion tokens) | [references/stream-and-events.md](references/stream-and-events.md) |
| see how this compares to OpenRouter / LiteLLM / Portkey | [references/competitor-landscape.md](references/competitor-landscape.md) |
| know which CLI/MCP surfaces are MISSING (and the HTTP workaround) | [references/gaps.md](references/gaps.md) |

## Surface (quick map)

All on `https://spideriq.ai`. Gateway core is `/api/gate/v1` (OpenAI-compatible, no aliases prefix); brand analytics is `/api/v1/brands/{brand_id}/gate/*`.

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| Send a completion | `POST /api/gate/v1/chat/completions` | `gate_chat` *(now forwards cost-cap/JSON/tools)* | `spideriq gate chat` |
| List models (+ pricing, context window) | `GET /api/gate/v1/models` | `gate_models` | `spideriq gate models` |
| List task aliases (+ model chains) | `GET /api/gate/v1/aliases` | `gate_aliases` | `spideriq gate aliases` |
| Gateway health | `GET /api/gate/v1/health` | `gate_health` | `spideriq gate health` |
| Read usage / spend | `GET /api/v1/brands/{brand_id}/gate/usage?days=` | `gate_usage` | `spideriq gate usage -b <brand>` |
| List / inspect traces | `GET …/gate/traces` · `…/traces/{id}` · `…/traces/stats/summary` | `gate_traces` / `gate_trace_detail` / `gate_trace_stats` | — |
| Brand stats / agents / providers | `…/gate/stats` · `/agents` · `/providers` | `gate_stats` / `gate_agents` / `gate_providers` | — |
| Images / TTS / STT / embeddings | `POST /api/gate/v1/{images/generations,audio/speech,audio/transcriptions,embeddings}` | — *(gap 4)* | — *(gap 4)* |

> **CLI + MCP now cover the consumer core** (chat / models / aliases / usage / health, ≥ cli@1.25.0 /
> mcp@1.31.0), and `gate_chat` forwards the cost-cap / JSON / tool-calling controls. Still HTTP-only:
> token-by-token **streaming** and the **multimodal** endpoints (images/TTS/STT/embeddings — gap 4).
> See [references/gaps.md](references/gaps.md).

## Methods (native tool calls — from client/schema.yaml)

| Method | Does | Reference |
|---|---|---|
| `chat` | send a chat completion (task alias or model id) | [references/cost-aware-completion.md](references/cost-aware-completion.md) |
| `listModels` | list models with provider, context window, pricing | [references/pick-an-alias.md](references/pick-an-alias.md) |
| `listAliases` | list task aliases with their fallback chains + usage | [references/pick-an-alias.md](references/pick-an-alias.md) |
| `health` | gateway liveness | [references/stream-and-events.md](references/stream-and-events.md) |

The envelope contract (`guidance:` per method — `use`/`next`/`warn`/`telemetry_signal_default`, plus skill-level `intent_aliases`) lives in [client/schema.yaml](client/schema.yaml). Brand-analytics reads (usage/traces) are served under a different root (`/api/v1/brands/{brand_id}/gate`) and are exposed as the `gate_usage`/`gate_traces`/… MCP tools — see [references/read-usage-and-traces.md](references/read-usage-and-traces.md).

## References (loaded on demand)

- **[references/pick-an-alias.md](references/pick-an-alias.md)** — the two alias families (`spideriq/*` worker, `agent/*` live-agent), how to choose, the PII lane. **Read before your first call.**
- **[references/cost-aware-completion.md](references/cost-aware-completion.md)** — `max_cost_usd`, `cache_enabled`, `fallback_models`, and reading `cost_usd` back. WRONG→RIGHT.
- **[references/structured-output-and-tools.md](references/structured-output-and-tools.md)** — `response_format` (json_object/json_schema) + `tools`/`tool_choice`. WRONG→RIGHT.
- **[references/read-usage-and-traces.md](references/read-usage-and-traces.md)** — usage by `brand_id`, per-call cost, trace list/detail/stats.
- **[references/stream-and-events.md](references/stream-and-events.md)** — `stream: true` SSE framing + the difference vs the `events-stream` job-event skill.
- **[references/competitor-landscape.md](references/competitor-landscape.md)** — OpenRouter / LiteLLM / Portkey mapping (cited).
- **[references/gaps.md](references/gaps.md)** — CLI/MCP gaps the skill needs but the tooling lacks (REQUIRED reading before you reach for a CLI command that doesn't exist).

## See also

- `learnings/` — `no-pii-on-free-tier` (the HARD-GATE's why), `cost-is-in-spidergate-metadata`, `mcp-gate-chat-is-text-only`. Starting points, not ground truth — verify against current code.
- **Sibling skills in this package:** `spidergate-manager` (administer the key pool — add provider keys, health, billing) and `events-stream` (subscribe to *job* lifecycle events). This skill is the consumer of the gateway; those manage it.
