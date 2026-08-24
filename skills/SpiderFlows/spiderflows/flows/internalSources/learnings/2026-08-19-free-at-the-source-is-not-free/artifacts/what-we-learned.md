# An internal run's money fields all read zero, and the run is not free

## What happened

The `internal` adapter registers with `source_is_free=True`. It is a real,
knowable zero — nobody is paid for us to read our own corpus — so the estimate
and the 202 come back with every money field at `0` or `null`.

That is a true statement about the **source** and a false summary of the **run**.

## Why it misleads

The spend moved, it did not disappear:

```
cost ≈ eligible_leads × (number of enabled stages)
```

A 9,000-lead selection with `spidersite` + `spiderverify` enabled is 18,000 units
of enrichment. Nothing about the empty cost field says so.

## 🔴 The discriminator is NOT `!has_cost`

This is the part that catches people. An **unpriced provider** looks identical to
a free source on every money field: `outscraper` has no unit price configured, so
it also returns `estimated_cost_usd: null` — and it is buying records for real
money. Branching a confirmation screen or an agent's summary on "the cost field
is empty" therefore lumps together:

| | source cost | `estimated_cost_usd` |
|---|---|---|
| `internal` / `csv` / `json` / `sortlist` | genuinely zero | `0` / `null` |
| `outscraper` (unpriced) | **real money** | `null` |

## What to do instead

Branch on **`source_is_free`**, or on what is being enriched. Never on whether
the money field is populated.

When summarising an internal run to a human, say the shape out loud:

> "The leads are yours already, so there's nothing to buy. This will run
> **812 leads × 2 stages** of enrichment."

## See also

- `recipes/internal-vs-buying.md`
- the sibling learning on `eligible_leads` — it is the multiplicand above, and
  quoting `matched_leads` there inflates this number too.
