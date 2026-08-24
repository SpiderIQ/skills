# Building a filter AST — the agent IS the natural-language layer

There is no natural-language filter box in the dashboard. It was dropped
deliberately (owner, 2026-08-16) because the agent is the better place for it:
you translate the user's sentence into a validated AST and post that.

Your job is **translation**, not parsing tricks. The server tells you the entire
vocabulary; do not invent any of it.

## Step 1 — read the catalogue. Always. First.

```bash
spideriq bulk-source fields
```
MCP: `list_bulk_corpus_fields`.

One response carries everything:

| key | what it gives you |
|---|---|
| `fields[]` | every askable field: `key`, `type`, `label`, and its **own** `operators` list |
| `ast.operators_by_type` | which operators each field TYPE allows |
| `ast.valueless_operators` | `is_empty` / `is_not_empty` — these take **no** `value` |
| `ast.list_operators` | these take an **array** |
| `ast.operator_aliases` | `">="`, `"gte"`, `"in"` — all understood |
| `ast.error_codes` | the 14 refusals, so you can branch instead of guessing |
| `ast.example` | a worked tree |
| `limits` | 20 conditions · depth 3 · 5 groups · 100 values per list |
| `presets` | four ready-made filters — **prefer these** |

**A field `key` is a catalogue lookup, not a column name.** `business.city`
resolves; `city`, `cities`, `b.city` and `city; DROP TABLE x` are all the same
answer: `unknown_field`, 422. There is nothing to be clever about, and no
sanitisation to defeat, because an unlisted key never reaches SQL at all.

## Step 2 — prefer a preset when one fits

The four presets cover most of what people actually ask:

| user says | preset |
|---|---|
| "we never crawled these" | `never_crawled` |
| "the ones with no email" | `no_email` |
| "found an email but never checked it" | `email_unverified` |
| "never published to VayaPin" | `no_pin` |

They are server-authored, so a preset **cannot** disagree with the validator.
Copy its `filter` and edit it; that is what they are for.

## Step 3 — the shape

A **group** is `{op, conditions}`. A **condition** is `{field, operator, value}`.
Groups nest inside groups, freely, to depth 3.

```json
{
  "op": "and",
  "conditions": [
    { "field": "has.website",   "operator": "is_not_empty" },
    { "field": "has.email",     "operator": "is_empty" },
    { "op": "or", "conditions": [
      { "field": "business.city", "operator": "is_any_of", "value": ["Berlin", "Hamburg"] },
      { "field": "business.city", "operator": "starts_with", "value": "Mün" }
    ]}
  ]
}
```

Reads as: *has a website, has no email yet, and is in Berlin or Hamburg (or a
city starting "Mün")*.

## Step 4 — get the spellings right, from the data

If the user names a city, category or status, ask what the corpus actually
holds — do not guess between `Restaurant` and `restaurants`:

```bash
spideriq bulk-source values business.city --prefix Ber
```

Only fields the catalogue marks enumerable answer this (they carry a
`values_endpoint`). A free-text field returns a 422 saying so, by design.

## The refusals, and what each one means you did

Every one is client-fixable and names the offending field.

| code | you did this |
|---|---|
| `unknown_field` | invented a key, or used a column name |
| `operator_not_allowed` | used an operator the field's **type** does not carry — e.g. `gt` on a city |
| `unexpected_value` | sent a `value` with `is_empty` / `is_not_empty` |
| `missing_value` | omitted `value` on an operator that needs one |
| `invalid_value` | wrong shape — a date that is not ISO-8601, a non-uuid for a uuid field |
| `list_too_long` | over 100 entries in an `is_any_of` |
| `too_many_conditions` / `too_deep` / `too_many_groups` | over the structural ceiling |
| `value_too_long` | a single text value over 512 chars |

⚠️ `unexpected_value` exists precisely because the alternative is worse. An
ignored extra is how "is_empty with a value" quietly starts meaning two things.

## Step 5 — size it before you save it

```bash
spideriq bulk-source count --stages spidersite,spiderverify --filter-file ./f.json
```

Free, repeatable, writes nothing. Iterate here. Then read
[run-internal.md](run-internal.md) — and read
[eligible-not-matched.md](eligible-not-matched.md) before you quote a number to
anyone.

## Put the AST in a FILE

`--filter-file` takes a path, and that is not a convenience. A JSON tree quoted
into a shell argument is one escape away from a *different, still-valid* filter —
which fails as a wrong selection rather than as an error.
