# Write an answer schema

`research.answer_schema` is a JSON Schema (draft 2020-12). The answer comes back shaped by it,
the job checks the shape, and if the first reply does not fit it makes ONE repair call — which
doubles the answer's cost. A good schema is one the pages can actually fill.

Describe **only the answer**. The job wraps it for you (the model replies
`{"answer": …, "citations": […]}` and the job unwraps it), so `answer` and `citations` never
appear in your schema.

## 1. Trace every item to its page

**WRONG** — facts with no page:

```json
{"type": "object", "properties": {"tiers": {"type": "array", "items": {"type": "object",
  "properties": {"name": {"type": "string"}, "price": {"type": "string"}}}}}}
```

**RIGHT** — a `source_url` on every item, required:

```json
{"type": "object", "required": ["tiers"], "properties": {"tiers": {"type": "array", "items": {
  "type": "object", "required": ["name", "price", "source_url"], "properties": {
    "name": {"type": "string"}, "price": {"type": "string"}, "source_url": {"type": "string"}}}}}}
```

The model is told to copy the exact URL shown for the page it used. Then check
`answer_urls.ungrounded` — a `source_url` that is not a page the job read is listed there.

## 2. Let a fact be absent

**WRONG** — a required string for something the page may not state:

```json
{"type": "object", "required": ["author"], "properties": {"author": {"type": "string"}}}
```

On a page with no declared author the model must either invent a name or break the schema.

**RIGHT** — nullable:

```json
{"type": "object", "required": ["author", "published"], "properties": {
  "author": {"type": ["string", "null"]}, "published": {"type": ["string", "null"]}}}
```

The whole answer may also be `null` — that is the job's way of saying the pages do not answer the
question, and it is never counted as a schema violation.

## 3. Type what the page writes, not what you wish it wrote

**WRONG** — `"price": {"type": "number"}`. Measured on a real pricing page: one tier's price was
"Custom (contact for pricing)" and another's "$9/month (or $7.50/month billed yearly)". A number
field forces a lie or a violation.

**RIGHT** — a string, or a number plus a note:

```json
{"price": {"type": "string"}}
{"price_usd_month": {"type": ["number", "null"]}, "price_note": {"type": "string"}}
```

## 4. Keep references local

**WRONG** — `{"$ref": "https://json.schemastore.org/…"}` → **422** "answer_schema may only use local
$ref values (starting with #)". The job never fetches a schema from the web.

**RIGHT** — define it once under `$defs` and point at it:

```json
{"$defs": {"tier": {"type": "object", "properties": {"name": {"type": "string"}}}},
 "type": "array", "items": {"$ref": "#/$defs/tier"}}
```

## What the API refuses at submit (422, nothing runs)

| You sent | Refused because |
|---|---|
| `answer_schema` that is not a valid draft 2020-12 schema | "answer_schema is not a valid JSON Schema: …" |
| a `$ref` not starting with `#` | only local references |
| a schema over 20,000 characters | size cap |
| a misspelled research key (`answer_shema`, `maxPages`) | the research block refuses unknown keys, so a typo is never silently ignored |
| `max_pages` outside 1–20 · `question` under 3 characters | bounds |
| `mode: "research"` without a `research` block, or a `research` block without `mode: "research"` | they only mean something together |

## Reading the result against the schema

- `answer_schema_valid: true` — the answer has the shape you asked for. Not that it is true: check
  its sources.
- `answer_schema_valid: false` — it still did not fit after the repair call. `answer` holds what the
  model returned anyway and `answer_schema_errors` says where it breaks (e.g.
  `tiers/0/price: 9 is not of type 'string'`). Use the fields that are right; do not treat the rest
  as data.
- `usage.calls: 2` — the first reply did not fit and the repair call fixed it. A schema that often
  costs two calls is usually asking for something the pages do not say in that form.
