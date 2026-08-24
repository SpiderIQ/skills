# Internal sources vs buying leads — read this first

Two completely different purchases wear the same `bulk-lead-sourcing` name.

| | **Provider run** (`outscraper`, `apify`) | **Internal run** (`internal`) |
|---|---|---|
| Where the leads come from | bought from a third party | **the tenant's own corpus** — leads they already paid for |
| Source cost | real money, per record | **zero** |
| What you send | `queries` × `geo` | a `selection_id` |
| What it produces | leads you did not have | **enrichment on leads you did have** |
| Duplicate risk | dedup within the purchase | none — these ARE the existing rows |

## Pick internal when the user's sentence is about work, not about leads

Buying: *"find me 2,000 dentists in Bavaria"*, *"I need leads in Texas"*.

Internal: *"we never verified the emails from the Berlin campaign"*, *"crawl the
sites for everyone we have without a website record"*, *"which of our leads have
no email yet — go get them"*, *"re-run VayaPin over last quarter"*.

The tell is a possessive. **"Our leads", "the leads we already have", "last
month's campaign" all mean internal.** Buying more copies of leads the tenant
already owns is the failure this source exists to prevent, and nothing downstream
will catch it — the dedup is per-purchase, so a second buy of the same city looks
like a perfectly healthy 2,000-record job.

## 🔴 Free at the source is not free

Every money field on an internal run reads `0` or `null`, because nobody is paid
for us to read our own database. **Do not tell the user the run is free.** The
spend is downstream and it is real:

```
cost ≈ eligible_leads × (number of enabled stages)
```

A 9,000-lead selection with site + verify enabled is 18,000 units of enrichment.
That it cost nothing to *select* is irrelevant to what it costs to *run*.

Branch your confirmation copy on **what is being enriched**, never on whether the
cost field is empty — an unpriced *provider* looks identical on every money field
and is not free at all.

## Two shapes, one endpoint

```
unenriched_run   "the Berlin campaign, but with verify this time"
                 → point at a past campaign_id or job_id. No filter needed.

corpus_query     "everyone with a website but no email"
                 → author a filter AST against the field catalogue.
```

Both become a **selection**, and a selection is what the run consumes. See
[run-internal.md](run-internal.md).
