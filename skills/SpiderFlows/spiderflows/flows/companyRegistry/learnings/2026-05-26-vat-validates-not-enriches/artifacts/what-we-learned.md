# `vat` mode validates a number via VIES — it doesn't enrich a company

**Starting point, not ground truth — verify against current code.**

## The surprise

`vat` mode reads like "look up the company behind this VAT number and tell me
everything". It doesn't. It calls the EU **VIES** SOAP service to answer one
question — *is this VAT number valid?* — and returns the registered entity
name/address that VIES has on file. That's a *validation*, not a company profile:
no officers, no filings, no financials. (For depth, run `lookup`, or the
company-intel chain.)

## Exactly which countries VIES accepts

The VAT prefix must be one of these 28 codes, or you get
`valid:false, error:"Country XX not supported by VIES"`:

```
AT BE BG CY CZ DE DK EE EL ES FI FR HR HU IE IT
LT LU LV MT NL PL PT RO SE SI SK XI
```

Two traps in that list:
- **`EL`, not `GR`** — Greece's VIES code is `EL`. `GR123…` is rejected.
- **`XI`, not `GB`** — post-Brexit, only Northern Ireland (`XI`) is in VIES. A `GB`
  VAT number is **not** validated here.

The number is cleaned before parsing (spaces / dashes / dots stripped, uppercased),
so `DE 123 456 789` and `de-123-456-789` both work. A prefix that isn't two letters,
or a too-short string, is rejected as invalid.

## `valid:false` is two different things — read `error`

| Result | Meaning |
|---|---|
| `valid:false` **with no `error` key** | the number is **genuinely invalid** (VIES said so) |
| `valid:false` **with an `error` key** | validation **couldn't run** — unsupported country, a VIES SOAP fault, or the service being briefly down |

VIES is a known-flaky public service (it intermittently returns malformed XML or is
unavailable). A transient `valid:false`+`error` is **the EU service, not your
input** — retry the same well-formed number after a short delay; don't report it as
invalid.

## A `valid:true` can still have a null name

`company_name` / `company_address` come from VIES only when the member state
returns them — and several EU states return validity **without** the entity name.
So `valid:true` + `company_name:null` is normal; don't treat the null as a failure.

## What to do

1. Use `vat` to **confirm a VAT number and get the entity behind it when available**
   — a yes/no plus (sometimes) a name. Not a company profile.
2. Send the right prefix (`EL` for Greece, `XI` for Northern Ireland, never `GB`).
3. On `valid:false` **with `error`**, retry once or twice with a short delay before
   concluding anything; on `valid:false` **without `error`**, it's genuinely invalid.
4. Need depth? Switch tools — `lookup` for a UK/US filing, or the company-intel
   chain for the full account brief.

## Read-side note

`vat` results do **not** normalize into IDAP `company_registry` (the validation dict
has no `name`/`source_id`, so the normalizer skips it). Read VAT only via
`/jobs/{id}/results` → `data.data`.
