# Custom Collections — define a content type, fill it, render it

Custom collections let you (the agent) define your OWN content types — case studies, team
members, FAQs, products, testimonials — with a schema you declare, records you author, and a
live render on the site. This is the differentiator vs a classic CMS: the agent authors the
`schema_json` AND fills every record, in one session. Authoring goes through
`POST/PATCH/GET/DELETE /api/v1/dashboard/content/collections/...` (or the project-scoped
`/api/v1/dashboard/projects/{pid}/content/collections/...`) with a Bearer PAT. Published rows
read back through the SAME public `/items` door as the built-in collections. The deploy
pipeline lives once in [`deploy-protocol.md`](deploy-protocol.md); block shapes in
[`block-types.md`](block-types.md).

**Read when:** the built-in types (pages, posts, docs) don't fit — you need structured,
repeatable content with its own fields, authored in bulk and rendered as a list/detail.

---

## Model

- **Collection** = a definition: `slug`, `label`, `schema_json` (the field spec records
  validate against), `route_base` (optional detail-page URL base), `is_public` (expose via
  the `/items` door).
- **Record** = a row: `slug`, `data` (field values, validated against `schema_json`),
  `seo_title`, `seo_description`, `og_image_url`, `sort`, `publish_at`, `status`
  (`draft`|`published`|`archived`).
- **Scope:** PROJECT-scoped. Bind a project first (`spideriq use <project_id>`, an
  `-w/--workspace`, or an `X-Project-Id` header) or the API 400s asking for one.

---

## Define + fill + render a collection

### When to use

A tenant needs, e.g., a **Case Studies** section that renders live rows an agent authored —
not one-off pages, but a repeatable typed list.

### Prerequisites

1. **Tenant + project scope verified** (see SKILL.md auth). A collection lives in one project.
2. Know the fields you'll store — you declare them in `schema_json` up front. Records
   **reject-with-warning** on any field not in the schema (a 422 with `{errors, warnings}`),
   so declare every field you intend to store.

### The call path

1. **Define the collection** (non-destructive, enforces `max_collections`):
   ```
   createCollection slug=case-studies label='Case Studies' \
     schema_json={fields:[
       {id:title,   type:text,  label:Title},
       {id:client,  type:text,  label:Client},
       {id:summary, type:text,  label:Summary},
       {id:logo,    type:media, label:Logo}
     ]}
   ```
   **`fields` is a LIST of field objects, not a dict** — each needs an `id` (a `dict`
   keyed by field name 422s with `fields  Input should be a valid list`; a list whose
   items omit `id` 422s with `fields.0.id  Field required`). Valid `type` values are
   exactly: `text` · `number` · `bool` · `select` · `date` · `richtext` · `media` ·
   `relationship` · `blocks` — there is **no** `string` or `image` (use `text` / `media`).
   Optional per-field keys: `label`, `options` (for `select`).
2. **Bulk-fill the records** (1–100 in ONE transaction — any bad record rejects the whole
   batch; enforces `max_records` for the batch size):
   ```
   bulkCreateCollectionRecords collection=case-studies records=[
     {slug:'acme',  data:{title:'Acme',  client:'Acme Co',  summary:'…'}},
     {slug:'globex', data:{title:'Globex', client:'Globex LLC', summary:'…'}}
   ]
   ```
   For a single row use `createCollectionRecord`. Both save as **drafts**.
3. **Publish rows** — a `status` change is the GATED transition (two-phase):
   ```
   updateCollectionRecord collection=case-studies record_id=<id> status=published dry_run=true
   # → returns a preview + confirm_token (cft_…); repeat with it:
   updateCollectionRecord collection=case-studies record_id=<id> status=published confirm_token=cft_…
   ```
   Note `record_id` here is the **id**, not the slug (reads use the slug; writes use the id).
4. **Expose the collection** through the public `/items` door:
   ```
   updateCollection slug=case-studies is_public=true
   ```
5. **Render it** — create a `kind='dynamic'` component whose `source_id` is the collection
   slug (it binds exactly like the built-in `posts` source), then `insertSection` it on a
   page. The renderer fetches the rows server-side and exposes them as `items`. See
   [`content.md`](content.md) → dynamic component, and the `/content/help` →
   `custom_collections` stanza.
6. **Deploy:** `deploySite` (or `deployProduction`). Publishing flips a flag in the store;
   only a deploy makes it live — see [`deploy-protocol.md`](deploy-protocol.md).

### Verify

- `listCollectionRecords collection=case-studies` shows your rows (drafts + published);
  add `?format=yaml` for a token-cheap projection.
- After deploy, `GET /api/v1/content/data-sources/case-studies/items` returns the published
  rows (the same door dynamic components read).

---

## Reading records without paying for every field

A record comes back with **every field its schema declares**. That is fine for a 6-field
collection and expensive for a wide one — a 54-field collection costs roughly 73,000
characters for a single 60-row page, most of it fields you didn't ask about.

Narrow it:

```
listCollectionRecords collection=skills limit=50 fields=name,tagline,install_cmd
```

- `fields` is a comma-separated list of **field ids** (the `id` key in `schema_json.fields`),
  and it narrows the `data` object **only**. The record envelope — `slug`, `status`,
  `published_at`, `seo_title`, `seo_description`, `og_image_url`, timestamps — always comes
  back, so you can still page, sort and identify rows.
- **Unknown ids are ignored, not rejected.** Narrowing a projection should never be harder to
  get right than not narrowing it, so a typo costs you a missing field, not a 422. This is
  deliberately the opposite of the WRITE path — see the first gotcha below.
- Combine it with `limit`: `fields` cuts how wide each row is, `limit` cuts how many rows.
  A discovery pass usually wants `fields=<the field you're matching on>` and a small `limit`.
- `?format=yaml` saves on top of this, not instead of it — it changes the encoding, not which
  fields are present.

---

## Gotchas

- **Unknown fields are rejected, not ignored.** `data` is validated against `schema_json` —
  a typo'd field 422s with `{errors, warnings}`. Read the collection first (`getCollection`)
  if unsure of the field names.
- **Reads use the record slug; writes use the record id.** `getCollectionRecord` takes
  `record_slug`; `updateCollectionRecord` / `deleteCollectionRecord` take `record_id`.
- **Publishing ≠ deploying.** A `status=published` record is live in the STORE; the site only
  reflects it after `deploySite`.
- **Delete cascades.** `deleteCollection` removes the collection AND all its records
  (two-phase gated). `deleteCollectionRecord` removes one row (also gated).
- **Quotas.** Collection + record creates enforce `max_collections` / `max_records` (403 with
  `rule_id=max_collections_exceeded` / `max_records_exceeded`). A bulk is checked against the
  full batch size.
- **Not public until you say so.** A collection is private (≡ unknown) until `is_public=true`;
  the `/items` door + dynamic binding only see published rows of a public collection.
- **`richtext` normalizes to Tiptap — do NOT store raw HTML in it.** A `richtext` field is
  converted to a canonical Tiptap document at write; a raw HTML string is stored as **escaped
  text**, so the live render shows the literal `<div>…` markup. For a rich body author it as
  Markdown/Tiptap, or use a flat `text` field for plain strings.
- **`blocks` holds PAGE-BLOCKS, not arbitrary objects.** Each item in a `blocks` field must be a
  page block whose `type` is one of the 14 page block-types (`hero`, `features_grid`, `stats_bar`,
  `rich_text`, `cta_section`, `pricing_table`, `testimonials`, `faq`, `code_example`, `logo_cloud`,
  `comparison_table`, `image`, `video_embed`, `spacer`, `component`) — an off-list item 422s.
- **Reading a collection's `/items` resolves the tenant by DOMAIN.** `GET /content/data-sources/
  <slug>/items` is the public content door — it resolves the tenant from the `X-Content-Domain`
  header (the owning site's domain), **not** `X-Project-Id`. A request without it resolves the
  default tenant and 404s "Data source not found" even though the collection exists.
