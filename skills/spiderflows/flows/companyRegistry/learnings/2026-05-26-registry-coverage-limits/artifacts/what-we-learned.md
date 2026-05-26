# Coverage: company records are UK + US only; the EU is VAT-validation only

**Starting point, not ground truth — verify against current code.**

## The surprise

The flow card advertises "UK Companies House, US SEC, EU VIES, DE/FR/NL/ES/IL".
The **live worker is narrower than that**, and the gap costs you a wasted (and
sometimes confusing) run if you don't know it:

| Mode | Registries the worker *actually* queries |
|---|---|
| `search` | UK Companies House + US SEC EDGAR. `country=GB`→UK, `US`→US, **omitted→both**, anything else → queries nothing (empty list). |
| `lookup` | UK **or** US. `GB`→Companies House, `US`→SEC EDGAR, **any other country → `success:false, "Unsupported country: XX"`**. |
| `vat` | EU VIES validation only (28 member-state prefixes). |

So: **company *records* (filings, numbers, addresses) come from UK + US only.** The
**EU is reachable only through `vat`**, which is a VAT-number *validation* (valid +
sometimes the entity name), not a full filing. There is **no DE/FR/NL/ES/IL
company-record lookup** in this worker — the normalization layer recognises those
source tags (`_VALID_SOURCES`), and the flow card declares them, but the
search/lookup scripts have no adapter that emits them. Don't promise a German or
French company filing from this standalone flow.

## Why the flow card over-claims

The IDAP `company_registry` schema and the CRM normalizer were built to *accept*
DE/FR/NL/ES/IL source tags (forward-compatible), and the flow card mirrors that
ambition. But the deployed `spidercompanydata_search.py` only branches on `GB`/`US`,
and `spidercompanydata_lookup.py` rejects everything except `GB`/`US`. Treat the
extended list as roadmap, not capability — verify live before relying on it.

## US coverage is essentially public companies, and the records are thin

US search queries SEC EDGAR full-text (10-K/10-Q) — so it finds **SEC-filing
(mostly public) companies**, not private ones. US records carry only name + CIK +
a hardcoded `status:"active"` (no real status, no incorporation date, sparse
address). UK records are far richer.

## UK financials cost money, have only two real modes, and can be incomplete

- `include_financials` is **UK `lookup` only** (ignored on US) and the live worker
  has just two outcomes: `url_only` (free — returns the accounts-PDF URL) or OCR
  (`auto`/`ocr`, **~$0.05/company** via Mistral). `ixbrl`/`regex` are **accepted but
  coerced to `auto`** — the legacy free iXBRL/regex tiers are not in this worker.
- Even on success, **small/micro filings (AA01/AA02) omit revenue and P&L** — only
  "Full Accounts" carry turnover/profit, so figures can be null.

## Rule of thumb

- Records: `GB`/`US` only. EU: `vat` only. Pick the country deliberately —
  `lookup` with a non-GB/US country is a guaranteed `success:false`.
- Don't set `include_financials` unless the user needs UK figures; it's the only
  paid path and is ignored on US.
- Reconcile any load-bearing financial figure against the source filing.
