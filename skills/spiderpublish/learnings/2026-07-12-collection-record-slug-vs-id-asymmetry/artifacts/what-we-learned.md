# Collection records: read by slug, write by id — and unknown fields are rejected

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

You author a custom collection, read a record back by its slug, then try to
publish it — feeding that same slug into `updateCollectionRecord`. **404.** The
record is right there; you just read it. What went wrong?

And separately: you send a record with a field you *thought* was in the schema.
Unlike a blog post (which would silently swallow it), the collection record write
**422s** with `{errors, warnings}`.

## Why it happens

The custom-collections surface (slice 1.8) deliberately splits its record
addressing:

- **Reads use the record SLUG** — `getCollectionRecord` → `GET
  .../records/{record_slug}`. Slugs are the human/URL handle.
- **Writes use the record ID** — `updateCollectionRecord` /
  `deleteCollectionRecord` → `PATCH`/`DELETE .../records/{record_id}`. The id is
  the stable primary key; a slug can change, an id can't.

So a slug fed into an update/delete path resolves nothing → 404.

On fields: collection `data` is validated against the collection's own
`schema_json`. This is the **opposite** of the posts endpoints, which drop
unknown keys silently (see the sibling learning). Collections **reject-with-
warning** — fail-loud, because an agent authoring structured data should hear
about a typo, not ship blank rows.

## What "good" looks like

```jsonc
// 1. Declare EVERY field up front.
createCollection({ slug: "case-studies", label: "Case Studies",
  schema_json: { fields: { title: {type:"string"}, client: {type:"string"}, summary: {type:"richtext"} } } })

// 2. Create/read → keep the `id` from the response.
const rec = createCollectionRecord({ collection:"case-studies", slug:"acme", data:{ title:"Acme", client:"Acme Co", summary:"…" } })
//   rec.id  ← use THIS for writes, not rec.slug

// 3. Publish BY ID, two-phase gated.
updateCollectionRecord({ collection:"case-studies", record_id: rec.id, status:"published", dry_run:true })   // → confirm_token
updateCollectionRecord({ collection:"case-studies", record_id: rec.id, status:"published", confirm_token:"cft_…" })

// 4. Expose, then deploy.
updateCollection({ slug:"case-studies", is_public:true })
// deploySite(...)
```

## The general rule

When a resource has both a mutable slug and a stable id, note **which handle each
verb takes** — read-by-slug + write-by-id is a common, deliberate split.
Round-trip the id from the create/read response into your writes. And check
whether a write surface **drops** unknown fields (posts) or **rejects** them
(collections) — it changes whether a typo fails loud or ships blank.

## See also

- [`../references/collections.md`](../../references/collections.md) — the full call path + Gotchas.
- `2026-06-11-post-field-names-silently-dropped/` — the contrast: posts drop, collections reject.
