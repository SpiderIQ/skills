# `unknown` is not a success — the fourth outcome state

## What happened

The gateway's usage surface used to report a three-way picture that an agent naturally read
as "success vs failure". It was wrong in a way no error rate could reveal: the alias
`agent/chat` reported a **0.1% error rate** while **returning nothing at all on 62.2% of
requests**. Every one of those calls was a `200`. A hollow answer is not an error, so
nothing in the old split could see it.

The rebuild replaced that with four **mutually exclusive** states that sum to `total`:

```
   delivered   the model returned visible content
   hollow      a 200 that carried no content            <- invisible to an error rate
   failed      a real error
   unknown     the row predates the output_chars column <- WE CANNOT TELL
```

## The trap

`unknown` is the one an agent gets wrong, because three of the four names describe an
outcome and the fourth describes **our own inability to measure**. Folding it into
`delivered` — the reflex, since it "wasn't an error" — manufactures a false all-clear over
exactly the rows where we have the least information.

Two more mistakes live on the same JSON block:

- **`truncated` and `tool_call_turns` are annotations, not states.** They overlap the four.
  Summing all six double-counts. A tool-call turn returns zero visible characters *by
  construction* and is **delivered**, not hollow.
- **Trustworthiness is dated.** `outcome.measurable_from` says when the split became
  meaningful (`2026-08-13` at time of writing) and `window_predates_measurement` says
  whether your window reaches before it. When it does, `delivered_rate` is computed over
  the *classifiable* rows only, so the percentage does not mean what it appears to.

## What to do

- Report the four states separately, or report `delivered_rate` **with** the
  `window_predates_measurement` caveat attached. Never one without the other.
- **Read `measurable_from` from the response.** Do not hard-code the date — it is a server
  constant that will move, and a brief that quoted it from memory already got it wrong once
  (`2026-08-10` vs the shipped `2026-08-13`).
- Treat `measured: false` as "nothing was classified", not as a pass and not as 0%.
- The field is **`measurable_from`, nested inside `outcome`** — `outcome_measurable_from`
  is not a name that exists anywhere in the codebase.

## Why it generalises

This is the same shape as the sibling traps on this surface: `by_provider` is a wire prefix
rather than a provider, `cost_avoided` is a counterfactual rather than an invoice, and
`gate_capacity`'s `suggested_keys` is `null` on a refusing verdict. In each case a field
*looks* like the answer to the obvious question and is actually the answer to a narrower
one. The habit that protects you is reading the qualifier field the payload ships next to
the number — `measurable_from`, `state`, `traffic_scope`, `limit_source`, `verdict` — before
quoting the number itself.
