# Integrations & import — Airtable, cal.com, Cloudflare, HubSpot, Stripe, IDAP, clone, directory

> **REQUIRES — read before you plan.**
> **Package:** mixed — see the split below.
> **Tools:** `import_from_url` `directory_import_from_idap` `content_import_openapi` `content_import_markdown` (any universe) · cal.com wiring rides the booking surface (kitchen sink)
> **Needs `deploySite`.** Templates, theme files and the deploy-time `_config.json` overlay live in per-tenant KV and only change on deploy — unlike content, which is live on publish.
> **Not sure which universe you are in?** SKILL.md → *Step 0*.


Outside-system bridges and importers. Each integration has its own auth (the third-party's key,
configured per-tenant) layered on the SpiderPublish PAT. Clone (public URL → Liquid template)
and the directory-listings importer live here too because they're "bring outside content in"
flows. Directory imports hit the bulk listings endpoint, not a 50× page loop.

**Read when:** syncing Airtable → directory, wiring a cal.com booking flow, setting up a custom
domain via Cloudflare, mirroring a form to HubSpot, building a Stripe pricing table, filling a
form from an IDAP record, cloning a public URL or Tailwind page into a template, or bulk-importing
directory listings.


---

## Sync To Directory

Mirror an outside system — an Airtable view, a Google Sheet, a partner feed — into SpiderPublish
directory listings with `directory_bulk_upsert_listings`. One-shot import or a cron you drive.

### 🔴 Read this before you design the sync

**Idempotency is by `slug`, within a category.** The unique index on `content_directory_listings`
is **`(category_id, slug)`**. That pair is the whole matching rule.

There is **no `external_id` column** — not on the table, not in `directory_service.py`, not in any
tool schema. There is **no `on_conflict` parameter** anywhere. A sync designed around an external
idempotency key has nothing to key on and will duplicate every row on the second run.

**So: derive a STABLE slug from a stable source field, and treat it as the primary key.**

```
   Airtable "Slug" column (never edited)  ──▶  listing.slug  ──▶  (category_id, slug) UPSERT
   Airtable record id "rec…"              ──▶  listing.data.airtable_record_id   (provenance only)
```

Put the source record id in the listing's **`data` JSONB** so you can audit provenance, and use
**`source_job_id`** when the rows came from a SpiderIQ job. Neither is an idempotency key; both are
audit trails.

⚠️ **Slug stability is the whole game.** If your slug derives from a name the client edits, the
next sync creates a *second* listing at a new URL and leaves the old one published. Use a
dedicated, never-edited slug column in the source.

### When to use

- A client maintains their canonical service list outside SpiderPublish and wants it published as
  programmatic-SEO directory pages.
- Recurring sync: the outside system is the source of truth, SpiderPublish renders and serves.
- Initial migration: 50–5000 rows into a tenant directory in one job.

**Not this recipe if the data is already in SpiderIQ.** For the tenant's own IDAP corpus, one call
does the whole thing — `directory_import_from_idap`, see *IDAP → directory* below and
[`directory-pages.md`](directory-pages.md).

### Prerequisites

- Read access to the source (e.g. an Airtable Personal Access Token for the base).
- A SpiderPublish PAT scoped to the tenant.
- A **category** already created — `directory_create_category(name="Plumbers", slug="plumbers")`.
  Listings hang off it and the calls below address it by **`category_slug`**, never by a UUID.
- A field map: which source columns become `name`, `slug`, `city`, `state`, `phone`, `website`,
  `rating`, `review_count`, and what goes in `data`.

### Step 1 — pull from the source

```python
import requests

AIRTABLE_PAT = "<your-pat>"
BASE_ID      = "appXXXXXXXXXXXX"
TABLE_NAME   = "Listings"
VIEW_NAME    = "Published"            # filter to "ready to publish" rows

url     = f"https://api.airtable.com/v0/{BASE_ID}/{TABLE_NAME}"
params  = {"view": VIEW_NAME, "pageSize": 100}
headers = {"Authorization": f"Bearer {AIRTABLE_PAT}"}

records = []
while True:
    r = requests.get(url, params=params, headers=headers).json()
    records.extend(r.get("records", []))
    if "offset" not in r:
        break
    params["offset"] = r["offset"]
```

Airtable rate-limits at 5 req/sec per base — 5000 rows is about 17s serially. Do not parallelise
the page reads.

### Step 2 — map to the listing shape

```python
listings = [
    {
        "name":         r["fields"]["Name"],
        "slug":         r["fields"]["Slug"],          # STABLE. never derived from Name.
        "description":  r["fields"].get("Description", ""),
        "city":         r["fields"]["City"],          # drives city_slug, derived server-side
        "state":        r["fields"].get("State"),
        "address":      r["fields"].get("Address"),
        "phone":        r["fields"].get("Phone"),
        "website":      r["fields"].get("Website"),
        "rating":       r["fields"].get("Rating"),
        "review_count": r["fields"].get("ReviewCount"),
        "data": {                                     # anything else — free-form JSONB
            "hours":               r["fields"].get("Hours"),
            "airtable_record_id":  r["id"],           # provenance, NOT an idempotency key
        },
    }
    for r in records
]
```

🔴 **`city_slug` is not yours to set.** It is derived server-side from `city` + `state`
(`'Miami Beach'` + `'Florida'` → `miami-beach-florida`). There is no city field to pass.

### Step 3 — bulk upsert

```
directory_bulk_upsert_listings({
  category_slug: "plumbers",       # SLUG, not a UUID. required.
  listings:      listings          # required.
})
```

The call matches each row on `(category, slug)` and UPDATEs on a hit, INSERTs on a miss. Rows
default to `status='published'` — **there is no publish step.**

**5000 listings per call.** Above that, paginate; a larger single call risks a transaction timeout.

### Step 4 — handle disappearances yourself

The upsert **never removes anything**. A row deleted from the source view stays published forever.

```python
source_slugs = {l["slug"] for l in listings}
live = directory_list_listings({"category_slug": "plumbers", "status": "published"})
for l in live["listings"]:
    if l["slug"] not in source_slugs:
        directory_upsert_listing({
            "category_slug": "plumbers",
            "slug":          l["slug"],
            "status":        "archived",      # never deletes; reversible
        })
```

🔴 **There is no `directory_archive_listing` tool.** Archiving is `directory_upsert_listing` with
`status: "archived"` — the column's CHECK constraint allows `draft | published | archived`.

*(For an **IDAP** source this step is a built-in: `directory_import_from_idap(..., prune=true)`
archives everything the import did not produce, and refuses rather than guess on an empty or
limit-truncated result set. `prune` is IDAP-only — it has no equivalent on bulk upsert, because the
platform cannot know what your source contained.)*

### Step 5 — nothing to deploy

Directory pages render at request time. Once the rows land they are live (~60s edge cache), at

```
/{directory_base}/{category_slug}/{city_slug}/{listing_slug}
```

`{directory_base}` defaults to `directory` and is renamable per tenant — never hard-code
`/directory/`. **Only a template change needs a deploy** (see
[`deploy-protocol.md`](deploy-protocol.md)).

### The full loop

```python
records  = pull_airtable_view(BASE_ID, TABLE_NAME, VIEW_NAME)
listings = map_to_listing_shape(records)                       # stable slugs

result = directory_bulk_upsert_listings(
    category_slug="plumbers", listings=listings)               # ≤5000 per call

archived = archive_missing("plumbers", {l["slug"] for l in listings})

print(f"upserted: {result}, archived: {archived}")
```

Wrap it in a cron (`0 2 * * * /usr/local/bin/sync-airtable-to-spideriq.py`). **Nothing schedules
this for you** — there is no sync pipeline on the platform side.

### Verify

```
directory_list_listings({ category_slug: "plumbers", limit: 5 })
# → confirm recent items match the source, and that `data` carries what you put there

content_visual_check({
  page_url: "https://<tenant>/directory/plumbers/miami-florida/acme-plumbing",
  viewport: "desktop"
})
```

🔴 **Count the keys; do not eyeball the page.** Directory templates run values through `| default:`
chains, so an absent field and an empty one render identically. Read a listing back through
`directory_list_listings` before trusting a screenshot.

### Gotchas

- **A slug change is a new listing.** The old one keeps serving at the old URL. Archive it, or use
  a slug column the client never edits.
- **`data` is not typed.** Nothing validates its shape; a renamed key silently blanks whatever the
  template read.
- **A re-import overwrites editorial fixes.** The listing is a copy the CMS owns and anyone can
  edit; the next sync writes over it.
- **Two categories may hold the same slug.** The pair `(category_id, slug)` is unique, not the slug
  alone. Sync per category and keep the category straight.

### Anti-patterns

- **Looping `directory_upsert_listing` per row** instead of bulk-upserting. 5000 round trips
  vs 1.
- **Designing around `external_id` / `on_conflict`.** Neither exists. Every run duplicates.
- **Deriving the slug from an editable name field.** Guarantees drift.
- **Hard-coding `/directory/`** in generated links. It is `{directory_base}`.
- **Hard-coding the source PAT client-side.** It reads every row; keep it server-side.
- **Forgetting Step 4.** Listings linger forever when source rows disappear.

### See also

- [`directory-pages.md`](directory-pages.md) — the directory model end to end: categories, the
  URL shape, `directory_base`, SEO templates, the sitemap, and the IDAP one-call importer
- [`dynamic-collections.md`](dynamic-collections.md) — the FLAT layout over the same listings
- [`tool-surface.md`](tool-surface.md) — the `directory_*` tool family

---

## Booking Flow

End-to-end: cal.com event type → SpiderPublish `kind='booking'` flow with staff calendar invites. The cal.com side provides the calendar pool + availability engine; SpiderPublish provides the public `/f/<flow_id>` booking surface + theme + custom fields.

### When to use

- The tenant uses cal.com internally for team scheduling and wants a branded public booking page.
- Multi-staff round-robin booking ("the next available account exec") — cal.com handles the pool, SpiderPublish renders the form.
- Replacing the default cal.com landing page with a SpiderPublish-themed flow that asks custom intake questions before slot selection.
- Pattern: "cal.com is the calendar engine; SpiderPublish is the front door."

### Prerequisites

- A cal.com team account with an Event Type configured.
- cal.com API key (org-level, with `event-types:read` and `team-members:read` scopes).
- A SpiderPublish PAT scoped to the tenant.
- Staff emails ready (the cal.com team members who'll receive booking notifications).

### Step 1 — Pull the cal.com event type

```python
import requests

CAL_API_KEY = "cal_live_..."
EVENT_TYPE_ID = 12345

r = requests.get(
    f"https://api.cal.com/v1/event-types/{EVENT_TYPE_ID}",
    params={"apiKey": CAL_API_KEY}
).json()

event = r["event_type"]
# Returns:
# {
#   id, title, slug, description, length, schedulingType, hosts,
#   customInputs, locations, requiresConfirmation, ...
# }
```

### Step 2 — Create the SpiderPublish booking flow

```
form_create({
  name: event.title,
  kind: "booking",
  flow: {
    title:               event.title,
    description:         event.description,
    duration_minutes:    event.length,
    scheduling_type:     event.schedulingType,    # "ROUND_ROBIN" | "COLLECTIVE" | "MANAGED"
    calendar_pool_slug:  "<tenant-pool>",         # set up via cal.com team
    cal_event_type_id:   event.id,                # critical — wires the SP flow to the cal.com event
    fields: [
      // Intake questions (asked BEFORE slot selection)
      { id: "company", label: "Company", type: "short_text", required: true },
      { id: "size",    label: "Team size", type: "single_choice",
        choices: [{label: "1-10"}, {label: "11-50"}, {label: "51+"}] }
    ],
    requires_confirmation: event.requiresConfirmation
  },
  theme: { preset: "fullscreen-dark" }
})
# → { flow_id: "flow_..." }
```

The flow `kind='booking'` triggers booking-specific runtime: the public `/f/<flow_id>` URL shows the intake fields first, then a slot-picker grid pulled from cal.com.

### Step 3 — Invite staff (calendar pool wire-up)

Each staff member needs to:
1. Receive a per-staff invite token from SpiderPublish.
2. Click the email link → OAuth their calendar (Google / Outlook / iCloud) into the pool.
3. Their availability then surfaces in the slot grid on `/f/<flow_id>`.

```
# As of 2026-05-24, this is REST-only — see invite-staff-calendar.md for the MCP-gap note
POST /api/v1/booking/flows/<flow_id>/staff/invite
{
  "emails": ["alice@acme.com", "bob@acme.com", "carol@acme.com"]
}
# → emails sent; tokens persist with status="invited"
```

See [`../../booking/invite-staff-calendar.md`](forms-booking.md#invite-staff-calendar) for the full staff-invite recipe (verify endpoint, list staff, re-invite).

### Step 4 — Confirm cal.com ↔ SpiderPublish wiring

After staff connect their calendars:

```
booking_flow_get({ flow_id })
# → { ..., connected_staff_count: 3, cal_event_type_id: 12345, calendar_pool_slug: "<pool>" }

# Spot-check: visit /f/<flow_id> in a browser
# → intake questions appear first
# → after submit, slot grid populates with available 30-min slots from the cal.com pool
```

If the slot grid is empty:
- Confirm at least one staff member's `connected_at` is non-null (see [`../../booking/invite-staff-calendar.md`](forms-booking.md#invite-staff-calendar))
- Confirm `cal_event_type_id` matches the live cal.com event
- Confirm the cal.com event's availability schedule has slots in the next 14 days

### Step 5 — Publish + embed

```
form_publish({ flow_id })              # safe-default gated
form_preview_url({ flow_id })          # → https://<tenant>/f/<flow_id>
```

To embed on an external site:

```
form_get_embed_snippet({ flow_id, mode: "inline" })
# → "<div data-spiderflow-flow=\"flow_...\"></div><script src=\"https://embed.spideriq.ai/v1/loader.js\" async></script>"
```

For embed inside a SpiderPublish page, see [`../../booking/form-as-page-section.md`](forms-booking.md#form-as-page-section).

### Steps — full flow

```python
1. event = pull_cal_event_type(EVENT_TYPE_ID)
2. flow  = form_create(kind="booking", cal_event_type_id=event.id, ...)
3. invite_staff(flow_id=flow.id, emails=[...])
4. (staff click email → OAuth) — out of band
5. verify: booking_flow_get(flow.id).connected_staff_count > 0
6. form_publish(flow.id)
7. form_preview_url(flow.id) → share / embed
```

### Gotchas

- **cal.com and SpiderPublish use DIFFERENT IDs.** `cal_event_type_id` is cal.com's `id`; SpiderPublish stores it as a reference. Don't try to use one for the other.
- **Slot grid is live-pulled from cal.com on every page load.** No caching on the SpiderPublish side — if cal.com is down, the form shows a "no slots available" empty state with a retry message.
- **Booking confirmation routing**: the booking confirmation email (with calendar invite) is sent by **cal.com**, not SpiderPublish. SpiderPublish sends an optional "thank you" email; cal.com sends the actual `.ics`.
- **`requires_confirmation: true`** means booked slots are tentative until an admin clicks "confirm" in cal.com. Surface this in the SpiderForms thank-you screen so visitors know to expect a follow-up.
- **Pool members vs flow staff.** A cal.com team can have 20 members; you might want only 5 in this flow's pool. Configure the pool in cal.com first, then reference its slug from SpiderPublish.
- **Time zones.** cal.com handles TZ conversion based on visitor's browser. SpiderPublish passes through; don't try to second-guess.
- **Multi-event-type bookings** (visitor picks "30-min intro" OR "60-min deep dive") need ONE flow per event type. Cluster them via a "service picker" page that routes to /f/<flow_id_30min> vs /f/<flow_id_60min>.

### Verify

```
booking_flow_get({ flow_id })
# → confirm cal_event_type_id, connected_staff_count > 0

content_visual_check({
  page_url: f"https://<tenant>/f/{flow_id}",
  viewport: "desktop"
})
# → assert dom.shadow_hosts.includes("spideriq-form") (Rule 62)
# → body_text_preview should show the intake field labels

# Submit a real test booking (use a staff member's calendar that you control)
# → confirm:
#   - cal.com sends the calendar invite
#   - the slot is marked busy in cal.com
#   - SpiderPublish thank-you email fires (if configured)
```

### Anti-patterns

- **Trying to skip cal.com and use SpiderPublish alone for calendar management.** SpiderPublish doesn't have an availability engine. cal.com is the calendar primitive; SpiderPublish is the surface.
- **Hardcoding `cal_event_type_id` in client-side code.** It lives in the flow row, not in the embed snippet. The embed loader reads it server-side at render time.
- **Inviting staff before publishing the flow.** Invites work on draft flows but tokens reference the flow_id; if you delete + recreate the flow, the tokens orphan.
- **Embedding the cal.com native widget alongside the SpiderForms booking flow.** Confuses visitors + double-books cal.com slots.
- **Forgetting the `requires_confirmation` surface.** Visitors book, expect immediate confirmation, get a "tentative" email instead.

### See also

- [`../../booking/clone-booking-template.md`](forms-booking.md#clone-booking-template) — start from a booking template; same primitive, less boilerplate
- [`../../booking/invite-staff-calendar.md`](forms-booking.md#invite-staff-calendar) — the staff-invite flow in detail (with its MCP-gap REST fallback)
- [`../../booking/form-as-page-section.md`](forms-booking.md#form-as-page-section) — embed inside a SpiderPublish page
- [`../../booking/test-form-submission.md`](forms-booking.md#test-form-submission) — verify the booking end-to-end
- [`../../reference/booking-model.md`](booking-model.md) — the `booking_flows` schema, `/f/<id>` URL surface, cal.com / OAuth-by-invite spec


---

## Custom Domain

End-to-end: connect a client's custom domain (e.g. `acme.com`) to their SpiderPublish tenant. Cloudflare for SaaS handles the SSL/TLS + edge routing; SpiderPublish writes the dispatch binding. The recipe covers DNS verification, certificate issuance, and the post-attach visual check.

### When to use

- A tenant is moving from `<slug>.sites.spideriq.ai` to their own domain.
- An agency is white-labelling SpiderPublish — every client gets their own domain.
- Multi-domain tenants (e.g. `acme.com` + `acme.de` + `acme.fr`) pointing at the same SpiderPublish tenant.
- Pattern: "make this domain serve their SpiderPublish site."

### Prerequisites

- Domain control: ability to add DNS records at the registrar level (registrar dashboard OR access to the existing CF zone).
- SpiderPublish PAT scoped to the tenant.
- Cloudflare for SaaS configured in the SpiderPublish dispatch — this is platform infrastructure, already wired; you just consume it.

### The two flavours of domain attach

| Flavour | When | DNS setup |
|---|---|---|
| **CNAME** (preferred for apex-less + subdomains) | Tenant uses `www.acme.com` or `app.acme.com` | One CNAME record pointing at SpiderPublish's CF for SaaS hostname (`<tenant-slug>.cf.spideriq.ai` or similar) |
| **A record** (for apex `acme.com`) | Tenant wants `acme.com` (no www) | Two A records to CF's anycast IPs (provided by the SpiderPublish onboarding step) |

CNAME is operationally simpler and recommended. Push back gently on "I want it on the apex" — the CF for SaaS apex flow involves DNS-CNAME-flattening or registrar-level changes.

### Step 1 — Register the domain in SpiderPublish

This creates the `content_domains` row + triggers CF for SaaS to provision the certificate:

⚠️ **The response shapes in this recipe are illustrative, not a contract.** The tool NAMES below are
correct and registered in every universe — `content_add_domain`, `content_verify_domain`,
`content_list_domains`, `content_set_primary_domain`, `content_delete_domain` — but read each tool's
own schema for its real arguments and return fields rather than the comments here.

```
content_add_domain({
  domain:         "www.acme.com",
  is_primary:     true,                       # the canonical domain for SEO + redirects
  redirect_apex:  true                         # 301 acme.com → www.acme.com
})
# → {
#     dry_run: true,                          # safe-default gated
#     preview: {
#       domain: "www.acme.com",
#       cname_target: "<tenant>.cf.spideriq.ai",
#       verification_status: "pending"
#     },
#     confirm_token: "cft_..."
#   }

content_add_domain({
  domain: "www.acme.com",
  ...,
  confirm_token: "cft_..."
})
# → { success: true, domain: "www.acme.com", verification_status: "pending", cname_target: "..." }
```

### Step 2 — Add the DNS record at the registrar

Give the tenant the exact record to add:

| Type | Name | Value | TTL |
|---|---|---|---|
| `CNAME` | `www` | `<tenant>.cf.spideriq.ai` (from the response above) | Auto / 300 |

For apex (`acme.com` no www):

| Type | Name | Value |
|---|---|---|
| `A` | `@` | `198.51.100.10` (first CF for SaaS anycast IP) |
| `A` | `@` | `198.51.100.11` (second IP) |

Tenants editing their own DNS at the registrar:
- Cloudflare-managed zone: change in the CF dashboard → DNS tab → Add record
- Other (Namecheap, GoDaddy, Route53): registrar's DNS settings panel

### Step 3 — Wait for DNS propagation + CF cert issuance

```
content_verify_domain({ domain: "www.acme.com" })
# → {
#     verification_status: "pending" | "verified" | "failed",
#     dns_propagation: { record_found: true, last_checked: "..." },
#     cert_status: { state: "pending_validation" | "active" | "failed" }
#   }
```

Typical timing:
- DNS propagation: 30 seconds (registrar's TTL) to 48 hours (TTL inheritance of upstream resolvers)
- CF certificate issuance: 5-15 minutes after DNS verifies via HTTP-01 challenge

Re-check every 60 seconds; expect `verified` + `cert_status.state == "active"` within 15-20 minutes.

### Step 4 — Test from the edge

Once `verified`, eyeball the domain:

```bash
curl -sI "https://www.acme.com"
# HTTP/2 200
# server: cloudflare
# cf-ray: ...
# strict-transport-security: max-age=...
```

Then the deeper render check:

```
content_visual_check({
  page_url: "https://www.acme.com",
  viewport: "desktop"
})
# → body_text_preview should match the tenant's home page
# → for form-bearing pages: dom.shadow_hosts.includes("spideriq-form") (Rule 62)
```

If you get a 525 / 526 / 522 from CF: the cert isn't valid (yet). Re-check `content_verify_domain` and wait.

### Step 5 — Redirect the apex (if applicable)

If you attached `www.acme.com` as primary, ensure `acme.com` 301-redirects to it:

```
content_add_domain({
  domain:        "acme.com",
  is_primary:    false,
  redirect_to:   "www.acme.com"
})
```

CF for SaaS handles the redirect at edge — no SpiderPublish code involvement.

### Steps — full flow

```python
1. content_add_domain(domain="www.acme.com", is_primary=True)
                                       # safe-default gated; preview + confirm
2. (send tenant the CNAME instruction)
3. (tenant adds CNAME at registrar)
4. poll content_verify_domain until verified + cert active
5. content_visual_check(page_url="https://www.acme.com")
6. (optional) content_add_domain("acme.com", redirect_to="www.acme.com")
```

### Gotchas

- **CF for SaaS HTTP-01 challenge** requires DNS to be live BEFORE cert issuance. If you create the domain row but the CNAME isn't published, cert stays `pending_validation` forever.
- **Existing CF zone on the domain**: if the registrar's nameservers are already CF's, the customer must add the CNAME inside that CF zone (their DNS UI), NOT delete CF first. Removing CF then re-adding will break their email + other records.
- **CAA records**: a tenant with `CAA 0 issue "letsencrypt.org"` blocks CF's cert provider. Either add CAA for CF (`0 issue "comodoca.com"` and `0 issue "digicert.com"`) or remove the CAA.
- **DNSSEC drift**: domains with DNSSEC enabled at the registrar but no DS record at the parent zone respond intermittently with SERVFAIL. Check `dig +dnssec www.acme.com`.
- **`is_primary: true` matters for SEO.** All non-primary domains 301 to the primary. Set wrong primary = canonical-URL mismatch + crawl waste.
- **DNS propagation lies.** `dig` from your terminal may show the new record; the tenant's ISP cache may still serve the old record for hours. Always sanity-check from an edge probe (CF's DNS-over-HTTPS) or wait 24h.
- **The MCP tool `content_add_domain` is Phase 11+12 gated** — preview shows you the CNAME target. Don't skip the preview; copy-paste errors on CNAME values are the #1 onboarding failure mode.

### Verify

```
content_verify_domain({ domain: "www.acme.com" })
# → { verification_status: "verified", cert_status: { state: "active" } }

content_list_domains()
# → [{ domain: "www.acme.com", is_primary: true, cert_status: "active" }, ...]

# Edge probe
curl -sI "https://www.acme.com" | head -5
# HTTP/2 200
# server: cloudflare
```

### Anti-patterns

- **Telling the tenant "just point your domain at us" without specifying CNAME vs A.** They'll guess wrong and spend a day debugging.
- **Skipping `content_add_domain` and just adding the DNS record.** CF for SaaS routes by hostname; without the SpiderPublish-side row, the request hits CF but no Worker handles it → 522.
- **Setting two domains as `is_primary: true`.** Only one can be primary per tenant; the system rejects the second. SEO chaos otherwise.
- **Removing the original `.sites.spideriq.ai` URL.** Keep it active as a fallback during DNS transitions; useful for debugging.
- **Trying to issue your own cert via Let's Encrypt.** CF for SaaS handles certs; competing cert lifecycles cause renewal failures.
- **Forgetting the visual-check post-attach.** A 200 from `curl` only proves CF is responding; the visual-check confirms YOUR tenant's pages are rendering (not a stale CF "no Worker bound" 522 page).

### See also

- [`../../content/custom-domain.md`](integrations.md#custom-domain) — generic custom-domain attach flow (this recipe is its Cloudflare-specialised twin with onboarding context)
- [`../../audit/visual-check-a-page.md`](audit.md#visual-check-a-page) — verification primitive used in Step 4
- [`../../reference/deploy-protocol.md`](deploy-protocol.md) — the safe-default gate on `content_add_domain`
- [`../../reference/tool-surface.md`](tool-surface.md) — the `content_*_domain` tool family


---

## Form Mirror

Mirror a HubSpot form into a SpiderPublish `kind='form'` flow — for tenants migrating off HubSpot or running parallel surfaces. Mapping is one-way (HubSpot → SpiderForms); submissions on the mirrored form route back to HubSpot via webhook.

### When to use

- The tenant has 12 HubSpot forms in production and wants to migrate to SpiderForms without rewriting each by hand.
- Running a SpiderForms surface (faster, custom-themed) while keeping HubSpot as the CRM/marketing-automation backend.
- A/B testing the SpiderForms UX against the HubSpot embed without changing the data destination.
- Pattern: "HubSpot is the data home; SpiderForms is the prettier surface."

### Honest framing

- This is a **one-time-or-periodic mirror**, not a live sync. HubSpot is the source of truth for form *structure*; SpiderForms is the source of truth for form *experience*.
- HubSpot's form schema is rich (calculated fields, smart fields, dependent fields, GDPR consent blocks); SpiderForms covers the common 80%. Expect ~80% of fields to map cleanly; the rest need manual conversion or omission.
- Submissions on the SpiderForms surface POST back to HubSpot's `/submissions/v3/integration/submit` endpoint via a server-side webhook on the SpiderForms flow.

### Prerequisites

- A HubSpot Private App access token with `forms` scope.
- The HubSpot form's `formId` (UUID from HubSpot dashboard URL).
- A SpiderPublish PAT scoped to the tenant.
- HubSpot portal ID (for the submission webhook URL).

### Step 1 — Pull the HubSpot form

```python
import requests

HS_TOKEN = "pat-na1-..."
FORM_ID  = "abc-def-..."

r = requests.get(
    f"https://api.hubapi.com/marketing/v3/forms/{FORM_ID}",
    headers={"Authorization": f"Bearer {HS_TOKEN}"}
)
hs_form = r.json()

# Returns:
# {
#   id, name, fieldGroups: [{fields: [{name, label, fieldType, required, options, ...}]}],
#   submitButton, redirectUrl, notifications, ...
# }
```

### Step 2 — Map fields

| HubSpot `fieldType` | SpiderForms type | Notes |
|---|---|---|
| `single_line_text` | `short_text` | Direct |
| `multi_line_text` | `long_text` | Direct |
| `email` | `email` | Direct (with format validation) |
| `phone` | `phone` | Direct |
| `number` | `number` | Direct (min/max from HubSpot validations) |
| `date` | `date` | Direct |
| `single_checkbox` | `boolean` | Yes/no semantics; HubSpot's "consent" subtype maps to `gdpr_consent` SpiderForms field |
| `multiple_checkboxes` | `multiple_choice` | Options array maps 1:1 |
| `dropdown` | `single_choice` (dropdown variant) | Options array maps 1:1 |
| `radio` | `single_choice` (radio variant) | Same |
| `file` | `file_upload` | Direct (size limit aligns to SpiderForms tenant config) |
| `calculation` | **NOT SUPPORTED** | Omit; compute server-side after submission |
| `smart_field` (progressive profiling) | **NOT SUPPORTED** | Omit; use SpiderForms variables to approximate |

```python
def map_hubspot_field(hs_field):
    SUPPORTED = {
        "single_line_text": "short_text",
        "multi_line_text":  "long_text",
        "email":            "email",
        "phone":            "phone",
        "number":           "number",
        "date":             "date",
        "single_checkbox":  "boolean",
        "multiple_checkboxes": "multiple_choice",
        "dropdown":         "single_choice",
        "radio":            "single_choice",
        "file":             "file_upload"
    }
    if hs_field["fieldType"] not in SUPPORTED:
        return None    # skip unsupported types; log them

    return {
        "id":          hs_field["name"],
        "type":        SUPPORTED[hs_field["fieldType"]],
        "label":       hs_field["label"],
        "required":    hs_field.get("required", False),
        "placeholder": hs_field.get("placeholder", ""),
        "choices":     [{"label": o["label"], "value": o["value"]}
                        for o in hs_field.get("options", [])]
    }

sp_fields = [
    f for f in (map_hubspot_field(hf) for fg in hs_form["fieldGroups"] for hf in fg["fields"])
    if f is not None
]
unsupported = [
    hf for fg in hs_form["fieldGroups"] for hf in fg["fields"]
    if hf["fieldType"] not in {"single_line_text", "multi_line_text", "email", ...}
]
print(f"Mapped {len(sp_fields)} fields; skipped {len(unsupported)} unsupported")
```

### Step 3 — Create the SpiderForms flow

```
form_create({
  name:  hs_form.name,
  kind:  "form",
  flow: {
    title:    hs_form.name,
    fields:   sp_fields,
    submit_button_text: hs_form.submitButton.text || "Submit"
  },
  theme: { preset: "card-light" }     // or whatever matches the tenant brand
})
# → { flow_id: "flow_..." }
```

### Step 4 — Wire the submission webhook back to HubSpot

Submissions on the SpiderForms flow must POST to HubSpot to keep the CRM in sync:

```
form_update({
  flow_id: "<flow_id>",
  changes: {
    submission_destinations: [
      {
        type: "webhook",
        url:  f"https://api.hsforms.com/submissions/v3/integration/submit/{PORTAL_ID}/{FORM_ID}",
        payload_template: {
          "fields": [
            { "name": "{{field_id}}", "value": "{{field_value}}" }
          ],
          "context": {
            "pageUri":  "{{submission_page_url}}",
            "pageName": "{{submission_page_title}}"
          }
        }
      }
    ]
  }
})
```

The webhook fires on every submission, mapping SpiderForms field IDs back to HubSpot field names. **Field IDs MUST match HubSpot's internal names** (which is why we used `hs_field["name"]` as the SpiderForms field `id` in Step 2).

### Step 5 — Publish + embed

```
form_publish({ flow_id })            # safe-default gated
form_get_embed_snippet({ flow_id })  # for external sites
# OR embed into a SpiderPublish page — see ../../booking/form-as-page-section.md
```

### Steps — full flow

```python
1. hs_form = pull_hubspot_form(FORM_ID)
2. sp_fields, unsupported = map_fields(hs_form)
3. (audit unsupported; decide skip vs manual port)
4. flow = form_create(name, fields=sp_fields, ...)
5. form_update(flow_id=flow.id, submission_destinations=[hubspot_webhook])
6. form_publish(flow_id=flow.id)
7. (embed or share via /f/<flow_id>)
8. (test submission lands in HubSpot's responses dashboard)
```

### Gotchas

- **HubSpot's "dependent fields" (show field X if Y is checked) need manual rebuild** as SpiderForms conditional logic via `form_add_logic_rule`. Audit which HubSpot fields have `dependentFieldFilters` and port them by hand.
- **GDPR consent blocks are critical.** HubSpot has explicit `consent` field types; SpiderForms requires you to add a `boolean` field labelled appropriately + a separate "subscription preferences" question. Don't strip GDPR consent — surface it explicitly.
- **HubSpot's `fieldType` enum is larger than this mapping covers** (~25 types vs the ~12 mapped). Always log the `unsupported` list and surface it to the user.
- **Webhook signature verification** — HubSpot's submit endpoint accepts any POST; consider adding HMAC signing to the SpiderForms webhook payload if you need end-to-end auth.
- **Field-name uniqueness across HubSpot fieldGroups.** HubSpot allows duplicate `name` values across groups; SpiderForms requires unique field IDs per flow. Detect duplicates pre-create.
- **HubSpot UI's "smart fields" / progressive profiling** isn't easily mirrored — those depend on HubSpot's visitor cookie tracking. Skip; rely on SpiderForms' own variable-substitution if needed.

### Verify

```
form_get({ flow_id })
# → confirm field list matches the HubSpot form (minus skipped types)

# Test submit + verify it lands in HubSpot
form_test_submit({ flow_id, answers: {"email": "qa@example.com", ...} })

# Then check HubSpot's contacts dashboard for the test contact
# (or use HubSpot CRM API to query the most recent submission)
```

### Anti-patterns

- **Mirroring without checking the unsupported-types list.** Sweeping `calculation` and `smart_field` away silently breaks compliance + UX flows you didn't realize existed.
- **Skipping the webhook wire-up.** SpiderForms collects submissions in its own response table; HubSpot has no idea. CRM users wonder where the leads went.
- **Mapping HubSpot `single_checkbox` for GDPR consent → SpiderForms `boolean` without explicit labeling.** Compliance teams will reject — surface the consent semantics in the field label + add a separate subscriptions question.
- **Using HubSpot's CDN-hosted CSS classes in the SpiderForms theme.** SpiderForms has its own theme system; don't try to reuse HubSpot's styling unless you've explicitly imported the tokens.
- **One-time mirroring then editing both surfaces.** Pick a source of truth: re-pull HubSpot → SpiderForms periodically, or commit to SpiderForms as source and stop editing HubSpot. Drift = pain.

### See also

- [`../../booking/build-form.md`](forms-booking.md#build-form) — the SpiderForms primitive being created in Step 3
- [`../../booking/form-as-page-section.md`](forms-booking.md#form-as-page-section) — embed the mirrored form in a SpiderPublish page
- [`../../booking/test-form-submission.md`](forms-booking.md#test-form-submission) — verify the webhook fires + lands in HubSpot
- [`../../booking/clone-form-template.md`](forms-booking.md#clone-form-template) — if a SpiderForms template covers 80% of the HubSpot form shape, start there


---

## Pricing Table

Build a `pricing_table` block from Stripe's `/v1/prices` catalog — one source of truth for price + currency, no manual page editing when the price changes.

### When to use

- The tenant prices change quarterly (SaaS subscriptions) — sync from Stripe so the page never lies.
- Multi-currency pricing (`unit_amount` per currency from Stripe) — pull the right currency for the right region.
- "Most popular" / "annual discount" badges driven by Stripe metadata.
- Pattern: "Stripe is the price book; SpiderPublish is the public catalog."

### Prerequisites

- Stripe secret key (`sk_live_...` or `sk_test_...`) with `prices:read` scope.
- A SpiderPublish PAT scoped to the tenant.
- A target page (`page_id`) where the pricing table will live.
- Decided UX: vertical (3 columns) vs horizontal (rows) — affects which `pricing_table` variant to use.

### Step 1 — Pull from Stripe

```python
import stripe
stripe.api_key = "sk_live_..."

# List active prices, expanding product for name + description
prices = stripe.Price.list(
    active=True,
    expand=["data.product"],
    limit=100
).data

# Filter to display-eligible (e.g. exclude one-off addon prices)
display_prices = [
    p for p in prices
    if p.metadata.get("display_in_table") == "true"
]
```

Pre-tag display-eligible prices with a `display_in_table=true` metadata field in the Stripe dashboard. Avoids leaking internal-only prices to the public table.

### Step 2 — Group by product (one card per product)

```python
from collections import defaultdict

cards = defaultdict(lambda: {"name": "", "description": "", "prices": []})

for price in display_prices:
    product = price.product
    cards[product.id]["name"]        = product.name
    cards[product.id]["description"] = product.description or ""
    cards[product.id]["prices"].append({
        "id":        price.id,
        "amount":    price.unit_amount / 100,                # cents → dollars
        "currency":  price.currency,
        "interval":  price.recurring.interval if price.recurring else "one_time",
        "highlight": price.metadata.get("highlight") == "true",
        "cta_text":  price.metadata.get("cta_text", "Subscribe")
    })
```

### Step 3 — Build the `pricing_table` block

```python
pricing_table_block = {
    "type": "component",
    "component_slug": "sys-pricing-table",         # or your custom slug
    "props": {
        "variant": "vertical",                       # vertical | horizontal | compact
        "show_currency_symbol": True,
        "default_interval": "month",                 # tabs between month/year if both exist
        "cards": [
            {
                "name":        c["name"],
                "description": c["description"],
                "prices":      c["prices"],
                "featured":    any(p["highlight"] for p in c["prices"])
            }
            for c in cards.values()
        ]
    }
}
```

### Step 4 — Insert or update the page

If this is a NEW pricing page:

```
content_create_page({
  title: "Pricing",
  slug:  "pricing",
  template: "default",
  blocks: [
    { type: "component", component_slug: "sys-hero-headline", props: {...} },
    pricing_table_block,
    { type: "component", component_slug: "sys-faq-accordion", props: {...} }
  ]
})
```

If the page already exists, find the existing pricing block by ID + replace it:

```python
page = content_get_page({"page_id": "<page-uuid>"})
blocks = page["blocks"]
# Find the existing pricing_table block
idx = next(i for i, b in enumerate(blocks) if b["component_slug"] == "sys-pricing-table")
blocks[idx] = pricing_table_block

content_update_page({
  "page_id": "<page-uuid>",
  "blocks":  blocks
})
```

### Step 5 — Wire CTAs to Stripe Checkout

Each price's `cta_text` button needs to land on a Stripe Checkout session. Either:

- **Static Checkout link** (low-traffic plans): pre-generate via Stripe dashboard, paste into `props.cards[*].prices[*].checkout_url`.
- **Dynamic Checkout** (most cases): set `checkout_url` to a SpiderForms submit endpoint that creates a Stripe Checkout session server-side and returns the redirect URL.

```python
# Option B: rewrite checkout_url to a SpiderForms submit
for card in pricing_table_block["props"]["cards"]:
    for price in card["prices"]:
        price["checkout_url"] = f"https://<tenant>/api/checkout?price_id={price['id']}"
```

### Step 6 — Deploy

Follow [`../../reference/deploy-protocol.md`](deploy-protocol.md):

```
content_publish_page({ page_id })           # safe-default gated
content_deploy_site_preview()
content_deploy_site_production({ confirm_token })
```

### Steps — full flow (CI-friendly)

```python
# Run as a CI job triggered on Stripe webhook (price.created / .updated / .deleted)
1. prices = stripe.Price.list(active=True, expand=["data.product"])
2. cards  = group_by_product(filter_display_eligible(prices))
3. block  = build_pricing_table_block(cards)
4. page   = content_get_page({"page_id": "..."})
5. blocks = replace_pricing_block(page["blocks"], block)
6. content_update_page({"page_id": "...", "blocks": blocks})
7. content_publish_page({"page_id": "..."})         # via preview+confirm
8. content_deploy_site_production({confirm_token})  # via preview+confirm
```

For low-traffic pages, run this nightly instead of webhook-triggered.

### Gotchas

- **Stripe `unit_amount` is in CENTS** (or smallest currency unit). Always divide by 100 (or by the currency's decimal_digits) before passing to the table.
- **Multi-currency requires care.** A `prices.list` call returns ALL currencies. If you want only USD, filter `if price.currency == "usd"`. If you want region-aware display, the page needs client-side currency detection (out of scope here).
- **`product.description` may be Markdown.** SpiderPublish components render as HTML — escape if you can't trust the source, or use a `rich_text` rendering hint in the props_schema.
- **Stripe rate-limits at 100 req/sec.** Reasonable for catalog reads; if you're pulling 500+ prices on every page load, cache.
- **Don't store the Stripe key in the page or component.** The pulled prices land in `props` (visible client-side); the SECRET key must stay server-side only.
- **Webhook-triggered sync can race.** Two webhooks firing within milliseconds can both trigger updates; use idempotency keys + serial-pull state.
- **One-time prices vs recurring** — the snippet above handles both via `price.recurring`. Verify your `pricing_table` component supports the "one-time" variant or filter to `recurring` only.

### Verify

```
content_get_page({ page_id })
# → confirm blocks[<idx>] has the new pricing_table with current prices

content_visual_check({
  page_url: "https://<tenant>/pricing",
  viewport: "desktop"
})
# → body_text_preview should contain the current prices ("$29", "$99", etc.)
```

Manually verify each Checkout CTA:

```bash
curl -sI "https://<tenant>/pricing" | grep "200"
# Then click each CTA in a real browser to confirm Stripe Checkout opens with the right price.
```

### Anti-patterns

- **Hardcoding prices in the page blocks.** Defeats the purpose of Stripe-as-source-of-truth. Re-syncs become "edit Stripe AND edit the page in two places."
- **Listing ALL Stripe prices in the table** without `display_in_table=true` filtering. Internal/test prices leak.
- **Forgetting the CTA URL rewrite to Checkout.** The table looks right but every button 404s.
- **Pulling without filtering by `active=true`.** Inactive prices leak into the table.
- **Storing the Stripe secret in `props`.** It ships to the browser. Use a webhook-triggered server-side sync; never expose the secret.
- **Re-running the sync on every page request.** Stripe rate limits; cache the result (CDN / Redis / static page rebuild on webhook).

### See also

- [`../../content/landing-page.md`](content.md#landing-page) — for the page that hosts the pricing table
- [`../../marketplace/browse-cro-components.md`](marketplace.md#browse-cro-components) — for FAQ / urgency components that pair well with pricing
- [`../../reference/block-types.md`](block-types.md) — the `component` block schema (pricing_table is a component slug)
- [`../../reference/deploy-protocol.md`](deploy-protocol.md) — the publish + deploy gate flow


---

## IDAP Fill From Form

Make a Form *populate the tenant's CRM* on submit. Wire each form field to a typed CRM column via `crm_target`, and use the 8 IDAP-anchored field types (url / country / region / postal_code / address / datetime / currency / place) so the value the form ships is structurally compatible with the column the CRM expects.

The form-fills-the-CRM premise: every IDAP column type needs a matching form field type that emits a typed, structured value. Without this map, an author can wire `crm_target` but the form ships a string blob into a column the CRM expects to hold a `place_id`, a country code, or a structured address — defeating the whole point of dual-write.

### When to use

- A tenant wants form submissions to land *in the CRM* (not just in the raw submissions audit), so SpiderMail / VayaPin / SpiderVerify can re-engage from the same row.
- The form collects structured data (address, country, currency, scheduled datetime, business place) — not just free text.
- You're migrating off Typeform and want one of: typed lead profile updates, lead-scoring fields, structured intake.
- A form question has a clean CRM home: `business website` → `norm_cli_*.businesses.website`, `country of incorporation` → `norm_cli_*.company_registry.country_code`, etc.

### The two pieces

| Piece | What it does | Where it lives |
|---|---|---|
| **`crm_target`** on a field | Wires that field's answer to `norm_cli_<tenant>.<resource_type>.<column>` on submit | `field.crm_target = { resource_type, column }` |
| **IDAP-anchored field types** | Make the field emit a *typed* value (ISO country code, structured address, currency `{amount, currency}`) so the column accepts it | `field.type = "url" \| "country" \| "region" \| "postal_code" \| "address" \| "datetime" \| "currency" \| "place"` |

Both are validated at publish time. If `field.type` is `text` and `column` is `country_code varchar(2)`, the form publish call returns `422 error_code="crm_target_invalid"` — the wrong field type would let `"United States"` reach a column that expects `"US"`.

### The 8 IDAP-anchored field types

Each is registered in the form renderer (input UX), validated at parse time (correct ISO shape, country-aware postal regex, etc.), and gated at publish-time against the column's `data_type`.

#### `url`

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

#### `country`

ISO 3166-1 alpha-2 (`"DE"`, `"US"`, `"AR"`). Per-type config:

| Config | What it does |
|---|---|
| (none required) | Picker rendered as a searchable dropdown of 250 ISO countries. |

```
{ id: "billing_country", type: "country", label: "Country",
  crm_target: { resource_type: "businesses", column: "country_code" } }
```

CRM column shapes: text-family. Especially `country_code varchar(2)` columns on `businesses`, `phones`, `linkedin_profiles`, `company_registry`.

#### `region`

Text region / state / province. Optional ISO 3166-2 subdivision (`"US-CA"`, `"DE-BY"`) for tenants with a strict region-code requirement.

```
{ id: "state", type: "region", label: "State / region",
  crm_target: { resource_type: "businesses", column: "region" } }
```

CRM column shapes: text-family.

#### `postal_code`

Normalised text with country-aware shape validation (US `\d{5}(-\d{4})?`, DE `\d{5}`, UK alphanumeric, …). The shape is picked from the form's `country` field answer or from the per-field default if there is no country answer.

```
{ id: "zip", type: "postal_code", label: "Postal code",
  crm_target: { resource_type: "businesses", column: "postal_code" } }
```

CRM column shapes: text-family.

#### `address`

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

#### `datetime`

ISO 8601 timestamp with timezone (`"2026-06-12T14:30:00Z"`). For day-only collection, the field flips to a date-only widget that lands as a `date` value.

```
{ id: "event_date", type: "datetime", label: "When is your event?",
  crm_target: { resource_type: "bookings", column: "slot_start" } }
```

CRM column shapes: `timestamp with time zone`, `date`.

#### `currency`

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

#### `place`

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

##### Server-proxy behavior

The `place` field requires server-side Google Places lookup — the public API key is never shipped to the browser. The form renderer proxies `/api/v1/booking/{flow_id}/places/autocomplete` to the backend, which calls Google Places with the per-tenant `GOOGLE_PLACES_API_KEY`.

**Provisioning:**

- If `GOOGLE_PLACES_API_KEY` is set on the deployment, the field renders as a Google-Places-backed autocomplete.
- If it is **not** set, the field gracefully degrades to a free-text input, the `crm_target` writes the raw text, and the renderer surfaces a one-line `info` hint ("autocomplete unavailable — using free text") so authors know the lookup is offline.

If you need the autocomplete and don't see it on a deployment, talk to the platform admin about provisioning the key. Don't switch the field type to `text` — the IDAP type carries semantics the CRM column relies on (`place_id` is a natural key on `norm_cli_*.businesses`).

### CRM column shapes — quick map

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

#### Full compatibility matrix

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

### End-to-end recipe — agency-intake form that fills the CRM

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

### What happens on submit

```
POST /api/v1/booking/{flow_id}/submit
{ "answers": { ... }, "consent": { "agreed_to_booking": true } }
```

1. The submit handler validates each answer against its field's structural shape (ISO country code? Valid URL?).
2. For each field with a `crm_target`, the handler maps the typed value into the right shape for the column type (`text-family` → string; `jsonb` → full struct; `numeric` → amount-only).
3. Within the submit transaction, the raw submission row lands in `public.results` (`worker_type='form'`, full answers JSONB).
4. The CRM sync cron picks up the row within 60s and UPSERTs each `crm_target` mapping into `norm_cli_<tenant>.<resource_type>` using the natural key of that table (e.g. `contacts.email`, `businesses.google_place_id`).

Downstream workers (SpiderMail outreach, SpiderVerify, VayaPin) see the updated row on their next pass — same as any other CRM mutation.

### Anti-patterns

- **Don't use `text` for a structured column.** A free-text "Country" answer landing in `country_code varchar(2)` will publish-fail at the `FIELD_TYPE_COLUMN_COMPAT` gate. Use `country`.
- **Don't wire `crm_target` to a column that doesn't exist** on the tenant's `norm_cli_*` schema. The publish-time validator returns `422 error_code="crm_target_invalid"` listing the missing column.
- **Don't store a `place` payload's `formatted_address` into `businesses.address`** — wire the typed payload (or its `place_id`) and let the CRM sync cron unpack it. `place` carries `lat/lng/address_components` the CRM uses to enrich downstream.
- **Don't assume `place` autocomplete is on every deployment.** When `GOOGLE_PLACES_API_KEY` is not provisioned the field falls back to free text — design the form so the downstream CRM column accepts both shapes (or accept that on those deployments the column gets the user's typed string).
- **Don't use `currency_mode: "amount_only"` against a `jsonb` column.** The dual-write writes a bare number; the CRM ends up with a JSON number instead of `{amount, currency}`. Pair `amount_only` with `numeric`, `with_picker` with `jsonb`.

### See also

- [recipes/build-lead-gen-form](../SKILL.md) — end-to-end form pipeline (this recipe drops in the `crm_target` and IDAP fields)
- [recipes/design-a-form](../SKILL.md) — themes / token overrides / per-question media
- [core-skills/forms/SKILL.md](../SKILL.md) — full `form_*` tool catalog (20 tools)
- examples/idap-fill-from-form.sh — runnable bash version of the agency-intake recipe


---

## URL To Template

Clone a public URL into a SpiderPublish Liquid template + extracted components. SpiderClone scrapes the source URL, tokenizes the markup into per-section components, uploads images to SpiderMedia, and emits a draft theme + draft pages ready to publish.

### When to use

- A prospect points at a competitor's site ("can you replicate this look?") and you want a working SpiderPublish tenant that matches in <30 minutes.
- A client is migrating from a hosted page-builder (Tilda, Webflow, Lovable, Wix, Squarespace) and you have URLs but not source HTML.
- You're building demos / spec'ing new theme designs by cloning reference sites as a starting point.

If you have **source HTML files** (Tilda export, hand-coded) → use [`tilda-migration.md`](content.md#import-tilda-site) instead. SpiderClone is the URL-only path.

### Honest framing

SpiderClone is a **best-effort scraper + emitter**, not a perfect-replica tool. Expect:

- 70-90% visual fidelity on first run for simple marketing sites.
- 30-50% on JavaScript-heavy sites (React SPAs, animation-heavy hero sections, scroll-jacked landing pages).
- Manual cleanup after every run — extracted sections become draft components you can iterate on.

It's a **starting-point generator**, not a one-shot finished site.

### Tool surface — current state

The first-party SpiderClone MCP tool surface is **still emerging**. As of 2026-05-24, the production-ready paths are:

1. **REST endpoint**: **NOT YET EXPOSED** as of 2026-05-24. No `/clone/from-url` route exists in `app/api/v1/`. SpiderClone is being staged as a separate worker; the public REST surface lands later. Tracked as product gap.
2. **CLI command**: **NOT YET EXPOSED** in `@spideriq/cli` as of 2026-05-24. Same product gap.
3. **MCP tool**: **NOT YET EXPOSED** in `@spideriq/mcp` kitchen-sink as of 2026-05-24 — no `clone_from_url` / `content_clone_*` registration in `packages/mcp-tools/src/publish/`. Same product gap.

This recipe shows the REST path. When the MCP tool lands, the structure here transfers directly — same params, same flow.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Source URL reachable** from the SpiderPublish scraper (i.e. not behind auth, not geo-blocked from CF's edge).
3. **SpiderMedia R2 quota** — the cloner uploads every extracted image. Large sites can hit tenant quota; check `get_media_stats()` first.
4. **`spideriq.json` bound to the destination tenant.** Cloned drafts land in this tenant, not the source.

### The 4-step path

```
1. POST /clone/from-url     — kick off the scrape + emit
2. (poll for completion)     — clone is async; usually 30-120s
3. (review draft components + pages)  — content_list_components + content_list_pages
4. content_publish_component / content_publish_page + content_deploy_site
```

#### 1. Kick off the clone

```bash
curl -X POST "https://spideriq.ai/api/v1/dashboard/projects/$PID/clone/from-url" \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "source_url": "https://example-competitor.com/",
    "include_paths": ["/", "/features", "/pricing", "/about"],
    "extract_strategy": "section",
    "upload_images_to_r2": true
  }'
# → { job_id: "clone_...", status: "queued", estimated_seconds: 60 }
```

**Params:**

| Field | Notes |
|---|---|
| `source_url` | The starting URL. Required. |
| `include_paths` | Array of paths to crawl from the source domain (default: just `/`). Use to constrain to a few key pages instead of the whole site. |
| `extract_strategy` | `"section"` = one component per visible section (recommended). `"whole_page"` = one component per page (less granular, harder to iterate). |
| `upload_images_to_r2` | When `true`, every `<img src="...">` is fetched and uploaded to your SpiderMedia bucket. Source URLs rewritten to `https://media.cdn.spideriq.ai/...`. Skip with `false` only if you're testing — link-rot from the source CDN breaks the site months later. |

**Resolved 2026-05-24 — product gap, full surface not yet shipped:** the SpiderClone family is roadmapped but no REST/CLI/MCP surface is registered in `master` yet. This recipe stays in the catalog as forward-compatibility documentation — once the surface lands, the structure here transfers directly (4-step path: scope verify → submit URL → poll → review draft). Until then, the practical paths are [`import-tailwind.md`](integrations.md#import-tailwind) (if you have Tailwind source) or [`../content/import-tilda-site.md`](content.md#import-tilda-site) (if you have HTML).

#### 2. Poll for completion

```bash
curl "https://spideriq.ai/api/v1/dashboard/projects/$PID/clone/jobs/clone_..." \
  -H "Authorization: Bearer $CLIENT_ID:$API_KEY:$API_SECRET"
# → {
#     job_id: "clone_...",
#     status: "running" | "succeeded" | "failed",
#     progress: { pages_scraped: 4, components_extracted: 17, images_uploaded: 23 },
#     emitted: {
#       theme_name: "cloned-from-example",
#       components: [ { slug: "home-hero", category: "hero", status: "draft" }, ... ],
#       pages:      [ { slug: "home", template: "default", status: "draft" }, ... ]
#     },
#     errors: []   # populated if scrape partially failed
#   }
```

Typical timing: 30-120s for a 5-page site, longer for image-heavy ones. The cloner emits incrementally — `components` and `pages` populate as work progresses.

`emitted.theme_name` is the new theme. You don't need to `template_apply_theme` it explicitly — the cloned pages already reference its templates. But you CAN apply it as the tenant's default if you want non-cloned pages to also use it.

#### 3. Review what landed

```
# List the extracted components
content_list_components({ status: "draft", limit: 50 })
// → [
//   { slug: "home-hero",       category: "hero",     status: "draft", ... },
//   { slug: "home-features",   category: "features", status: "draft", ... },
//   { slug: "pricing-table",   category: "pricing",  status: "draft", ... },
//   ...
// ]

# Inspect one
content_get_component_by_slug({ slug: "home-hero" })
// → { html_template, css, props_schema, default_props, ... }
```

Read each component. Things to expect:

| Often correct | Often needs editing |
|---|---|
| HTML structure | Animations (CSS @keyframes, JS-driven) |
| CSS layout (flexbox, grid) | Interactive JS (carousels, modals — emitted as static) |
| Image URLs (now pointing at SpiderMedia) | Font references (clone may miss `@font-face` declarations) |
| Static text | Dynamic text (CMS-fed content from the source site) |
| Color palette | Hover-states (rarely captured) |

For non-trivial cleanup, edit the component in the Content Studio dashboard (better diffing) or use `content_update_component` for targeted patches.

```
content_list_pages({ status: "draft", limit: 50 })
// → [
//   { slug: "home",     status: "draft", blocks: [ {type: "component", component_slug: "home-hero", ...}, ... ] },
//   { slug: "features", status: "draft", blocks: [...] },
//   ...
// ]
```

Each page's `blocks` reference the extracted components by `component_slug`. You can `content_update_page` to rearrange, swap components, or drop sections.

#### 4. Publish + deploy

```
# For each component
content_publish_component({ component_id: "comp_..." })
content_publish_component({ component_id: "comp_...", confirm_token: "cft_..." })

# For each page
content_publish_page({ page_id: "<page-uuid>" })
content_publish_page({ page_id: "<page-uuid>", confirm_token: "cft_..." })

# Then deploy
content_deploy_readiness()
content_deploy_site_preview()   # eyeball the preview URL
content_deploy_site_production({ confirm_token: "cft_..." })
```

Site is live in 2-5s on the tenant's primary domain.

### Verify

```
content_visual_check({
  page_url: "https://<tenant>/",
  viewport: "desktop"
})
```

Compare the screenshot side-by-side with the source URL. Typical differences after a clone+publish:

- Fonts: source uses Inter, clone falls back to system-ui. Fix: update `content_settings.css_variables` with the right `@font-face` declarations + font URLs.
- Animations: source has fade-in scroll triggers, clone is static. Fix: upgrade the component to Tier 3 (add GSAP dependency).
- Hover/focus states: source has them, clone may miss. Fix: add `:hover` / `:focus` rules to the component's `css` field.
- Form embeds: source has a HubSpot/Typeform iframe, clone embeds a static placeholder. Fix: create a SpiderPublish form (`form_create_from_template` or `build-form.md`) and swap the placeholder block.

### Iterate

The healthy loop after a clone:

```
1. clone (one-shot, 30-120s)
2. review → identify the 3-5 worst sections
3. content_update_component on each
4. content_deploy_site_production
5. visual_check, compare to source
6. repeat 3-5 until "good enough"
```

Don't try to make the clone 100% pixel-perfect — at some point it's faster to author from scratch using the clone as a structural reference.

### Anti-patterns

1. **Treating the cloned output as final.** It's a starting point. Plan for 30-60 min of manual cleanup per page.
2. **Skipping `upload_images_to_r2: true`.** Source CDNs rate-limit + go down + change URLs. Your tenant breaks 6 months later if you skip this.
3. **Cloning auth-walled or geo-blocked URLs.** Scraper can't reach them. Will return `errors: [{url, status: 403}]`. Either provide the HTML (use [`tilda-migration.md`](content.md#import-tilda-site)) or pick a different URL.
4. **Cloning React/Vue SPAs.** The scraper renders with a headless browser, but heavy client-side state often produces blank-canvas captures. Test with a small `include_paths` first; if quality is bad, the source is SPA-shaped → reach for [`tilda-migration.md`](content.md#import-tilda-site) or hand-author.
5. **Cloning into a production tenant directly.** Always test in a fresh tenant first. The clone creates dozens of draft components + pages — easy to pollute a production tenant. Use a `cloning-sandbox` tenant, iterate there, then copy the "good" components into production via `content_create_component` once you're happy.
6. **Publishing every cloned component without review.** Bad sections get published too. Triage first: which sections are usable as-is, which need iteration, which to drop entirely.

### See also

- [`../content/import-tilda-site.md`](content.md#import-tilda-site) — HTML-source path (Tilda exports, Webflow, hand-coded) — preferred over URL-clone when you have source files
- [`../components/create-component.md`](components.md#create-component) — author a component from scratch (clone's last resort)
- [`../content/landing-page.md`](content.md#landing-page) — block-based authoring (when the clone needs a from-scratch rebuild)
- [`../content/apply-theme.md`](templates-deploy.md#apply-theme) — apply the cloned theme as the tenant default
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the two-phase publish + deploy
- [`../reference/tool-surface.md`](tool-surface.md) — `content_*` component + page tools
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Import Tailwind

Take a Tailwind-built page (a `tailwind.config.js` + HTML markup with `class="…"` strings) and turn it into a SpiderPublish theme — design-tokens applied via `template_apply_theme` + draft pages with extracted components. The semi-manual sibling of [`url-to-template.md`](integrations.md#url-to-template) (URL scrape) and [`../content/import-tilda-site.md`](content.md#import-tilda-site) (inline-style port).

### When to use

- A client built their MVP in Tailwind + plain HTML (or copy-pasted a Tailwind UI Kit snippet) and you want to migrate without rebuilding.
- You have a Figma → Tailwind code-gen export and want to land it as a SpiderPublish theme + pages.
- An agency hands over a Tailwind starter and you want first-pass tenant assets in a day.
- Pattern: "here's a tailwind.config.js + some `*.html` — make a SpiderPublish tenant out of it."

### Honest framing

There is **no first-party `tailwind_to_template` MCP tool** as of 2026-05-24. This is a structured manual flow that uses three existing primitives:

1. **`template_apply_theme`** — apply your extracted CSS-token map to the tenant theme.
2. **`content_create_component`** — register each unique Tailwind-class block (hero, card, CTA) as a component.
3. **`content_create_page`** — assemble pages from those components.

You do the **Tailwind → tokens** extraction client-side (a small Node script reading `tailwind.config.js`); the tools land the result.

### Prerequisites

1. **Tenant scope verified.** `./scripts/verify-tenant-scope.sh` exit 0.
2. **Source files on disk:** `tailwind.config.js` + a folder of `*.html` files (one per page).
3. **Node** to run the extraction script.
4. **`@spideriq/cli` installed** (for the registration steps).
5. **PAT** scoped to the destination tenant.

### Step 1 — Extract tokens from `tailwind.config.js`

Tailwind's `theme.extend` block IS your design-token source. A small Node script reads it and emits a SpiderPublish-friendly token map:

```javascript
// scripts/tailwind-to-tokens.mjs
import { default as tailwindConfig } from "../tailwind.config.js";

const colors = tailwindConfig.theme?.extend?.colors ?? {};
const fonts  = tailwindConfig.theme?.extend?.fontFamily ?? {};
const radius = tailwindConfig.theme?.extend?.borderRadius ?? {};

const tokens = {};
for (const [name, value] of Object.entries(colors)) {
  if (typeof value === "string") {
    tokens[`--color-${name}`] = value;
  } else if (typeof value === "object") {
    for (const [shade, hex] of Object.entries(value)) {
      tokens[`--color-${name}-${shade}`] = hex;
    }
  }
}
for (const [name, stack] of Object.entries(fonts)) {
  tokens[`--font-${name}`] = Array.isArray(stack) ? stack.join(", ") : stack;
}
for (const [name, value] of Object.entries(radius)) {
  tokens[`--radius-${name}`] = value;
}

console.log(JSON.stringify(tokens, null, 2));
```

Run it:

```bash
node scripts/tailwind-to-tokens.mjs > tokens.json
```

Produces:

```json
{
  "--color-primary-500": "#3b82f6",
  "--color-primary-600": "#2563eb",
  "--color-gray-50": "#f9fafb",
  "--font-sans": "Inter, ui-sans-serif, system-ui",
  "--radius-lg": "0.5rem",
  ...
}
```

### Step 2 — Apply the theme

Use `template_apply_theme` to land the token map into the tenant's `content_settings`:

```
# Dry-run first (template_apply_theme is safe-default gated)
template_apply_theme({
  theme_slug: "tailwind-imported",
  tokens:     {<the tokens.json contents>}
})
# → { dry_run: true, preview: {...}, confirm_token: "cft_..." }

# Confirm
template_apply_theme({
  theme_slug:    "tailwind-imported",
  tokens:        {<same>},
  confirm_token: "cft_..."
})
```

This becomes the active theme; every page references the same `--color-primary-500` etc.

### Step 3 — Identify unique sections in your HTML

A Tailwind HTML file is usually a sequence of `<section class="...">` blocks. Each section becomes a SpiderPublish component:

```html
<!-- pages/landing.html -->
<section class="bg-gradient-to-br from-primary-500 to-violet-600 py-24">
  <div class="max-w-4xl mx-auto text-center text-white">
    <h1 class="text-5xl font-bold">{{headline}}</h1>
    <p class="mt-4 text-xl opacity-90">{{subhead}}</p>
    <a class="mt-8 inline-block bg-white text-primary-600 rounded-lg px-8 py-4">{{cta_label}}</a>
  </div>
</section>

<section class="bg-gray-50 py-16">
  <!-- features grid -->
</section>
```

Group by visual identity:
- `tw-hero-gradient` — the section above
- `tw-features-grid` — the next section
- `tw-cta-band` — third section
- etc.

Each unique pattern = one component. Identical-looking sections across pages reuse the same component.

### Step 4 — Register each as a component

For each unique section, extract:
- `html_template` — the section HTML (with `{{...}}` Liquid placeholders for the dynamic bits)
- `css` — empty (Tailwind classes carry the styling)
- `props_schema` — JSON Schema for the placeholders (headline, subhead, cta_label, etc.)
- `default_props` — sensible defaults so the section renders standalone

```
content_create_component({
  slug: "tw-hero-gradient",
  category: "hero",
  html_template: "<section class=\"bg-gradient-to-br ...\">...</section>",
  css: "",
  props_schema: {
    type: "object",
    properties: {
      headline:  { type: "string" },
      subhead:   { type: "string" },
      cta_label: { type: "string" },
      cta_href:  { type: "string", format: "uri" }
    },
    required: ["headline", "cta_label", "cta_href"]
  },
  default_props: {
    headline:  "Your headline here",
    subhead:   "Your subhead here",
    cta_label: "Get started",
    cta_href:  "/signup"
  },
  agent_meta: {
    when_to_use: "Top of marketing pages where you want a gradient hero with a single CTA",
    when_not_to_use: "Anywhere needing a video or image background"
  }
})
```

### Step 5 — Assemble pages from registered components

```
content_create_page({
  slug: "landing",
  title: "Landing Page",
  template: "default",
  blocks: [
    {
      type: "component",
      component_slug: "tw-hero-gradient",
      props: { headline: "Real headline here", cta_label: "Sign up", cta_href: "/signup" }
    },
    { type: "component", component_slug: "tw-features-grid", props: {...} },
    { type: "component", component_slug: "tw-cta-band",      props: {...} }
  ]
})
```

### Step 6 — Tailwind CSS itself

The Tailwind utility classes need to be ON THE PAGE for the components to render right. Two options:

| Option | When | How |
|---|---|---|
| **CDN Tailwind** | Quick start, prototyping | Add `<script src="https://cdn.tailwindcss.com"></script>` to the template `<head>` via `template_upsert` |
| **Compiled Tailwind CSS** | Production | Run `tailwindcss -i src/input.css -o dist/output.css` → upload to SpiderMedia → `<link rel="stylesheet" href="<r2_url>">` in the template `<head>` |

CDN is fine for the first deploy; ship compiled CSS before going live so you don't fetch ~3 MB of Tailwind runtime on every page load.

### Step 7 — Deploy

Follow [`../reference/deploy-protocol.md`](deploy-protocol.md):

```
content_deploy_readiness()
content_deploy_site_preview()
content_deploy_site_production({ confirm_token })
```

### Steps — full flow

```
1. (write + run scripts/tailwind-to-tokens.mjs)   — extract tokens
2. template_apply_theme({ tokens, ... })          — land the tokens
3. (audit HTML for unique sections)
4. content_create_component(...) × N              — register each unique section
5. content_create_page(...) × M                   — assemble pages
6. (upload Tailwind CSS to SpiderMedia OR add CDN script to template)
7. content_deploy_site_preview() → ...production() — push live
```

### Gotchas

- **Tailwind utility names ≠ SpiderPublish token names.** `bg-primary-500` (TW) → `var(--color-primary-500)` (SP). The token map handles values; the markup still references TW class names. Don't try to rewrite TW classes to CSS-var names — keep the markup as-is and ship Tailwind CSS.
- **Hand-rewriting Tailwind classes to CSS-vars breaks utility tooling.** If the next person opens the markup expecting Tailwind, they'll find half-rewritten CSS. Leave the classes; ship Tailwind CSS.
- **Tailwind `@apply` directives don't work** if you're shipping only the runtime CDN — they need build-time Tailwind. Compiled-CSS path required for `@apply` usage.
- **`tailwind.config.js` `content` paths** are meaningless in SpiderPublish (no build step). The extraction script ignores them. Tokens only.
- **Components with the same TW classes can still differ semantically.** Two hero sections with identical class strings might mean different things (one is a feature row, one is a hero); name them by INTENT not by classes.
- **Custom plugins (`@tailwindcss/typography`, custom utilities) won't extract cleanly.** Manual port for those: read the plugin source, add the resulting classes to the compiled CSS bundle.

### Verify

```
# After theme apply
template_get_config()
# → confirm the tokens you applied are in settings.theme_tokens

# After page deploy
content_visual_check({
  page_url: "https://<tenant>/<page-slug>",
  viewport: "desktop"
})
# → confirm Tailwind classes are rendering (look for the gradient hero in body_text_preview-adjacent fields)
```

### Anti-patterns

- **Trying to use SpiderClone for a Tailwind site you have source for.** SpiderClone scrapes the rendered output; you'd lose the original utility classes. If you have source, use this recipe.
- **Hand-translating every Tailwind class to inline CSS.** Defeats the purpose. Ship Tailwind CSS as a stylesheet; let the classes work.
- **Registering one component per section without grouping.** 40 sections might collapse to 8 unique patterns. Group by visual identity first.
- **Forgetting to ship the Tailwind CSS itself.** Page renders unstyled; classes are no-ops without the stylesheet.
- **Skipping `template_apply_theme` and relying on Tailwind's color palette.** SpiderPublish components elsewhere (forms, dashboards) read tokens from `--color-*`. Without applying them, those surfaces stay default-themed.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "import a tailwind site into SpiderPublish"
# Top-1 should be: recipes/clone/import-tailwind.md
```

### See also

- [`url-to-template.md`](integrations.md#url-to-template) — when you have a URL but no source code
- [`../content/import-tilda-site.md`](content.md#import-tilda-site) — for inline-`<style>` legacy HTML (Tilda, Webflow exports)
- [`../content/apply-theme.md`](templates-deploy.md#apply-theme) — applying a pre-built theme (not from Tailwind)
- [`../components/create-component.md`](components.md#create-component) — the component-registration primitive used in Step 4
- [`../reference/deploy-protocol.md`](deploy-protocol.md) — the gated `template_apply_theme` flow


---

## Import Listings

Build a programmatic-SEO directory — categories + per-city pages + individual listings — with SEO title/description templates that auto-interpolate `{category}`, `{city}`, and `{listing}`.

Two concepts, three URLs:

- **Category** (e.g. `plumbers`) — a vertical with SEO templates
- **Listing** — an individual business inside a category, tagged with `{city, state, country, ...}`
- URLs: `/{directory_base}/{category}` → cities list · `/{directory_base}/{category}/{city}` → listings · `/{directory_base}/{category}/{city}/{listing}` → detail

🔴 **`{directory_base}` is a per-tenant setting, not the literal string `directory`.** It defaults to `"directory"` and a tenant can rename it (`template_update_config(directory_base="ls")` → `/ls/plumbers/…`). Renaming is SEO-safe — the old paths keep serving as permanent **301** redirects and `sitemap.xml` switches to the new prefix — but **never hard-code `/directory/` into generated links or docs**. Full rules: [`directory-pages.md`](directory-pages.md).

### The one-shot path (v2.89.0+)

#### MCP — recommended

```
directory_create_category(
  name = "Plumbers",
  seo_title_template = "Best {category} in {city} | Your Brand",
  seo_description_template = "Compare top-rated {category} in {city}. Ratings, reviews, hours, directions."
)

directory_bulk_upsert_listings(
  category_slug = "plumbers",
  listings = [
    {
      name: "Aqua Fix",
      city: "Miami Beach",
      state: "Florida",
      phone: "+1-305-555-1234",
      website: "https://aquafix.example.com",
      rating: 4.7,
      review_count: 182,
      data: { hours: [{day: "Mon-Fri", open: "08:00", close: "18:00"}] }
    },
    // ... up to 5000 listings per call
  ]
)
```

Returns `{upserted: N, failed: 0, affected_cities: ["miami-beach-florida", ...]}`. No publish step (listings default to `status: "published"`). No deploy step — the public `/{directory_base}/*` routes render live. **A template change or a `directory_base` change does need a deploy.**

#### CLI

```bash
spideriq directory categories create \
  --name "Plumbers" \
  --seo-title "Best {category} in {city} | Your Brand" \
  --seo-description "Compare top-rated {category} in {city}. Ratings, reviews, hours."

# from a file (non-IDAP source):
spideriq directory listings import plumbers --file plumbers-miami.json

# from the tenant's own IDAP corpus — one command, no file:
spideriq directory listings import-from-idap plumbers \
  --category-filter "Plumber" --country-code US --rating-min 4.0 --limit 5000 --prune
```

`plumbers-miami.json` is a JSON array of listing objects.

`--prune` archives listings the import did not produce. It is **off by default**, and it refuses
rather than guess on an empty or limit-truncated result set — see *IDAP → directory* below.

### URL structure

| URL | What it renders |
|---|---|
| `/{directory_base}/{category_slug}` | Category landing — grid of every city that has published listings |
| `/{directory_base}/{category_slug}/{city_slug}` | Listings in that city, sorted by rating DESC then review_count DESC |
| `/{directory_base}/{category_slug}/{city_slug}/{listing_slug}` | Single listing with contact info + hours + optional breadcrumbs |

`{directory_base}` is `directory` unless the tenant changed it — see above. A published CMS page at slug `<directory_base>` renders in place of the built-in category hub.

**`city_slug` is auto-computed** as `LOWER(city + '-' + state)` with non-alphanumeric stripped. "Miami Beach" + "Florida" → `miami-beach-florida`. Don't manage city slugs by hand — the materialized view does it.

### SEO templates

The three placeholders are substituted server-side on every directory page:

- `{category}` — the category's display name (e.g. "Plumbers")
- `{city}` — the listing's city (e.g. "Miami Beach")
- `{listing}` — the listing's name (e.g. "Aqua Fix")

Example templates:

```
seo_title_template:       "Best {category} in {city} | Your Brand"
seo_description_template: "Compare top-rated {category} in {city}. Ratings, reviews, hours, directions."
```

Every category, every `(category, city)`, and every published listing auto-lands in `/sitemap.xml` with `<lastmod>` and `<changefreq>weekly</changefreq>`.

### Listing fields

Only `name` is required. Everything else shapes the page. (**Not** the merge-tag pipeline — merge tags do not reach directory pages; see *Merge tags inside listings* below.)

| Field | Required? | Notes |
|---|---|---|
| `name` | ✓ | Display name |
| `slug` | — | Auto-generated from name if omitted |
| `description` | — | Rendered on detail page |
| `city`, `state`, `country` | — | Drives `city_slug` computation + sitemap grouping |
| `address`, `latitude`, `longitude` | — | Detail page + future map support |
| `phone`, `email`, `website` | — | Contact card |
| `rating`, `review_count` | — | Sort order on city page + ★ badge |
| `data` | — | Free-form JSONB. `data.hours: [{day, open, close}]` renders automatically. Anything else is available to custom templates. |
| `source_job_id` | — | SpiderIQ job UUID for provenance. Set this when importing from SpiderMaps so you can audit which campaign produced each listing. |
| `status` | — | `published` (default), `draft`, `archived` |

### Ecosystem integration

#### IDAP → directory — ONE CALL, no transform

🔴 **Do not hand-transform an IDAP dump.** There is a dedicated importer that reads the tenant's
`norm_cli_*.businesses` **directly** — no scheduler, no sync pipeline, no export step, no external
call — and carries **every declared column** through (typed columns onto the listing, everything
else into its `data` JSONB):

```
directory_import_from_idap(
  category_slug  = "plumbers",
  category_filter = "Plumber",   # matches the businesses.categories[] array
  country_code    = "US",        # ISO-2, uppercase, exact
  city            = "Miami",     # ILIKE substring
  rating_min      = 4.0,         # inclusive
  limit           = 5000,        # hard cap 5000
  prune           = False        # see below
)
```

Returns `{upserted, inserted, updated, pruned, failed, source_rows, affected_cities, source_schema,
fields_mapped, filter, sync_log_id, failures?, prune_skipped_reason?, hint?}`. If the tenant has no
`norm_cli_*` schema yet (never ran SpiderMaps), `hint` explains the workaround instead of failing
silently.

**Use `directory_bulk_upsert_listings` only for a NON-IDAP source** — a hand-built list, a partner
feed, an Airtable view (see *Sync To Directory* at the top of this file). There, set
`source_job_id` so provenance is auditable.

🔴 **Both paths are an UPSERT keyed on `(category, slug)` and neither removes anything.** A business
deleted from IDAP, or renamed so it derives a different slug, stays **published forever**, and every
re-import drifts the category further from its source. `prune=true` archives (never deletes) what
the import did not produce — and it **refuses rather than guess**, naming which in
`prune_skipped_reason`: `source_returned_no_rows` (an empty result is far more often a filter that
matched nothing) or `source_truncated_at_limit` (absence is a pagination artefact). A refusal is an
**answer** — re-running unchanged refuses identically.

#### Merge tags inside listings — 🔴 THEY DO NOT WORK HERE

`{{ first_name }}`, `{{ company_name }}`, `{{ salesperson_email }}` and the rest are **`/lp/`
lead-scoped only**. They are built from a lead resolved by the `/lp/{page_slug}/{identifier}`
routes; on every other route — directory pages included — they resolve to the canonical **empty
shape** and render as empty strings, **silently, at HTTP 200**.

Storing `{{ salesperson_email }}` in a listing field and rendering it produces a blank, not a
substitution.

**Directory templates read `listing.*` (the typed columns) and `data.*` (whatever you put in the
listing's `data` JSONB) instead.** For per-prospect personalisation you want a different surface
entirely — [`dynamic-landing.md`](dynamic-landing.md).

### Common variants

#### Bulk import from a file (CLI)

```bash
spideriq directory listings import plumbers --file ./exports/miami-plumbers.json
```

#### Verify import

```
directory_list_listings(category_slug="plumbers", city="Miami Beach")
# → paginated result set, including your freshly imported rows
```

#### Rebuild the city_stats materialized view manually

```
directory_refresh_stats()
```

Rebuilds the **`city_stats` materialized view** — the per-(category, city) rollup that the category
hub and every city page read to know which cities exist and how many listings each holds.

🔴 **It does NOT recompute a category's `listing_count`.** Two similar names, two different numbers:
`listing_count` lives on the category row and is maintained by the **write** paths only (bulk
upsert, import, prune, delete-listing). Nothing recomputes it on demand and this tool will not. If a
`listing_count` looks wrong, re-run the write that produced it.

Every write path already refreshes `city_stats` itself, so you rarely need this. Reach for it when a
hub or city page shows a stale city list after a change made outside the normal write path.

### When to use

- You have an SEO strategy around "best {category} in {city}" long-tail queries
- You've run a SpiderMaps/IDAP campaign and want the results to surface as a directory
- You're migrating a Yellow Pages-style site and need per-category + per-city pages + individual business details
- You want to reuse the SpiderPublish render pipeline (Liquid templates, theme, merge tags) for a directory product

### When NOT to use

- You have fewer than 20 listings — just make normal pages
- Your "listings" are actually products (SKUs) — use blog posts or a separate product model
- You need complex faceted filtering (price range, distance radius, tag intersection) — directory is single-axis (category + city). For richer search, pair with a dedicated search index.

### Anti-patterns

- DO NOT create a category per city ("plumbers-miami", "plumbers-austin") — one category spans all cities. The platform derives cities from the listings' `city` field.
- DO NOT manage `city_slug` by hand — the materialized view computes it. Editing it directly will desync from the index.
- DO NOT bulk-import more than 5000 listings per call — paginate. Transactions time out and you'll need to retry.
- DO NOT bypass the bulk endpoint for IDAP dumps — individual `directory_upsert_listing` calls for a 3000-row dump burns 3000× the API budget.
- DO NOT add listings to a category that doesn't exist — you'll get 404. Create the category first, then import.

### See also

- [`directory-pages.md`](directory-pages.md) — the full directory reference: the copy-not-IDAP model, `directory_base`, staleness and `prune`, the three re-import doors, the overridable templates
- [`dynamic-collections.md`](dynamic-collections.md) — the FLAT layout over the same listings, and every other `collection_type`
- [`media.md`](media.md) — uploading listing images
- [SpiderIQ `/content/help` → `build_a_directory`](https://spideriq.ai/api/v1/content/help?format=yaml)
- [SpiderIQ `/content/playbook` → `build_a_directory`](https://spideriq.ai/api/v1/content/playbook?intent=build_a_directory&format=yaml)
