# Dynamic landing pages — one page, personalised per prospect

> **REQUIRES — read before you plan.**
> **Package:** works in **every** universe (kitchen sink · mcp-publish default · mac-128).
> **Tools:** `createPage(template='dynamic_landing')` `publishPage` `deploySite` · `content_get_variables` for the merge-tag vocabulary
> **Live on PUBLISH — no deploy needed.** Content is fetched from STORE at request time; allow ~60s for the edge cache (`s-maxage=60`). **Do not run a deploy to make content appear, and do not tell the user a deploy is pending.** Deploy is only for templates / theme / the config overlay.
> **Not sure which universe you are in?** SKILL.md → *Step 0*.


A page whose `template` is `dynamic_landing` gains two extra public routes on the deployed site:

```
/lp/{page_slug}/{identifier}
/lp/{page_slug}/{salesperson_slug}/{identifier}
```

The `{identifier}` is resolved to a business record **at request time** and exposed to the
template as `lead`. There is no page row per prospect and nothing is stored per visitor — one
authored page serves the whole list.

Reach for this when the user says: *a personalised landing page*, *a page per prospect*, *an
outreach page*, *ABM landing page*, *merge tags on a landing page*.

Everything below is **project-scoped**. Bind a project first (`spideriq use <id>`, a
`-w/--workspace`, or an `X-Project-Id` header).

---

## Build one

```
createPage(template="dynamic_landing")  →  publishPage  →  deploySite
```

1. **`createPage`** with `template: "dynamic_landing"`. Set it **at create time** — the renderer
   dispatches on this field, and a page created with the default template will not pick up the
   `/lp/` routes. (`updatePage` can also set it; the dashboard exposes it under **Page Settings →
   Template**, not on the new-page form.)
2. Put `{business}` and `{city}` placeholders in the page's copy fields.
3. **`publishPage`**, then **`deploySite`**. Both are required: publish makes the page live in the
   store, deploy pushes the routes to the domain.

⚠️ **`{business}` is substituted in the template BODY only** — the headline, the subheadline, the
CTA. It is **not** substituted in the page `title`, `seo_title` or the social preview. A
placeholder in the title field ships the literal `{business}` to the browser tab and to every link
preview. Keep placeholders in the copy.

---

## What the template gets

Two vocabularies, and they do NOT have the same rules. Mixing them up is the single most common
`/lp/` authoring mistake.

| Variable | Shape |
|---|---|
| `lead` | the business record — **every column the tenant's IDAP `businesses` table has**, spread verbatim. Plus `lead.related.{emails,phones,domains,contacts}` when requested. |
| flat merge tags | `{{ company_name }}`, `{{ city }}`, `{{ firstname }}`, `{{ email }}`, `{{ phone }}`, `{{ rating }}` … — snake_case, null-safe, spread at top level **alongside** `lead`, never instead of it. |
| `salesperson` | `name`, `title`, `location`, `bio`, `photo_url`, `calendar_url` — matched from the URL slug against `salespersons` in the project's template config |

```liquid
{{ lead.name }} in {{ lead.city }} — {{ lead.rating }} from {{ lead.reviews_count }} reviews
Hi {{ firstname }}, a quick note for {{ company_name }}.
```

### `{{ lead.x }}` is free. `{{ x }}` comes from a generated spec.

**`lead.*` needs nothing.** `GET /content/leads/resolve` spreads the resolved row into its
response verbatim (`**data`) and the renderer stores it in Liquid scope **unprojected** — there is
no allowlist, no field map, no serializer to extend. A column that exists on the tenant's
`businesses` table is readable as `{{ lead.<column> }}` with **zero** platform work. The only two
keys that move are `created_at` / `updated_at`, which the door pops and re-emits as `created_at` /
`modified_at`.

🔴 **Do not go looking for a number of columns.** It has changed twice in one quarter and will
change again. The authoritative list is the manifest, `app/data/idap-fields.json`; the list an
agent can read at runtime is **`content_get_variables`**. Ask the surface, do not quote a count.

**Flat tags come from a generated spec, and adding a column now mints one automatically.** The
vocabulary lives in `apps/liquid-renderer/merge-tags.spec.json`, generated from that same
manifest. Every tag the spec marks `generated: true` is resolved by one generic loop —
`lead[column]` — so a new column produces a working `{{ column }}` tag with no code change.

⚠️ **Two exceptions, and both are deliberate.** A column listed in `merge-tags.bespoke.json`'s
`covered_columns` gets **no** generated tag, because a hand-written picker already serves that name
and reads somewhere else: `{{ team_size }}` resolves
`lead.related.domains[0].company_vitals.team_size`, **not** `businesses.team_size`. And a bespoke
picker always wins over the generic loop. So: **`{{ x }}` is not guaranteed to be
`{{ lead.x }}`** — where a bespoke picker exists, the two can legitimately hold different values.
`{{ phone }}` is E.164 (`+13055551234`) while `{{ phone_national }}` is `(305) 555-1234`, from the
same record. When you need a specific column, `{{ lead.<column> }}` is the unambiguous form.

Run `content_get_variables` for the live vocabulary with per-tag descriptions — it is the only
list that cannot go stale.

---

## Preview: `/lp/{slug}/demo` does NOT read IDAP

```
/lp/{page_slug}/demo              ← the literal identifier "demo"
/lp/{page_slug}/{anything}?preview=sample-lead
```

Both **bypass IDAP entirely** and serve a built-in fixture. That is the point — you can preview a
personalised page before you have a single prospect — but it means **a preview is not evidence
about a real lead, in either direction.**

🔴 **The trap this used to set, and what changed.** The fixture was hand-maintained and drifted
behind production: it carried 24 of the 43 columns the live door served. An author wrote
`{{ lead.working_hours }}`, previewed on `/lp/x/demo`, saw blank, and concluded the field does not
bind. **It binds.** The blank was the fixture, not the platform — and the staleness was invisible
from both sides, because a missing key and an empty value render identically.

**ISU-20 (2.2b) made that class of lie structurally impossible.** `demo-fixture.ts` is now
**GENERATED** — its key set comes from `app/data/idap-fields.json`, keyed exactly as the resolve
door keys a real lead, so it cannot fall behind the manifest again. Its *values* stay hand-curated
in `demo-lead.curated.json`.

⚠️ **State it at that level and no higher.** What is established is that the fixture's **key set**
is generated from the manifest. A live diff of the `/lp/{slug}/demo` key set against a real
`/lp/{slug}/{place_id}` on a deployed tenant was **not** run at `/test-live` — so "the preview
shows exactly what production shows" is a claim nobody has measured. If a field is blank in
preview, check it against a real identifier before concluding anything.

**And the preview surface lags the deploy.** The renderer bundle reaches tenants through a
per-tenant sweep; the `preview-*` scripts are swept by nothing. A blank tag on a *preview* URL
after a platform change is expected until that tenant redeploys — never use a preview URL as the
test for whether a field binds.

---

## Pick the identifier key — TEN resolve, and `email` is not one of them

The identifier is read as a Google place ID by default. Name a different key with `?resolve_key=`:

```
/lp/wifi-proposal/acme-plumbing.de?resolve_key=domain
/lp/wifi-proposal/ajay/DE123456789?resolve_key=vat
```

| Where the list came from | Keys |
|---|---|
| Maps / crawl | `place_id` (default), `domain` |
| VayaPin | `pin_name`, `pin_data_set_id`, `account_id`, `pin_subscription_id` |
| Company registry | `vat`, `lei`, `tax_id`, `registration_number` |

🔴 **`email` is accepted but NEVER resolves a business.** It is retained for backward
compatibility; the business record has no email column and no join on one, so it always returns
`404 lead_not_found`. Recommend `domain` instead — do not offer `email` as an option.

The underlying read is `GET /content/leads/resolve?<key>=<value>&include=emails,phones` (public,
tenant resolved from `X-Content-Domain`). Supplying zero or more than one identifier is a `400`.

---

## The no-lead contract — do not guard the whole page

When the identifier does not resolve, `lead` is **null**. This is a designed state, not an error,
and it **never 500s**: the renderer runs with `strictVariables` off, so `{{ lead.name }}` renders
empty rather than throwing, and the flat tags degrade to `''`.

The shipped default template falls back through `page.custom_fields.demo_business` to the literal
`"Your Business"`. Set your own:

```json
{ "custom_fields": { "demo_business": "your business", "demo_city": "your city" } }
```

**If you author a custom `dynamic_landing` template:**

```liquid
{%- assign biz = lead.name | default: page.custom_fields.demo_business | default: "Your Business" -%}

<h1>Faster wifi for {{ biz }}</h1>          {# outside the guard — always renders #}

{% if lead %}
  <p>Rated {{ lead.rating }} across {{ lead.reviews_count }} reviews.</p>
{% endif %}                                  {# inside — only with a real record #}
```

Render the authored blocks, hero and CTA **outside** the guard so a forwarded or expired link is
still a working page. A `/lp/` 500 is almost always a custom template dereferencing nested
`lead.*` without an `{% if lead %}` guard — the platform does not 500 on a missing lead.

A **404** on `/lp/...` means the *page slug* does not exist, not that the identifier failed.

---

## Do not claim

- It does **not** import anything. It reads business records already in the account.
- There is no visitor analytics, A/B testing, or per-visitor storage on this surface.
- Page titles and social previews are not personalised.
- **Do not claim the preview matches production.** The fixture's key set is generated from the
  manifest; a live key-set diff between `/lp/{slug}/demo` and a real identifier has not been run.
- **Do not claim a flat `{{ x }}` equals `{{ lead.x }}`.** Where a bespoke picker owns the name it
  reads elsewhere by design (`{{ team_size }}`, `{{ phone }}`).
- **Do not quote a column count or a merge-tag count.** Both move with the manifest. Name
  `content_get_variables` instead.
- **Merge tags are `/lp/` only.** They do not populate on `dynamic_list`, `dynamic_item`, or
  directory pages — see `references/dynamic-collections.md`.

## See also

- `references/dynamic-collections.md` — the other dynamic templates (`dynamic_list` /
  `dynamic_item`) and why merge tags do **not** reach them
- `references/directory-pages.md` — programmatic-SEO directory pages, the other way to publish
  many pages from IDAP data
- `references/content.md` — page CRUD, blocks, custom fields
- Customer guide: https://publish.spideriq.ai/docs/building-your-site/dynamic-landing-pages
- API reference: https://publish.spideriq.ai/docs/api-reference/content
