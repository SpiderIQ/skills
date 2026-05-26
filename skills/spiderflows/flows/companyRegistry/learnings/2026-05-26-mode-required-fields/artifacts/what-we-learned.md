# The mode decides the required fields — a mismatch is a 422, not an empty result

**Starting point, not ground truth — verify against current code.**

## The surprise

The lookup has one endpoint but three modes, and each mode requires *different*
fields. Get the combination wrong and the payload validator rejects the request
with a `422` **before** the job is queued — you never get a `job_id`, so it's not
a "ran and found nothing" situation, it's "never ran".

## The rules

| `mode` | Must include | If missing |
|---|---|---|
| `search` (default) | `name` | `422` — `'name' is required for search mode` |
| `lookup` | `identifier` **and** `country` | `422` — `'identifier'`/`'country'` required for lookup mode |
| `vat` | `vat_number` (or `identifier` as fallback) | `422` — `'vat_number' or 'identifier' is required for vat mode` |

`lookup` is the one that catches people: it needs **both** the registry ID *and*
the `country`, because the ID is registry-specific (a UK company number and a US
CIK are both just digits — `country` tells the worker which registry to ask).

## Two different failure layers — don't conflate them

The schema validator checks that the required *fields* are present. It does **not**
check the country *value*. So there are two distinct ways a request "fails":

| Layer | When | What you get |
|---|---|---|
| **Schema `422`** (before the job runs) | a required field is missing for the mode | HTTP `422`, **no `job_id`** — it never ran |
| **Worker `success:false`** (after the job runs) | well-formed request, but the worker can't satisfy it — e.g. `lookup` with `country:"DE"` (passes the schema; only GB/US resolve), or "Company not found" | HTTP `200`, `status: completed`, **`data.success:false`** + `data.error` |

Example: `{"mode":"lookup","identifier":"123","country":"DE"}` is **valid to the
schema** (identifier + country both present) → gets a `job_id` → the worker then
returns `success:false, "Unsupported country: DE"`. That is NOT a 422; you only see
it by reading `data.success`. See
[2026-05-26-success-flag-not-http-status/](../../2026-05-26-success-flag-not-http-status/artifacts/what-we-learned.md).

## What to do

1. **Set `mode` explicitly** and supply exactly that mode's required fields. The
   default is `search`, so a request with only an `identifier` and no `mode` is
   treated as a *search* with no `name` → `422`.
2. **Have a name but not an ID? Search first.** Run `search` to get candidate
   records (each carries its `source_id` / `registration_number`), then `lookup`
   the one the user wants by that ID + `country`. You can't `lookup` what you can't
   identify.
3. **A `422` is your payload shape; a `success:false` is the registry.** A 422 means
   a required field was missing (fix the fields, no job ran). A `200` +
   `data.success:false` means the job ran but the lookup couldn't land (wrong
   country, not found, out of coverage).
