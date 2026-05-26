# What this worker does NOT return: officers, rich US data, free financials

**Starting point, not ground truth — verify against current code.**

## The surprise

The result schema *has* fields for officers and financials, and the IDAP
`company_registry` type has columns for them — so it's easy to promise a user "the
directors" or "the revenue". But the live worker hard-codes or omits several of
these. Promising a field the worker never fills is the classic
read-the-schema-not-the-worker mistake.

## `officers` is ALWAYS empty

Both `search` and `lookup` set `"officers": []` unconditionally — the worker never
calls the registry's officers/appointments endpoint. The IDAP `company_registry`
table has an `officers` column, but this standalone flow never populates it.
**Never tell the user you can return directors/officers from this flow.** (Officers
would require a separate Companies House appointments call that isn't implemented
here.)

## US records are thin

US (SEC EDGAR) results carry far less than UK:
- `status` is **hard-coded `"active"`** — it is NOT the real company status.
- `incorporation_date` / `dissolution_date` are **null**.
- `search` US records have **no address** at all (only `name` + CIK + status);
  `lookup` US records have a business address but no dates.
- US coverage is essentially **SEC-filing (public) companies** — private US
  companies won't be found.

UK (Companies House) records are the rich ones: real status, structured address,
incorporation date, SIC codes, legal form.

## Financials are UK-only, mostly paid, and often partial

- Only on a **UK `lookup`** with `include_financials:true` (ignored on US, absent
  from `search`).
- The live worker has **two** real modes: `url_only` (free, returns the
  accounts-PDF URL only) and OCR (`auto`/`ocr`, **~$0.05** via Mistral). `ixbrl` and
  `regex` are **accepted but coerced to `auto`** — there is no free figure-extraction
  tier in this worker.
- Figures (`revenue`, `net_income`, `total_assets`, `total_liabilities`,
  `net_assets`, `employees`, `fiscal_year_end`) are **GBP** and can be **null even on
  success**: small/micro filings (AA01/AA02) omit revenue/P&L — only "Full Accounts"
  carry them. The worker also needs an `AA*` accounts filing with a document link, or
  `financials` is null.

## What to do

1. **Don't promise officers.** If the user needs directors, say this flow doesn't
   return them.
2. **Set expectations for US**: name, CIK, address (lookup only), no real status, no
   dates, public companies only.
3. **Only enable `include_financials` for UK companies that need figures** — it's the
   only paid path (~$0.05), is ignored on US, and may still return null figures for
   small/micro filings. Use `url_only` if the user just wants the accounts PDF.
4. Read what the mode actually produced (see results-shape.md) before telling the
   user a field is "missing" — some fields are *never* populated, not missing.
