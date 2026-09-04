# Dynamic collections — `dynamic_list` / `dynamic_item` and every `collection_type`

> **REQUIRES — read before you plan.**
> **Package:** `content_create_page` / `content_update_page` ship in **every** universe. Floors: `@spideriq/mcp-publish` ≥ 1.43.0 · `@spideriq/mcp` ≥ 1.91.1 · `@spideriq/core` ≥ 1.76.0.
> **Tools:** `content_create_page(template=…, collection_type=…)` · `content_publish_page` · `content_deploy_site` · `list_data_sources` / `collection_list` to confirm the binding exists
> **Live on PUBLISH** for the page itself and for the items it iterates. **Deploy only if you changed a Liquid template.**
> **Not sure which universe you are in?** SKILL.md → *Step 0*.


Two page templates turn one authored page into many rendered ones:

- **`dynamic_list`** — one page that lists every record in a bound collection.
- **`dynamic_item`** — one page that serves the detail view for *every* record in that collection.

Both take a **`collection_type`**, and picking it is the whole decision. Read this **before** you
pick one.

> `dynamic_landing` is **not** in this family. It takes no `collection_type`, is lead-scoped, and
> lives on `/lp/` — see `references/dynamic-landing.md`.

---

## The contract

```
  template = dynamic_list | dynamic_item   ⇒  collection_type is REQUIRED   (422 without it)
  template = anything else                 ⇒  collection_type must be ABSENT (422 with it)
```

`content_update_page` **cannot change `collection_type`.** Bind it at create time or rebuild the
page.

---

## Every accepted `collection_type`, with its honest status

| `collection_type` | Status | List URL | Item URL |
|---|---|---|---|
| `posts` | built-in, long-standing | `/{page_slug}` | `/blog/{post_slug}` |
| `docs` | built-in, long-standing | `/{page_slug}` | `/docs/{full_path}` |
| `directory_listings` | **renders** — verified live 2026-09-02, cards reconciling exactly to category totals | `/{page_slug}` | `/{page_slug}/{listing_slug}` |
| `idap.<collection>` (e.g. `idap.businesses`) | **serving real tenant-scoped rows** — verified live 2026-09-03 | `/{page_slug}` | ⚠️ **no working detail URL** — see below |
| `<custom-collection-slug>` | works, and was **undocumented until now** | `/{page_slug}` | `/{collection_slug}/{record_slug}` |

### `directory_listings` — the FLAT layout

Every published listing on one page, each item one segment below it. **No category, no city in the
URL.** It coexists with the nested `/{directory_base}/{category}/{city}/{listing}` pages over the
same rows — it does not replace them. Pick flat when the user does not want a city in the URL;
pick nested when they are doing per-city programmatic SEO (`references/directory-pages.md`).

Backed by `GET /content/directory/listings[?category=&city=&page=&page_size=]` and
`GET /content/directory/listings/{listing_slug}[?category=]`.

⚠️ **A listing slug is unique per CATEGORY, not per tenant.** Where two categories hold the same
slug, the flat detail door returns a **deterministic first match** (`ORDER BY category.sort_order,
category.slug`) and names its choice in `category_slug` — it never 400s on the ambiguity. Pass
`?category=` to pin it.

### `idap.<collection>` — the tenant's own corpus, and one real gap

`idap.businesses` binds and serves the tenant's rows, scoped to that tenant. Its siblings behave
distinctly, and the difference is worth knowing before you debug one:

| | Answer |
|---|---|
| `idap.businesses` | 200, rows |
| `idap.streets` — registered but not servable | **422** `DATA_SOURCE_NOT_SERVABLE` |
| `idap.lead` — a **singleton**, not a collection | **422**. It reaches `/lp/` templates as `lead`; it is not bindable here |
| anything unregistered | **404** |

🔴 **`idap.*` has no working per-item URL in default mode.** The generic branch builds each item's
link as `/{collection_type}/{slug}` — i.e. `/idap.businesses/acme` — and nothing serves that path:
it is neither a collection `route_base` (a dot is not admissible in one) nor a page slug. The list
renders; every default-mode item link 404s. **Use authored mode** and write your own `href`s from
`items`, or bind a custom collection instead if you need detail pages.

### `<custom-collection-slug>` — any collection you made

Any collection created with `collection_create` (`^[a-z0-9][a-z0-9-]*$`). Its records come through
the same items door and its detail pages are served by the catch-all record door at
`/{collection_slug}/{record_slug}`. Long supported, previously undocumented — this is the value to
reach for when none of the built-ins fit.

---

## 🔴 Existence is NOT validated at create time

Deliberately — the validator has no database. **A well-formed slug for a collection that does not
exist is a `201`.** At request time the page renders its empty state, which is byte-identical to a
real collection with no published records.

```
  content_create_page(template="dynamic_list", collection_type="case-studys")   ← typo
  → 201 Created                                                                ← looks fine
  → the live page says "No items in this collection yet", at HTTP 200, forever
```

**Confirm the binding before you trust the 201:** `list_data_sources` or `collection_list`. And
when a `dynamic_list` renders nothing, **check the binding before you touch the template** — an
empty page and a wrong `collection_type` are the same output, at the same status code, with no
error anywhere.

---

## Two render modes

Both templates branch on whether the page has blocks:

| Mode | Trigger | What renders |
|---|---|---|
| **AUTHORED** | `page.blocks` is non-empty | Your blocks own the layout. `items` (list) / `item` (detail) are in Liquid scope, so a block can do `{% for item in items %}…{% endfor %}` and control the markup and the hrefs. |
| **DEFAULT** | `page.blocks` is empty | A built-in fallback: the page title plus a simple linked list. Lets a tenant create the page and see *something* immediately. |

Default mode is a starting point, not a design. Add blocks to take over. For `dynamic_item` the
same split applies, with `item` null when the slug does not match — the template shows its
not-found state rather than erroring.

Both dispatch to `templates/dynamic-list.liquid` / `templates/dynamic-item.liquid`. Override either
with `template_upsert` — **that** is what needs a deploy; the page and its items do not.

---

## Build one

```
# the list
content_create_page(title="Our clients", slug="clients",
                    template="dynamic_list", collection_type="case-studies")
content_publish_page(page_id)

# the detail — pair them, or /{page_slug} 404s for visitors who land on the index
content_create_page(title="Client story", slug="clients",
                    template="dynamic_item", collection_type="case-studies")
```

`slug` on a `dynamic_item` page is the URL **prefix**, not a per-item value: the renderer reads the
segment after it and resolves the item. `blocks[]` is optional on both.

---

## 🔴 Merge tags do NOT populate on these pages

`{{ first_name }}`, `{{ company_name }}`, `{{ city }}` and the rest are **`/lp/` lead-scoped
only** — they are built from a lead resolved by the `/lp/{page_slug}/{identifier}` routes. On every
other route, `dynamic_list` and `dynamic_item` included, they resolve to the canonical **empty
shape** and render as empty strings, silently.

A `dynamic_list` / `dynamic_item` template reads its `items` / `item` — and, for
`directory_listings`, `listing.*` and `data.*`. Never `{{ first_name }}`.

---

## Paging a bound collection

Reading through `list_data_source_items`: **`offset` is capped at 10,000** (`offset=10001` → `422
OFFSET_CAP_EXCEEDED`, which names the cap rather than silently returning page 1). Past that the
**`after` keyset cursor is the only way through** — send back the response's `next_cursor` and drop
`offset` entirely.

---

## Do not claim

- **Do not claim a `201` means the collection exists.** It means the slug was well-formed.
- **Do not diagnose an empty page as a template problem.** Check the binding first.
- **Do not promise merge tags here.**
- **Do not promise `idap.*` detail pages.** The list works; the default item links 404.
- **Do not offer `content_update_page` to change `collection_type`.** It cannot.
- **Do not describe `directory_listings` as unrendered.** It renders — that was true before ISU-4
  and is not true now.

## See also

- `references/directory-pages.md` — the nested, category-first directory layout over the same
  listings
- `references/collections.md` — creating a custom collection and filling it
- `references/dynamic-landing.md` — `/lp/` lead-scoped pages, where merge tags DO work
- `references/content.md` — page CRUD, blocks, the dynamic-list / dynamic-item recipes in full
- `references/templates-deploy.md` — overriding the two Liquid templates
