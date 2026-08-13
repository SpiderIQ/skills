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

| Variable | Shape |
|---|---|
| `lead` | the business record: `name`, `address`, `city`, `country_code`, `rating`, `reviews_count`, `phone_e164`, `domain`, `website`, `categories`, `description`; plus `lead.related.{emails,phones,domains,contacts}` when requested |
| flat merge tags | `{{ company_name }}`, `{{ city }}`, `{{ firstname }}`, `{{ email }}`, `{{ phone }}`, `{{ rating }}`, `{{ vat_number }}` … — snake_case, null-safe, spread at top level alongside `lead` |
| `salesperson` | `name`, `title`, `location`, `bio`, `photo_url`, `calendar_url` — matched from the URL slug against `salespersons` in the project's template config |

```liquid
{{ lead.name }} in {{ lead.city }} — {{ lead.rating }} from {{ lead.reviews_count }} reviews
Hi {{ firstname }}, a quick note for {{ company_name }}.
```

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

## See also

- `references/content.md` — page CRUD, blocks, custom fields
- Customer guide: https://publish.spideriq.ai/docs/building-your-site/dynamic-landing-pages
- API reference: https://publish.spideriq.ai/docs/api-reference/content
