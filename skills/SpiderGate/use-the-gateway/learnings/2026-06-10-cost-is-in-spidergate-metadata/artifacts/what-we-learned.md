# Cost lives in spidergate_metadata, not usage

## The trap

OpenAI responses carry a `usage` block, so agents reach for `response.usage` when they
want "how much did that cost." But `usage` is **token counts only**:
`prompt_tokens`, `completion_tokens`, `total_tokens`. There is no dollar figure in it.
Multiplying tokens by a guessed rate is how cost dashboards drift.

## Where the dollars actually are

SpiderGate adds a `spidergate_metadata` block to every chat completion response:

```json
"spidergate_metadata": {
  "provider": "groq",
  "provider_model": "llama-3.1-8b-instant",
  "latency_ms": 640,
  "cost_usd": 0.000004,
  "cache_hit": false,
  "fallback_used": false,
  "original_model": null
}
```

`cost_usd` is the real, provider-priced dollar cost of **this one call**, computed on
the model that actually served (`provider_model`) — which can differ from the alias's
slot-0 when a fallback fired (`fallback_used: true`, `original_model` shows what you asked
for). A cache hit sets `cache_hit: true` and `cost_usd: 0`.

## How to apply

- For the cost of a call you just made: read `response.spidergate_metadata.cost_usd`. Free,
  immediate, exact. Don't poll the aggregate `/usage` endpoint for it (that's batched and
  brand-keyed).
- To know what actually answered (for quality/debugging): read `provider_model`, not the
  `model` you sent.
- For account-level rollups across many calls: that's the brand-scoped
  `GET /api/v1/brands/{brand_id}/gate/usage` surface — a different, aggregate view.

> Verify the field shape against `app/api/v1/gate/schemas.py:SpiderGateMetadata` — it's the
> source of truth and may gain fields over time.
