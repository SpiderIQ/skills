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

Filters compose: `--provider`, `--search`, `--tag`, `--configured-only`,
`--free-only`, `--include-hidden`, `--limit`, `--offset`.

## One model in full

```
spideriq gate catalog get openai/gpt-4o-mini
# GET /api/gate/v1/catalog/models/openai/gpt-4o-mini
```

Returns spec + authored copy + benchmarks + per-provider pricing + links + evals
aggregate, each sourced field with a `provenance` block `{source, url,
retrieved_at, attribution}`.

## Gotchas

- **`model_id` keeps its slash.** A raw `provider/model` id (`openai/gpt-4o-mini`)
  is passed whole — the slash is part of the id, not a path separator you split on.
- **Every array is JSON, not a string.** `capabilities`, `benchmarks`,
  `per_provider`, `links`, `evals` come back as JSON arrays — don't string-parse.
- **Provenance is required reading for benchmarks.** A benchmark number without a
  `provenance.source` is authored/estimated; cite the source when you surface it
  (e.g. `Source: llm-stats.com`).
- **`configured_only=true`** limits to models the Router can actually serve today —
  use it when the next step is to pin + call the model.

## Verify

`listCatalog(fields=capabilities,pricing)` returns rows narrowed to identity +
those two sections; `capabilities` is a JSON array (e.g. `["chat","vision",
"function_calling"]`), and a `provider/model` `getModel` returns 200 with a full
record (404 for an unknown id).
