# Competitor landscape — OpenRouter · LiteLLM · Portkey

How SpiderGate's consumer surface maps onto the three gateways an agent author is
most likely to already know. The point isn't marketing — it's "you already know this
pattern; here's the SpiderGate name for it." Sources cited at the bottom.

## At a glance

| Capability | OpenRouter | LiteLLM (Router) | Portkey | **SpiderGate** |
|---|---|---|---|---|
| OpenAI-compatible endpoint | ✓ | ✓ | ✓ | ✓ `/api/gate/v1/chat/completions` |
| "route by task," not model | Presets | `model_group` aliases | Configs | **task aliases** `spideriq/<task>` |
| Fallback chain | `models: [...]` array | `fallbacks` list | composable `fallback` targets | alias chain + `spidergate_options.fallback_models` |
| Per-request price ceiling | `provider.max_price` | (per-key budget) | budget limits | **`spidergate_options.max_cost_usd`** |
| Provider steer / ban | `provider.order` / `ignore` | deployment list | load-balance targets | `preferred_providers` / `excluded_providers` |
| Per-call cost back | `usage` (priced on served model) | response cost hook | analytics | **`spidergate_metadata.cost_usd`** |
| Response cache | (no) | (no, app-level) | semantic + simple cache | `spidergate_options.cache_enabled` (exact-match) |
| Per-request observability | generation stats endpoint | callbacks | trace id + dashboard | **traces** (`/gate/traces`, LangFuse-backed) |

## OpenRouter — the closest analogue for "one endpoint, many providers"

- **Fallback** = you pass an array of model ids in priority order; on an error OpenRouter
  tries the next, transparently. SpiderGate bakes that chain into each **task alias**, so
  you send one alias instead of hand-ordering models — and can still extend it with
  `spidergate_options.fallback_models`.
- **Provider routing** = `provider.{sort, order, only, ignore, allow_fallbacks, max_price, …}`.
  SpiderGate's `preferred_providers`/`excluded_providers` are the `order`/`ignore` analogue;
  `max_cost_usd` is the `max_price` analogue but expressed as a whole-request dollar cap.
- **Cost** = "priced using the model that was ultimately used, returned in the `model`
  attribute." SpiderGate prices on the served model too and returns it as
  `spidergate_metadata.provider_model` + `cost_usd`.
- **Presets** = named, reusable config bundles. SpiderGate task aliases are the same idea,
  curated + eval-tested centrally instead of per-account.

## LiteLLM — because it IS our engine

SpiderGate runs **litellm.Router underneath** (least-busy routing, 3 retries, 60 s cooldown).
So LiteLLM concepts map 1:1: `model_group` alias ≈ our task alias, `fallbacks` ≈ the alias
chain, Router strategy ≈ our least-busy. What SpiderGate adds on top: multi-tenant PAT auth,
the analytics/traces surface, the per-request `max_cost_usd` cap, and a curated alias catalog —
you don't run or configure the Router yourself. (We pin `litellm==1.82.6`; never assume
latest-litellm docs apply to behavior you see.)

## Portkey — the closest analogue for cost-governance + traces

- **Configs** = a JSON object (routing/fallback/load-balance) referenced by id. SpiderGate's
  equivalent is the alias + the inline `spidergate_options` block (no separate config object to
  manage).
- **Virtual keys / vault** ≈ SpiderGate's key pool (managed via the `spidergate-manager` skill,
  not this one).
- **Budget limits** ≈ `max_cost_usd` (per request) + the brand's spend tracking.
- **Trace id / observability** ≈ SpiderGate **traces** — find a request, see the span waterfall
  and input/output, read p95 latency + cost ([read-usage-and-traces.md](read-usage-and-traces.md)).

## What none of the three give you that SpiderGate does

The **task-alias families split** (`spideriq/*` cost-biased for workers vs `agent/*`
subscription-biased for live agents) is SpiderGate-specific — it encodes *who the caller is*
into the routing, not just *what the model is*. Plus the **PII/free-tier HARD-GATE** is a
SpiderGate policy: cost-biased aliases route to trainable free-tier providers, so the skill
refuses PII on them. The competitors leave that judgment entirely to you.

## Sources

- OpenRouter — [Provider Routing](https://openrouter.ai/docs/guides/routing/provider-selection),
  [Model Fallbacks](https://openrouter.ai/docs/guides/routing/model-fallbacks),
  [Presets](https://openrouter.ai/docs/guides/features/presets) (provider preference fields incl.
  `order`/`ignore`/`max_price`; "priced on the model ultimately used").
- LiteLLM — [Router docs](https://docs.litellm.ai/docs/routing) (routing strategies, `fallbacks`,
  `model_group` aliases); SpiderGate runs it as the engine (SpiderGate CLAUDE.md / LEARNINGS #16).
- Portkey — [Fallbacks](https://portkey.ai/docs/product/ai-gateway/fallbacks),
  [AI Gateway features](https://portkey.ai/features/ai-gateway) (configs, virtual keys, budget
  limits, trace-id observability, load-balancing).
