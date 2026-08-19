# Recipe: source marketing agencies from Sortlist

Sortlist is a public B2B directory of marketing, design and development
agencies. It is a **source** in the same slot as `outscraper` and `apify` —
same endpoint, same buy order, same fan-out, same result envelope — with two
differences that change how you compose the request:

```
outscraper / apify   you type a SEARCH TERM      → a search runs      → you pay per record
sortlist             you pick from ITS CATALOGUE → a listing is read  → nothing is bought
```

Read [run-bulk.md](run-bulk.md) for the shared mechanics. This page covers only
what is specific to Sortlist.

## Submit

```bash
curl -X POST "https://spideriq.ai/api/v1/bulk-lead-sourcing/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "source": {
      "provider": "sortlist",
      "source_kind": "sortlist_agency",
      "queries": ["seo", "i/branding"],
      "geo": [{ "label": "united-states-us" }, { "label": "germany-de" }],
      "limits": { "max_records_per_query": 200 }
    },
    "settings": {
      "workflow": {
        "spidersite":   { "enabled": true },
        "spiderverify": { "enabled": true },
        "vayapin":      { "enabled": false },
        "smartlead":    { "enabled": false }
      }
    }
  }'
```

`queries x geo` expands the same way it does for any source: two services across
two countries is **four listings**, not two.

## 🔴 The queries are catalogue slugs, and a wrong one is accepted then kills the run

There is no free-text search. Every value in `queries` and every `geo[].label`
must be a slug Sortlist itself publishes.

**The submit endpoint does not check this.** An off-catalogue slug returns a
perfectly normal `202` with a `job_id`, and the run dies seconds later in the
worker:

```
POST … "queries": ["not-a-real-sortlist-service"]     →  202  job accepted
GET  /jobs/{job_id}/status  (~5s later)               →  "status": "failed"
     error_message: ValidationError … service 'not-a-real-sortlist-service'
                    is not in Sortlist's catalogue
```

Nothing is contacted, nothing is spent, nothing fans out — but the run is dead
and the 202 gave you no warning. **Pick from the vocabulary; never guess a
slug.** If you cannot see the vocabulary from your surface, prefer a slug you
have used before over one you inferred from the user's wording — "SEO" is
`seo`, but "web design" is not `web-design` in every catalogue.

### The selection vocabulary

| Axis | Count | Form |
|---|---|---|
| Services | **109** | bare slug — `seo`, `web-design`, `content-marketing` |
| Industries | **26** | `i/` prefix — `i/advertising`, `i/app-development` |
| Countries | **21** | slug carries its own ISO code — `united-states-us`, `germany-de` |

Services and industries go in the **same** `queries` array — **135 options
between them**, which is why "135 services" is the wrong way to say it.

They are not interchangeable, and several slugs exist on **both** axes:
`branding`, `content-marketing` and `design` are each a service *and* an
industry, and `/s/design` and `/i/design` are different Sortlist pages listing
different agencies. That is what the `i/` prefix is for — without it there is no
way to say which of the two you meant.

**Omitting `max_records_per_query` buys the platform default of 500 per
listing**, the same as any other source. (A Sortlist listing reads 3 pages by
default and page 1 is not a normal page — ~20 promoted agencies, then ~100 on
each of pages 2-3 — so a listing yields roughly 220 and the 500 is rarely
reached. Set the limit explicitly anyway: the guards and the estimate are
computed from the number you sent, not the number the run will hit.)

## Free at the source is not a free run

`estimated_cost_usd` comes back `null` and the source reports itself free.
Both are true and neither means the run costs nothing:

```
the SOURCE      free — a public directory, nothing is purchased to start
the ENRICHMENT  N agencies x every stage you enabled       ← this is the spend
```

Quote the user the **downstream** figure. Branch your confirmation copy on the
source being free, **never** on `estimated_cost_usd` being absent — an unpriced
*paid* provider looks identical on every money field and is emphatically not
free.

## 🔴 VayaPin is refused — and the reason is republication

Enabling `workflow.vayapin` on a Sortlist run is a **422**, not a silent skip:

```
settings.workflow.vayapin is enabled but source_kind 'sortlist_agency' cannot
feed it (eligible stages: ['smartlead', 'social_media_enrichment',
'spidersite', 'spiderverify']). Disable the stage or choose another source.
```

Eligible: `spidersite` · `spiderverify` · `social_media_enrichment` ·
`smartlead`. Not eligible: `vayapin`.

**Do not read this as a data gap.** A Sortlist agency *does* have a street
address — the record carries one, and the adapter maps it. The exclusion is not
"VayaPin needs an address it hasn't got"; that is the reason the LinkedIn source
is excluded, and applying it here leads a reader to conclude this line is an
oversight and try to remove it.

The actual reason is **republication**. VayaPin mints a permanent public profile
page per lead, and those pages stay online after the run — there is no
un-publish path. Enabling it would let a checkbox permanently republish records
taken from a third party's directory. Reading the directory is permitted;
republishing it was never part of that.

## Where the contact data comes from

The directory is a source of *agencies*, not of contacts. Sortlist publishes no
email addresses and no phone numbers, and none are read from it. Every contact
on a finished record comes from **the agency's own website**, crawled by
`spidersite` in the fan-out exactly as it would be for a Maps lead.

That is why `spidersite` is the stage worth enabling here: with it off, you get
agency names and sites and no way to reach anyone.

## When to use it

| Use Sortlist when | Use Maps/`outscraper` when |
|---|---|
| the user wants **agencies** — "SEO agencies in Germany", "branding studios in the Nordics" | the user wants local businesses of any other kind |
| coverage by service or industry across a whole country is the point | a city, a radius, or a named place is the point |
| the budget is the enrichment, not the sourcing | you are willing to buy records |

Sortlist has no city or radius targeting — the smallest unit is a country. If
the user asked for one city, Maps is the right source.
