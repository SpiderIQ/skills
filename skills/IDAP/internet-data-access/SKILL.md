---
name: internet-data-access
version: "1.1.0"
description: >
  Unified read/flag access to all per-client normalized data. Fetch, list, search, batch, flag, and get stats for businesses, domains, contacts, emails, phones, company registry, and LinkedIn profiles.

category: data-collection
requires_auth: true
requires_brand: true
triggers:
  - fetch data
  - list resources
  - search data
  - flag resource
  - batch fetch
  - sync data
  - idap
client: internet-data-access
client_version: "1.1.0"
metadata:
  openclaw:
    primaryEnv: OPVS_PAT
---

# internet-data-access #data_collection

read, search, flag, and sync normalized client data across all resource types — businesses, domains, contacts, emails, phones, company registry, linkedin profiles

/#scrape-google-maps → discover NEW businesses (IDAP reads already-collected data)
/#scrape-website-extract-leads → crawl websites (IDAP reads crawl results)
/#lead-enrichment → manage board cards and enrichment workflow stages

## Chain
fetchResource → writeFlags (qualify/reject a resource)
listResources (with since) → batchFetch (sync delta)
searchResources → writeFlags (qualify matches)
getStats → listResources (drill into specific types)
resolveByExternalId → fetchResource (look up by VAT / LinkedIn / place_id, then load full record)
listCustomFields → defineCustomField → setCustomValues → listResources (filter custom.<key>=)

## Pitfalls
- IDAP reads EXISTING data — it does NOT trigger new scraping or crawling
- Resource IDs are UUIDs from normalized tables, NOT job IDs
- rejected flag auto-excludes from list/search — use flags=-rejected to include
- Batch max is 100 refs per request
- include parameter works on businesses (emails,phones,domains,contacts) and domains (contacts)
- Custom fields are on businesses only. Values come back in `custom`; filter with `custom.<key>=<v>` or `custom.<key>.<op>=<v>` (op: eq, in, gt, gte, lt, lte, exists) on listResources
- A key must be defined before a value is written; a value that does not fit the field's type refuses the whole write
- is_public=true lets the client's SpiderPublish sites show the value without a key; leave it false for private data
- resolveByExternalId requires exactly one identifier per call; mixing two returns 400. Not all identifiers are valid for every resource_type (e.g. vat only on company_registry).

## Resource Types
- businesses — Google Maps results, enriched business profiles
- domains — crawled website data, contact info
- contacts — extracted team members
- emails — verified/unverified email addresses
- phones — phone numbers from maps and sites
- company_registry — Companies House, handelsregister data
- linkedin_profiles — extracted LinkedIn profile data

## Methods

- `fetchResource(resource_type, resource_id, fields?, include?)` — Fetch a single resource by type and ID. Returns data, active flags, and optional related resources.
- `listResources(resource_type, since?, until?, limit?, cursor?, fields?, include?, flags?, sort?, order?, campaign_id?, source?)` — List resources with filtering, cursor-based pagination, and incremental sync.
- `searchResources(resource_type, q, limit?, fields?, flags?)` — Full-text search within a resource type using PostgreSQL tsvector.
- `getStats(resource_type)` — Get aggregate statistics — total count, flag distribution, source breakdown, last-24h activity.
- `writeFlags(resource_type, resource_id, add?, remove?, flagged_by?, reason?)` — Add or remove flags on a resource. Idempotent, history preserved.
- `batchFetch(refs, fields?, include?)` — Batch fetch up to 100 resources by idap:// ref strings.
- `resolveByExternalId(resource_type, [exactly one of: place_id|domain|email|url|vat|registration_number|lei|tax_id|linkedin|twitter|source_id], fields?, include?)` — Look up a canonical resource by an external identifier. Returns 404 if no match exists in the caller's normalized data; 400 if more than one identifier is supplied or the identifier doesn't apply to the resource_type.
- `listCustomFields(include_archived?)` — List the client's custom field definitions (key, label, type, aliases, is_public).
- `defineCustomField(key, label, type, visible?, group?, is_public?, aliases?)` — Define one custom field on businesses. 422 if the key reuses a built-in field.
- `defineCustomFieldsBulk(fields)` — Define up to 200 fields at once, all or nothing.
- `updateCustomField(key, label?, type?, visible?, group?, is_public?, aliases?, archived?)` — Change a definition. A type change runs only if every stored value converts (409 with the count).
- `archiveCustomField(key)` — Archive a field; its values are kept and hidden.
- `setCustomValues(business_id, custom)` — Merge values into one business; null removes a key.
- `setCustomValuesBulk(ids, custom)` — Merge the same values into up to 1,000 businesses.
