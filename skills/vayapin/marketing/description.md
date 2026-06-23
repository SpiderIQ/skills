## vayapin

Phone number lookup + validation via VayaPin (SpiderIQ's phone-data service). 4 tools.

### What this skill does

- **`lookup_phone`** — accepts a business identifier (domain, name+location, or business_id). Returns one or more validated phone numbers with line type (mobile/landline/voip), carrier, and country.
- **`validate_phone`** — accepts a phone number, validates format + reachability (without ringing). Catches mistyped/disconnected numbers before an outreach call.
- **`bulk_lookup`** — batch over a list of business identifiers.
- **`list_lookups`** + **`get_lookup_status`** — async + history.

### Why a separate skill from `scrape-website-extract-leads`?

SpiderSite extracts phone numbers FROM websites. VayaPin looks them up via specialized phone-data APIs. Both produce phone numbers but with different reliability:

- SpiderSite: as-good-as-the-website (might be marketing reception, might be outdated)
- VayaPin: validated against carrier records (much higher accuracy for direct dial)

### Typical workflows

- **Fill phone gaps** — after the main scraping pipeline, agent calls `bulk_lookup` for businesses that came back without phones.
- **Pre-call validation** — agent validates each phone in a calling list before handing off to a dialer.
- **Format normalization** — agent uses `validate_phone` to canonicalize numbers across formats (e.g. all to E.164).

### Approval requirement

VayaPin calls cost money per lookup and brands have explicit per-day caps. Some orgs additionally gate VayaPin behind manual approval (no auto-lookup loops). The skill respects those gates server-side; agents that exceed get a clear quota error.

### Audit trail

Every VayaPin lookup is logged per-brand with the agent's token prefix, surfacing in admin reports for cost attribution.
