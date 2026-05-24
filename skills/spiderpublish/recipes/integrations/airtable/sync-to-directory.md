# recipes/integrations/airtable/sync-to-directory

Sync an Airtable view → SpiderPublish directory listings via `directory_bulk_upsert_listings`. One-shot import, idempotent by external_id, runs nightly via cron or on-demand.

## When to use

- A client maintains their canonical service list in Airtable and wants it published as programmatic-SEO directory pages.
- Recurring sync: Airtable is the source of truth, SpiderPublish renders + serves.
- Initial migration: 50-5000 rows from Airtable → tenant directory in one job.
- Pattern: "Airtable view is the master; mirror it as a public directory."

## Prerequisites

- Airtable Personal Access Token (PAT) with read access to the target base.
- A SpiderPublish PAT scoped to the tenant.
- A `directory_categories` row already created in the tenant (the parent for listings). See [`../../directory/import-listings.md`](../../directory/import-listings.md).
- Field map: which Airtable columns → which directory fields (`name`, `slug`, `description`, `address`, `phone`, `category_id`, etc.).

## Step 1 — Pull from Airtable

```python
import requests

AIRTABLE_PAT = "<your-pat>"
BASE_ID      = "appXXXXXXXXXXXX"
TABLE_NAME   = "Listings"
VIEW_NAME    = "Published"            # filter to "ready to publish" rows

url = f"https://api.airtable.com/v0/{BASE_ID}/{TABLE_NAME}"
params = {"view": VIEW_NAME, "pageSize": 100}
headers = {"Authorization": f"Bearer {AIRTABLE_PAT}"}

records = []
while True:
    r = requests.get(url, params=params, headers=headers).json()
    records.extend(r.get("records", []))
    if "offset" not in r:
        break
    params["offset"] = r["offset"]

# records = [{id: "rec...", fields: {Name, Slug, Description, ...}, createdTime}, ...]
```

## Step 2 — Map Airtable → SpiderPublish shape

```python
listings = [
    {
        "external_id":   r["id"],                                  # "rec..." — keep for idempotency
        "name":          r["fields"]["Name"],
        "slug":          r["fields"]["Slug"].lower().replace(" ", "-"),
        "description":   r["fields"].get("Description", ""),
        "address":       r["fields"].get("Address"),
        "phone":         r["fields"].get("Phone"),
        "website":       r["fields"].get("Website"),
        "category_id":   "<dir-cat-uuid>",                         # the parent category
        "metadata":      {
            "hours":     r["fields"].get("Hours"),
            "rating":    r["fields"].get("Rating"),
            "airtable_record_id": r["id"]                          # also store inline for audit
        }
    }
    for r in records
]
```

**`external_id` is your idempotency key.** Use the Airtable record ID (`rec...`) verbatim. Re-runs of the sync recognize existing rows by external_id and UPDATE rather than INSERT-duplicates.

## Step 3 — Bulk upsert via `directory_bulk_upsert_listings`

```
directory_bulk_upsert_listings({
  category_id: "<dir-cat-uuid>",
  listings:    listings,         # the array from Step 2
  on_conflict: "update_by_external_id"
})
# → {
#     success: true,
#     stats: { created: 12, updated: 38, skipped: 0, errors: [] }
#   }
```

The bulk endpoint:

1. INSERTs new rows for `external_id`s not yet seen.
2. UPDATEs existing rows where `external_id` matches.
3. Returns per-row stats so you can surface errors.

For a soft delete (rows in Airtable that disappeared from the view), the import doesn't auto-delete — call `directory_archive_listing({external_id})` for each missing ID in a follow-up step.

## Step 4 — Deploy

The directory pages are dynamically rendered at request time via Liquid; once the rows land, they're visible at `/{category-slug}/{listing-slug}` immediately. No deploy needed for new listings — but if you changed the directory **template**, redeploy via [`../../reference/deploy-protocol.md`](../../reference/deploy-protocol.md).

## Steps — full flow

```python
# 1. Pull Airtable → records
records = pull_airtable_view(BASE_ID, TABLE_NAME, VIEW_NAME)

# 2. Map → SpiderPublish shape (with external_id = record.id)
listings = map_to_spideriq_shape(records)

# 3. Bulk upsert
result = directory_bulk_upsert_listings(category_id, listings, on_conflict="update_by_external_id")

# 4. Detect deletions (optional)
local_ids = {r["id"] for r in records}
remote_listings = directory_list_listings(category_id)
to_archive = [l for l in remote_listings if l["external_id"] not in local_ids]
for l in to_archive:
    directory_archive_listing(l["external_id"])

# 5. Log + emit metrics
print(f"Synced: {result['stats']}, archived: {len(to_archive)}")
```

Wrap this in a cron (`crontab -e` → `0 2 * * * /usr/local/bin/sync-airtable-to-spideriq.py`).

## Gotchas

- **Slug stability matters.** If the client edits "Name" in Airtable, your slug-derivation regenerates and the listing URL changes — visitors hit 404. Either (a) use a separate "Slug" column in Airtable that doesn't change, or (b) detect slug changes and keep the old slug as a 301 redirect via `content_create_redirect`.
- **Airtable rate limits at 5 req/sec per base.** Bulk-pull 5000 rows in one go = ~17s. Don't parallelize per-page reads; respect the limit.
- **`directory_bulk_upsert_listings` has a per-call max** (~500 listings). For 5000 rows, batch in 10 calls of 500.
- **`external_id` is unique per category, not per tenant.** Two categories CAN share the same `external_id` value — useful for "same Airtable row appears in two directories" patterns; confusing if you assume global uniqueness.
- **Airtable's `Last Modified Time` field doesn't survive the sync** unless you map it explicitly to `metadata.last_modified_airtable`. Useful for "show what changed in the last sync."
- **Deleted Airtable rows don't auto-delete in SpiderPublish.** The bulk upsert is upsert-only. Archive missing rows in a separate step (Step 4 in the flow above).

## Verify

```
directory_list_listings({ category_id: "<dir-cat-uuid>", limit: 5 })
# → confirm recent items match Airtable

content_visual_check({
  page_url: "https://<tenant>/<category-slug>/<listing-slug>",
  viewport: "desktop"
})
# → confirm the dynamic page renders
```

## Anti-patterns

- **Loop-creating listings one at a time** instead of bulk-upserting. 5000 round-trips vs 10.
- **Skipping `external_id`** and letting the sync create duplicates on every run. Idempotency requires the external_id key.
- **Mapping Airtable's `id` to SpiderPublish's `id`** — different namespaces. Map `id` → `external_id` instead.
- **Hardcoding the Airtable PAT in client-side code.** PATs read all rows; keep server-side.
- **Forgetting to handle the deletion case.** Listings linger forever if Airtable rows disappear from the view but you don't archive them.

## See also

- [`../../directory/import-listings.md`](../../directory/import-listings.md) — the generic bulk-upsert primitive (this recipe is its Airtable specialisation)
- [`../../content/dynamic-list-page.md`](../../content/dynamic-list-page.md) — the listing-rendering primitive (Liquid template that paginates the directory)
- [`../../reference/tool-surface.md`](../../reference/tool-surface.md) — the `directory_*` tool family
