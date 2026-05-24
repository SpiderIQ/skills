# recipes/idap-fill-from-form

Make a Form *populate the tenant's CRM* on submit. Wire each form field to a typed CRM column via `crm_target`, and use the 8 IDAP-anchored field types (url / country / region / postal_code / address / datetime / currency / place) so the value the form ships is structurally compatible with the column the CRM expects.

The form-fills-the-CRM premise: every IDAP column type needs a matching form field type that emits a typed, structured value. Without this map, an author can wire `crm_target` but the form ships a string blob into a column the CRM expects to hold a `place_id`, a country code, or a structured address — defeating the whole point of dual-write.

## When to use

- A tenant wants form submissions to land *in the CRM* (not just in the raw submissions audit), so SpiderMail / VayaPin / SpiderVerify can re-engage from the same row.
- The form collects structured data (address, country, currency, scheduled datetime, business place) — not just free text.
- You're migrating off Typeform and want one of: typed lead profile updates, lead-scoring fields, structured intake.
- A form question has a clean CRM home: `business website` → `norm_cli_*.businesses.website`, `country of incorporation` → `norm_cli_*.company_registry.country_code`, etc.

## The two pieces

| Piece | What it does | Where it lives |
|---|---|---|
| **`crm_target`** on a field | Wires that field's answer to `norm_cli_<tenant>.<resource_type>.<column>` on submit | `field.crm_target = { resource_type, column }` |
| **IDAP-anchored field types** | Make the field emit a *typed* value (ISO country code, structured address, currency `{amount, currency}`) so the column accepts it | `field.type = "url" \| "country" \| "region" \| "postal_code" \| "address" \| "datetime" \| "currency" \| "place"` |

Both are validated at publish time. If `field.type` is `text` and `column` is `country_code varchar(2)`, the form publish call returns `422 error_code="crm_target_invalid"` — the wrong field type would let `"United States"` reach a column that expects `"US"`.

## The 8 IDAP-anchored field types

Each is registered in the form renderer (input UX), validated at parse time (correct ISO shape, country-aware postal regex, etc.), and gated at publish-time against the column's `data_type`.

### `url`

Validated URL string (`https?://…`). Per-type config:

| Config | What it does |
|---|---|
| `url_variant: "website"` | Generic site URL — fits `businesses.website`, `domains.website_url`. |
| `url_variant: "linkedin_url"` | Restricted to `linkedin.com/in/…` paths — fits `contacts.linkedin_url`, `linkedin_profiles.linkedin_url`. |
| `url_variant: "domain"` | Hostname-only — fits `businesses.domain`, `domains.domain`. |
| `url_variant: "generic"` | Anything matching `https?://…` — fits any text-family CRM column. |

```
{ id: "website", type: "url", label: "Company website",
  url_variant: "website",
  crm_target: { resource_type: "businesses", column: "website" } }
```

CRM column shapes: text-family (`text` / `varchar` / `citext`).

### `country`

ISO 3166-1 alpha-2 (`"DE"`, `"US"`, `"AR"`). Per-type config:

| Config | What it does |
|---|---|
| (none required) | Picker rendered as a searchable dropdown of 250 ISO countries. |

```
{ id: "billing_country", type: "country", label: "Country",
  crm_target: { resource_type: "businesses", column: "country_code" } }
```

CRM column shapes: text-family. Especially `country_code varchar(2)` columns on `businesses`, `phones`, `linkedin_profiles`, `company_registry`.

### `region`

Text region / state / province. Optional ISO 3166-2 subdivision (`"US-CA"`, `"DE-BY"`) for tenants with a strict region-code requirement.

```
{ id: "state", type: "region", label: "State / region",
  crm_target: { resource_type: "businesses", column: "region" } }
```

CRM column shapes: text-family.

### `postal_code`

Normalised text with country-aware shape validation (US `\d{5}(-\d{4})?`, DE `\d{5}`, UK alphanumeric, …). The shape is picked from the form's `country` field answer or from the per-field default if there is no country answer.

```
{ id: "zip", type: "postal_code", label: "Postal code",
  crm_target: { resource_type: "businesses", column: "postal_code" } }
```

CRM column shapes: text-family.

### `address`

Structured JSON `{ street_line_1, street_line_2?, city, region?, postal_code?, country }`. Per-type config picks which components are required:

| Config | What it does |
|---|---|
| `address_required_components` | Array of `"street_line_1"`, `"street_line_2"`, `"city"`, `"region"`, `"postal_code"`, `"country"` — which components the form rejects if empty. Defaults to `["street_line_1", "city", "country"]`. |

```
{ id: "billing_address", type: "address", label: "Billing address",
  address_required_components: ["street_line_1", "city", "postal_code", "country"],
  crm_target: { resource_type: "company_registry", column: "address_line1" } }
```

CRM column shapes: text-family (single flat string when the column is `varchar`) **or** `jsonb` (full structured object when the column is `jsonb`). The dual-write picks the right shape per column type.

### `datetime`

ISO 8601 timestamp with timezone (`"2026-06-12T14:30:00Z"`). For day-only collection, the field flips to a date-only widget that lands as a `date` value.

```
{ id: "event_date", type: "datetime", label: "When is your event?",
  crm_target: { resource_type: "bookings", column: "slot_start" } }
```

CRM column shapes: `timestamp with time zone`, `date`.

### `currency`

Structured `{ amount: number, currency: ISO4217 }`. Per-type config:

| Config | What it does |
|---|---|
| `currency_mode: "amount_only"` | Single number input; uses `default_currency` for the ISO code. CRM column must be `numeric`. |
| `currency_mode: "with_picker"` | Amount input + currency picker (dropdown of 180 ISO currencies, or restricted via `currencies[]`). CRM column should be `jsonb` to hold both amount + ISO code. |
| `default_currency` | ISO 4217 three-letter code (e.g. `"USD"`). |
| `currencies` | Array of ISO 4217 codes to limit the picker to (e.g. `["USD", "EUR", "GBP"]`). |

```
{ id: "budget", type: "currency", label: "What's your budget?",
  currency_mode: "with_picker",
  default_currency: "USD",
  currencies: ["USD", "EUR", "GBP"],
  crm_target: { resource_type: "deals", column: "budget" } }
```

CRM column shapes: `numeric` (amount-only mode), `jsonb` (with-picker mode).

### `place`

Google Places payload `{ place_id, formatted_address, address_components, lat, lng }`. The richest IDAP type — anchored to a real Google Place ID so downstream personalization (`/lp/{slug}/{place_id}`) and SpiderMaps enrichment can re-use it.

| Config | What it does |
|---|---|
| `place_types` | Array of Google Place type filters (e.g. `["restaurant"]`, `["establishment"]`, `["geocode"]`). |

```
{ id: "business", type: "place", label: "Search for your business",
  place_types: ["establishment"],
  crm_target: { resource_type: "businesses", column: "google_place_id" } }
```

CRM column shapes: text-family (when storing only `place_id`) **or** `jsonb` (when storing the full payload).

#### Server-proxy behavior

The `place` field requires server-side Google Places lookup — the public API key is never shipped to the browser. The form renderer proxies `/api/v1/booking/{flow_id}/places/autocomplete` to the backend, which calls Google Places with the per-tenant `GOOGLE_PLACES_API_KEY`.

**Provisioning:**

- If `GOOGLE_PLACES_API_KEY` is set on the deployment, the field renders as a Google-Places-backed autocomplete.
- If it is **not** set, the field gracefully degrades to a free-text input, the `crm_target` writes the raw text, and the renderer surfaces a one-line `info` hint ("autocomplete unavailable — using free text") so authors know the lookup is offline.

If you need the autocomplete and don't see it on a deployment, talk to the platform admin about provisioning the key. Don't switch the field type to `text` — the IDAP type carries semantics the CRM column relies on (`place_id` is a natural key on `norm_cli_*.businesses`).

## CRM column shapes — quick map

The `column` you pass to `crm_target` must already exist on the per-tenant `norm_cli_<id>.<resource_type>` table. Below are the most common targets per field type — the [full IDAP ↔ field-type compat matrix](#full-compatibility-matrix) covers the rest.

| Field type | Typical CRM target (resource_type.column) |
|---|---|
| `url` (`url_variant: website`) | `businesses.website` · `domains.website_url` |
| `url` (`url_variant: linkedin_url`) | `contacts.linkedin_url` · `linkedin_profiles.linkedin_url` |
| `url` (`url_variant: domain`) | `businesses.domain` · `domains.domain` |
| `country` | `businesses.country_code` · `phones.country_code` · `linkedin_profiles.country_code` |
| `region` | `businesses.region` · `company_registry.region` |
| `postal_code` | `businesses.postal_code` · `company_registry.postal_code` |
| `address` | `company_registry.address_line1` (text) · `<custom_field jsonb>` (full struct) |
| `datetime` | `bookings.slot_start` · `<custom_field timestamptz>` |
| `currency` (amount-only) | `<custom_field numeric>` |
| `currency` (with-picker) | `<custom_field jsonb>` |
| `place` | `businesses.google_place_id` (place_id only) · `<custom_field jsonb>` (full payload) |
| `email` | `contacts.email` · `emails.email` |
| `phone` / `tel` | `contacts.phone_e164` · `phones.phone_e164` |
| `text` / `textarea` | any text-family column (`name`, `description`, `notes`, …) |
| `number` | any numeric column (`rating`, `lead_score`, `reviews_count`, …) |
| `checkbox` / `consent` | any boolean column (`deliverable`, `valid`, `is_*`) |

### Full compatibility matrix

The publish-time validator (`FIELD_TYPE_COLUMN_COMPAT`) gates `crm_target` against the column's `information_schema.columns.data_type`:

| Field type | Allowed PostgreSQL `data_type` |
|---|---|
| `text`, `email`, `textarea` | `text`, `character varying`, `citext` |
| `number` | `smallint`, `integer`, `bigint`, `numeric`, `real`, `double precision` |
| `date` | `date`, `timestamp with time zone` |
| `time` | `time without time zone`, `timestamp with time zone` |
| `phone`, `tel` | text-family |
| `checkbox`, `consent` | `boolean` |
| `select`, `picture_choice` | text-family + `jsonb` |
| `rating`, `nps`, `opinion_scale` | `smallint`, `numeric` |
| `file_upload` | text-family |
| `url` | text-family |
| `country` | text-family |
| `region` | text-family |
| `postal_code` | text-family |
| `address` | text-family + `jsonb` |
| `datetime` | `timestamp with time zone`, `date` |
| `currency` | `numeric`, `jsonb` |
| `place` | text-family + `jsonb` |
| `statement` | — (unmappable; the field has no value) |

A mismatch (e.g. `address` field targeting an `integer` column) is rejected at `form_publish` with `422 error_code="crm_target_invalid"`.

## End-to-end recipe — agency-intake form that fills the CRM

```
form_create({
  name: "Agency intake — new client kickoff",
  fields: [
    {
      id: "contact_name",
      type: "text",
      label: "Your name",
      required: true,
      crm_target: { resource_type: "contacts", column: "full_name" }
    },
    {
      id: "work_email",
      type: "email",
      label: "Work email",
      required: true,
      crm_target: { resource_type: "contacts", column: "email" }
    },
    {
      id: "company_website",
      type: "url",
      label: "Company website",
      required: true,
      url_variant: "website",
      crm_target: { resource_type: "businesses", column: "website" }
    },
    {
      id: "linkedin",
      type: "url",
      label: "Your LinkedIn",
      required: false,
      url_variant: "linkedin_url",
      crm_target: { resource_type: "contacts", column: "linkedin_url" }
    },
    {
      id: "billing_country",
      type: "country",
      label: "Billing country",
      required: true,
      crm_target: { resource_type: "businesses", column: "country_code" }
    },
    {
      id: "billing_address",
      type: "address",
      label: "Registered office address",
      required: true,
      address_required_components: ["street_line_1", "city", "postal_code", "country"],
      crm_target: { resource_type: "company_registry", column: "address_line1" }
    },
    {
      id: "kickoff_when",
      type: "datetime",
      label: "When can we kick off?",
      required: true
    },
    {
      id: "monthly_budget",
      type: "currency",
      label: "Monthly budget",
      required: true,
      currency_mode: "with_picker",
      default_currency: "USD",
      currencies: ["USD", "EUR", "GBP"]
    },
    {
      id: "office_location",
      type: "place",
      label: "Where is your main office?",
      required: false,
      place_types: ["establishment"],
      crm_target: { resource_type: "businesses", column: "google_place_id" }
    }
  ]
})
```

Each field with a `crm_target` writes into the matched CRM column on submit. Fields without a `crm_target` (`kickoff_when`, `monthly_budget` above) still land in the raw submissions audit (`public.results.data->'answers'`) — they're just not dual-written.

## What happens on submit

```
POST /api/v1/booking/{flow_id}/submit
{ "answers": { ... }, "consent": { "agreed_to_booking": true } }
```

1. The submit handler validates each answer against its field's structural shape (ISO country code? Valid URL?).
2. For each field with a `crm_target`, the handler maps the typed value into the right shape for the column type (`text-family` → string; `jsonb` → full struct; `numeric` → amount-only).
3. Within the submit transaction, the raw submission row lands in `public.results` (`worker_type='form'`, full answers JSONB).
4. The CRM sync cron picks up the row within 60s and UPSERTs each `crm_target` mapping into `norm_cli_<tenant>.<resource_type>` using the natural key of that table (e.g. `contacts.email`, `businesses.google_place_id`).

Downstream workers (SpiderMail outreach, SpiderVerify, VayaPin) see the updated row on their next pass — same as any other CRM mutation.

## Anti-patterns

- **Don't use `text` for a structured column.** A free-text "Country" answer landing in `country_code varchar(2)` will publish-fail at the `FIELD_TYPE_COLUMN_COMPAT` gate. Use `country`.
- **Don't wire `crm_target` to a column that doesn't exist** on the tenant's `norm_cli_*` schema. The publish-time validator returns `422 error_code="crm_target_invalid"` listing the missing column.
- **Don't store a `place` payload's `formatted_address` into `businesses.address`** — wire the typed payload (or its `place_id`) and let the CRM sync cron unpack it. `place` carries `lat/lng/address_components` the CRM uses to enrich downstream.
- **Don't assume `place` autocomplete is on every deployment.** When `GOOGLE_PLACES_API_KEY` is not provisioned the field falls back to free text — design the form so the downstream CRM column accepts both shapes (or accept that on those deployments the column gets the user's typed string).
- **Don't use `currency_mode: "amount_only"` against a `jsonb` column.** The dual-write writes a bare number; the CRM ends up with a JSON number instead of `{amount, currency}`. Pair `amount_only` with `numeric`, `with_picker` with `jsonb`.

## See also

- [recipes/build-lead-gen-form](../build-lead-gen-form/SKILL.md) — end-to-end form pipeline (this recipe drops in the `crm_target` and IDAP fields)
- [recipes/design-a-form](../design-a-form/SKILL.md) — themes / token overrides / per-question media
- [core-skills/forms/SKILL.md](../../core-skills/forms/SKILL.md) — full `form_*` tool catalog (20 tools)
- [examples/idap-fill-from-form.sh](../../examples/idap-fill-from-form.sh) — runnable bash version of the agency-intake recipe
