# `spidergate_options` caps nothing, and the response has no `spidergate_metadata`

## What this skill used to say

That a completion could carry `spidergate_options` with a per-request cost cap
(`max_cost_usd`), a response cache (`cache_enabled`) and an extra fallback list
(`fallback_models`), and that the response came back with a `spidergate_metadata`
block holding `cost_usd`, `provider_model`, `cache_hit` and `fallback_used`. A
learning in this folder was titled "cost is in spidergate_metadata".

## What the gateway does

- The handler builds the provider request from the OpenAI fields: `model`,
  `messages`, `temperature`, `top_p`, `n`, `max_tokens`, `stop`, the two penalties,
  `logit_bias`, `seed`, `user`, `tools`, `tool_choice`, `response_format`.
  `spidergate_options` is not copied. The fields named above are read nowhere.
- The response is the provider library's own body with the gateway's request id
  written over `id`. No `spidergate_metadata` is added on any path.

The request model declares `spidergate_options` as a free-form object, and the
response model declares an optional `spidergate_metadata`. Both names appear in
the API schema, which is how a text written from the schema came to describe
behaviour the handler never had.

## What it cost

Nothing failed loudly. A call with `max_cost_usd: 0.02` returned `200` and was
billed in full. An agent loop that counted on the cap to stop it had no cap. Code
that read `spidergate_metadata["cost_usd"]` raised `KeyError`; code that used
`.get()` read `None` and reported no cost.

## How to apply

- Bound one call with `max_tokens`. Bound a token with its monthly budget: the
  gateway answers `402 budget_exceeded` once the token's spend reaches it.
- Count calls in your own loop and stop on your own limit.
- Read what served from the response `model` (raw HTTP: also the
  `X-Served-Model-Catalog-Id` header). Read cost from the call's row in the trace
  list, or from the usage read for a period.
- When a text describes a request option, look for the line of the handler that
  reads it. A field in the schema is not a behaviour.
