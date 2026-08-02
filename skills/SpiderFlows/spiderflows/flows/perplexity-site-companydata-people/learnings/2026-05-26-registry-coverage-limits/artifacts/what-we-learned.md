# Registry coverage is UK / US / EU only — and UK financials cost money

**Starting point, not ground truth — verify against current code.**

## The surprise

The registry stage feels like it should work for any company anywhere. It
doesn't — it reads three specific **free public registries**, and a company
outside them legitimately returns an empty `registry`.

## What's covered

| Jurisdiction | Source | What you get |
|---|---|---|
| UK | Companies House | filed name, registration number, status, address; financials (paid, see below) |
| US | SEC EDGAR | filings for SEC-registered (mostly public) companies |
| EU | VIES | VAT-number validation + the registered entity behind it |

A private company outside those — say a small DACH GmbH with no EU VAT
registration, or a private company in APAC/LATAM — returns no filing. **That is a
correct result, not a failure.** Don't tell the user "the lookup broke"; tell them
the company isn't in a public registry we can read.

## UK financials cost money and can be incomplete

- `include_financials` is **UK-only** and costs **~$0.05/company** (Mistral OCR of
  the filed accounts PDF). It's auto-enabled when `country_code` is `GB`.
- Even when it resolves, **small/micro company filings (AA01/AA02) omit revenue
  and P&L** — only "Full Accounts" carry turnover/profit. So financial fields can
  be null on a successful lookup. Set expectations accordingly.

## Rule of thumb

- Set `country_code` so the registry lookup is constrained to the right
  jurisdiction (and so UK gets financials).
- For a non-UK/US/EU company, expect an empty registry and consider disabling the
  stage (`spidercompanydata.enabled=false`) to skip the wasted lookup.
- Treat financials as best-effort for UK only; reconcile figures against the
  source filing for anything load-bearing.
