## spidergate-manager

The SpiderGate V2 LLM gateway surface. 11 tools covering chat completions, model discovery, usage analytics, trace inspection, and provider status.

### What this skill does

- **`chat_completion`** — OpenAI-compatible chat completion. Supports streaming and non-streaming, function-calling, and vision inputs. Pass `model="spideriq/<task-alias>"` to use task-based routing instead of picking a specific model.
- **Task aliases** — Pre-defined routing buckets: `coding`, `extraction`, `creative`, `research`, `planning`, `tool-use`, `classification`, `summarization`, `translation`, `vision`, `free`, `fast`, `chat`, `lead-analysis`. SpiderGate selects from a curated pool of providers ordered by cost, latency, and recency of failures.
- **Models** — `list_models` returns the 15+ available models with provider, context window, and pricing. `get_model_info` returns capability flags (function calling, vision, JSON mode).
- **Usage** — `get_usage` over a time range, broken down by model, task alias, and brand.
- **Traces** — `list_traces` (filterable by status, agent ID, time range), `get_trace` returns the full request/response with span waterfall (LangFuse backed, PostgreSQL fallback when LangFuse is unreachable).
- **Providers** — `list_providers`, `provider_status` for live capacity / cooldown state.

### Typical workflows

- **Routine completion** — agent calls `chat_completion(model="spideriq/coding", messages=[...])`. SpiderGate routes to the best available model in the coding pool.
- **Cost audit** — agent reads `get_usage(start, end, group_by="task")` to see which task aliases are driving spend.
- **Debugging a slow request** — agent looks up the trace by ID, inspects the span waterfall to find the slow step (model call vs tool call vs cache lookup).

### Why use this instead of direct provider APIs?

- One auth model, one error format
- Automatic fallbacks (3 retries, 60s cooldown on failed deployments)
- Cost attribution per-brand without managing per-brand provider keys
- Observability without instrumenting every agent
