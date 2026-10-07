# Compare a shortlist — the enriched catalog

`listCatalog` returns the full enriched rows; `getModel` returns one. Use `fields=`
to pull only the sections you need — the default payload is large.

## Narrow with `fields=`

Recognised sections: `capabilities, context, max_output, pricing, tier,
descriptions, tags, aliases, per_provider, benchmarks, links, evals`. Unknown
tokens are ignored.

```
# concrete-model selection — capabilities + price + per-provider + eval scores
spideriq gate catalog list --fields capabilities,pricing,per_provider,evals --limit 50
# GET /api/gate/v1/catalog/models?fields=capabilities,pricing,per_provider,evals
```

Whatever you pass, every row keeps `id`, `provider`, `model_id`, `spidergate_id`,
`display_name`, `owned_by`, `servable` and `call_as`.

Filters compose: `--provider`, `--search`, `--tag`, `--configured-only`,
`--free-only`, `--include-hidden`, `--limit`, `--offset`.

## Call a model: send its `call_as`

Every row carries `call_as`: the exact `model` string to send for that row right
now, or `null`.

- **To call a model from the catalog, send its `call_as`** as `model` on a
  completion.
- **If `call_as` is `null`, the model cannot be called through the gateway now.**
  Pick another row, or use a task alias.
- Do not send a row's `id` or `model_id` because a filter returned the row.

```json
{ "total": 3, "count": 3, "fields": ["pricing"],
  "models": [
    { "id": "gpt-6-sol-codex", "provider": "codex", "model_id": "gpt-6-sol",
      "spidergate_id": "gpt-6-sol-codex", "display_name": "gpt-6-sol", "owned_by": "",
      "pricing_input": 0.0, "pricing_output": 0.0,
      "servable": false, "call_as": "codex/gpt-6-sol" },
    { "id": "lease-model-anthropic", "provider": "anthropic", "model_id": "lease-model",
      "spidergate_id": "lease-model-anthropic", "display_name": "lease-model", "owned_by": "",
      "pricing_input": 0.0, "pricing_output": 0.0,
      "servable": false, "call_as": null },
    { "id": "llama-x-groq", "provider": "groq", "model_id": "llama-x",
      "spidergate_id": "llama-x-groq", "display_name": "llama-x", "owned_by": "",
      "pricing_input": 0.0, "pricing_output": 0.0,
      "servable": true, "call_as": "llama-x-groq" } ] }
```

These three rows are the service's own test fixtures run through the catalog
read with `fields=pricing`. The names and prices are synthetic; the shape and the
`call_as` values are exact.

| The row | `servable` | `call_as` |
|---|---|---|
| its provider has a healthy pooled key | `true` | the row's own `id` |
| Codex, while the gateway holds a pooled Codex seat | `false` | `codex/<model_id>` |
| Codex, with no seat | `false` | `null` |
| a lease-only provider (its logins are lent to the owner's own CLI; the gateway never calls the model) | `false` | `null`, always |
| anything else | `false` | `null` |

**Why the `id` is not enough.** The Codex row above has `id` `gpt-6-sol-codex` and
`model_id` `gpt-6-sol`. Both are refused as `model`. Only `codex/gpt-6-sol` is
served, and that is what `call_as` holds.

**What `call_as` does not tell you.**

- It is per provider, not per model and not per key. A held Codex seat does not
  prove that the account still serves a given model, so the call can still fail
  at the provider.
- It is not a check of your own credential's `allowed_models`.
- It is read from one gateway process's in-memory key state on each request. The
  gateway runs several processes, so `call_as` can differ between two reads for a
  moment. Read it close to the call. Cache the rest of the row; do not cache
  `call_as`.
- It is not a filter. No parameter selects on it.

## What each filter returns

| Filter | Returns | What it does not tell you |
|---|---|---|
| `configured_only=true` | Rows whose stored `is_configured` flag is true. A saved flag, not a live check. | Whether a row can be called. It can return a Codex row, whose `id` is refused, and a row with `call_as: null`. |
| `servable_only=true` | Rows whose provider has a healthy pooled key right now. | Anything about Codex. It never returns a Codex row, even one whose `call_as` is set. |
| `free_only=true` | Rows flagged free-tier. | Whether a row can be called. |

`servable_only` is a query parameter of the HTTP route. `listCatalog`,
`gate_catalog_list` and `spideriq gate catalog list` do not declare it. You do not
need it: read `call_as` on the rows you get.

## One model in full

```
spideriq gate catalog get openai/gpt-4o-mini
# GET /api/gate/v1/catalog/models/openai/gpt-4o-mini
```

Returns spec + authored copy + benchmarks + per-provider pricing + links + evals
aggregate, each sourced field with a `provenance` block `{source, url,
retrieved_at, attribution}`. The record carries `call_as` too. The id you look a
record up by (a `spidergate_id` or a raw `provider/model`) is a lookup key; what
you send as `model` is the record's `call_as`.

## Gotchas

- **`model_id` keeps its slash.** A raw `provider/model` id (`openai/gpt-4o-mini`)
  is passed whole — the slash is part of the id, not a path separator you split on.
- **Every array is JSON, not a string.** `capabilities`, `benchmarks`,
  `per_provider`, `links`, `evals` come back as JSON arrays — don't string-parse.
- **Provenance is required reading for benchmarks.** A benchmark number without a
  `provenance.source` is authored/estimated; cite the source when you surface it
  (e.g. `Source: llm-stats.com`).
- **`configured_only=true` is not "callable".** It selects on a saved flag. Read
  `call_as` on each row before you call it.
- **Leaderboard rows carry no `call_as`.** They carry `id`. Read the row with
  `getModel(id)` and send that record's `call_as`.

## Verify

`listCatalog(fields=capabilities,pricing)` returns rows narrowed to identity +
those two sections; `capabilities` is a JSON array (e.g. `["chat","vision",
"function_calling"]`), every row has a `call_as` key holding a string or `null`,
and a `provider/model` `getModel` returns 200 with a full record (404 for an
unknown id).
