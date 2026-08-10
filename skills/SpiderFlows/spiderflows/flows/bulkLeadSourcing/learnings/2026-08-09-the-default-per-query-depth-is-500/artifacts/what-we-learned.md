# Six searches is three thousand records

**Starting point, not ground truth — verify against current code.**

## The surprise

You write a body that looks modest:

```json
{ "queries": ["restaurants", "cafes"],
  "geo": [{"label": "Atlanta…"}, {"label": "Savannah…"}, {"label": "Macon…"}] }
```

Two terms, three cities. Six searches. That is the number in your head, because
it is the number you typed.

The estimate comes back at **3,000 records**.

## Where the 500 comes from

`limits.max_records_per_query` was omitted, so it fell back to
`BULK_DEFAULT_RECORDS_PER_QUERY = 500`:

```
expanded_queries  = 2 × 3        = 6
per_query         = 500            ← the default you didn't set
estimated_records = 6 × 500      = 3,000
```

That default is not arbitrary and it is not conservative-by-design — it is set to
match what the Outscraper adapter *actually sends*, precisely so that an omitted
limit cannot make the estimate look cheaper than the run will be. The estimate is
an upper bound on purpose: a guard sized on "what usually comes back" fails on
the one run that comes back full.

## Why it bites

The two numbers live in different units and only one of them is on screen:

```
what you wrote   →  6 searches      ← feels like the size of the run
what you buy     →  3,000 records   ← is the size of the run
what guards it   →  25,000/job ceiling, and the 24h spend cap
```

At 25,000 records per job by default, the ceiling does not stop this — it stops
runs about eight times bigger. So a mis-sized run sails through the guard and
bills.

## What to do

- **Always set `limits.max_records_per_query`** unless the user genuinely wants
  500-deep results per search.
- **Set `limits.max_total_records`** when the user gave you a budget — it clamps
  the whole job regardless of how the cross product expands.
- **Quote records to the user, never searches.** "Up to 3,000 records" is the
  thing they are approving; "6 searches" is not.
- Read `estimated_records` back out of the 202 and check it against what you
  told them before you walk away from the run.
