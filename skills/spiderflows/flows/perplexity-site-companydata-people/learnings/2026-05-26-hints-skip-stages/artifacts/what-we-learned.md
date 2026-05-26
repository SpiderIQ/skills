# Discovery hints skip a stage — pass what you already know

**Starting point, not ground truth — verify against current code.**

## The surprise

The pipeline starts with a Perplexity web-search to *discover* a company's domain
and LinkedIn URL from its name. That discovery step is the slowest, least-certain
part of the chain — and you can skip parts of it for free by passing what you
already know.

## What each input does

| You pass | Effect |
|---|---|
| `company_name` only | Perplexity searches the web for everything (domain, LinkedIn, description). Works, but it's a guess from a name. |
| `+ city` / `+ country_code` | Perplexity gets a `location_hint` ("Acme in Berlin, DE") → disambiguates same-named companies + constrains the registry lookup. |
| `+ domain` | **Skips** Perplexity domain discovery. The crawl starts on your domain directly — faster + no wrong-domain risk. |
| `+ linkedin_url` | **Skips** Perplexity LinkedIn discovery. SpiderPeople targets that company page directly. |

## Why it matters

- A name-only request makes Perplexity do work you may not need. If a CRM row
  already has the domain, passing it removes a discovery call *and* removes the
  risk that Perplexity picks the wrong "Acme".
- For batch (KYC / list enrichment) this compounds: 50 companies × one skipped
  discovery call each is real time and cost saved. Most CRM/vendor lists already
  carry a domain or LinkedIn URL — use them.

## Rule of thumb

- Always pass `country_code` (and `city` if you have it) — they're free accuracy.
- Pass `domain` and/or `linkedin_url` whenever the source data has them.
- Only the `company_name` is truly required; everything else trades a known value
  for a cheaper, more accurate run.
