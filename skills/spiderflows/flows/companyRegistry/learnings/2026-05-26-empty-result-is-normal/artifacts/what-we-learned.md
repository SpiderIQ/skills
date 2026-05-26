# An empty / not-found result is a valid answer — not a failure to retry

**Starting point, not ground truth — verify against current code.**

## The surprise

A registry lookup can complete cleanly (`status: completed`, HTTP `200`) and carry
**no company** — and that is frequently the *correct* answer, not an error. The
public registries only cover certain companies, so "we looked and this company
isn't in a registry we can read" is legitimate. It just doesn't look like a failure
at the HTTP level. (How to *read* that verdict is the
[success-flag learning](../../2026-05-26-success-flag-not-http-status/artifacts/what-we-learned.md);
this one is about what it *means* and what to do.)

## What "empty" looks like, by mode

| Mode | Empty/negative result |
|---|---|
| `search` | `data.success:true`, `data.results: []`, `data.total_results: 0` |
| `lookup` | `data.success:false`, `data.error:"Company not found"` (no `data.data`) — or `"Unsupported country: XX"` for a non-GB/US country |
| `vat` | `data.success:true`, `data.data.valid:false` (genuinely invalid) — or `valid:false` + `error` (couldn't validate) |

## Why it comes back empty

- **Out of coverage** — not a UK/US company (records) or not a VIES country (vat).
  The single most common cause; see the registry-coverage learning.
- **`search` no name match** — `results:[]`. Try a cleaner name, or set/relax
  `country`.
- **`search` upstream API hiccup** — the worker *swallows* a UK/US API error and
  also returns `results:[]` (indistinguishable from "no match" — see the
  success-flag learning).
- **`vat` `valid:false`** — a definitive "this number is invalid".
- **Wrong `lookup` ID/country** — an `identifier`/`country` pair that doesn't
  resolve, or a non-GB/US country (`Unsupported country`).

## What to do

1. **Read the mode's result key and `data.success`/`data.error`** before concluding.
   A `completed` job with no record is the empty case, not a crash.
2. **Don't retry an empty result as a failure.** Re-running the same out-of-coverage
   company returns empty again and wastes the call. The fix is a *different input*
   (a real registry ID, the right `country`, the `EL`/`XI` VAT prefix), not a retry.
   The exception: a `search` that returned empty (could be a swallowed upstream
   error) is worth **one** retry; a `vat` `valid:false`+`error` is worth a retry.
3. **Tell the user the accurate thing.** "Completed — that company isn't in a public
   registry we can read" is correct and useful; "the lookup failed" is not.

## Read-side note

An empty result writes **no IDAP `company_registry` row** — a missing row for an
out-of-coverage company is expected, not a normalization bug. `vat` never writes a
row regardless.
