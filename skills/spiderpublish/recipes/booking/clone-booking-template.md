# recipes/booking/clone-booking-template

Clone a global booking template into your tenant — cal.com-backed calendar slots, staff calendar resolution, ICS invites. Sibling to `clone-form-template.md` but for `kind='booking'`.

## When to use

- A tenant runs a service business (clinic, salon, agency, consultant) that needs visitors to book time slots on a real calendar.
- You want a multi-step intake-then-book flow: qualifying questions → calendar slot picker → confirmation.
- You're matching a Calendly/SavvyCal-style flow but want it on your tenant's domain + your tenant's branding.

For a simple data-collection form (no calendar) → [`clone-form-template.md`](clone-form-template.md). For inviting staff to connect their calendars → [`invite-staff-calendar.md`](invite-staff-calendar.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **MCP server with `booking_flow_*` tools.** Lives in `@spideriq/mcp` (kitchen-sink) alongside `form_*`. Same package picker rules as forms.
3. **A cal.com team set up for the tenant.** Booking flows back onto cal.com for the slot grid + staff calendar resolution. Without a cal.com team, `booking_flow_publish` can't provision an event-type. Check with the tenant whether their cal.com team exists; if not, set it up via the dashboard (Settings → Integrations → cal.com).
4. **(For each staff calendar)** Calendar-OAuth completed via invite. See [`invite-staff-calendar.md`](invite-staff-calendar.md).

## The 3-call path

```
1. (browse) — same as form_list_global_templates but filter for kind='booking'
2. booking_flow_clone_template / booking_create_flow — clone the template
3. booking_flow_publish — provision the cal.com event-type + go live
```

The exact MCP tool names for the booking surface match the form surface where there's parity (`booking_flow_get`, `booking_flow_update`, `booking_flow_delete`, etc.) and add cal.com-specific tools (`booking_flow_publish` provisions cal.com, the staff-invite flow uses dedicated endpoints).

<!-- VERIFY: confirm whether @spideriq/mcp exposes `booking_flow_list_templates` or whether browsing booking templates goes through the same `form_list_global_templates({ kind: "booking" })` filter. The form-specific helper filters server-side; the booking helper may live under a different name. Codify after grep. -->

### 1. Browse booking templates

```
# If the booking-specific MCP helper exists:
booking_flow_list_templates({ category: "consultation" })

# Fallback — use the generic flows endpoint (filters server-side by kind=booking):
# GET /api/v1/dashboard/booking/templates/global?kind=booking
```

Each template comes with a pre-populated flow shape:

```
{
  template_id: "tmpl_...",
  slug: "30min-consultation",
  name: "30-minute consultation",
  category: "consultation",
  flow: {
    kind: "booking",
    flow: [
      { type: "FormStep", id: "qualify",  fields: [...] },
      { type: "BookingStep", id: "pick_slot", length_minutes: 30, calendar_pool: "main" }
    ],
    theme: { preset: "card-light" }
  },
  cal_defaults: { length_minutes: 30, team_id_required: true }
}
```

The `BookingStep` is the calendar-picker step (what cal.com renders). It declares `length_minutes` (event duration) and `calendar_pool` (which staff calendars are eligible — typically `"main"` for the tenant's main team).

### 2. Clone

```
# Tool name pending grep — see VERIFY note above.
booking_flow_clone_template({
  slug: "30min-consultation",
  name: "Acme consultation"
})
// → {
//     flow_id: "flow_...",
//     template_id: "tmpl_cloned_...",
//     status: "draft",
//     business_id: "biz_...",    // tenant's main business — required for booking
//     ...
//   }
```

Unlike forms, **booking flows DO require `business_id`** — they're scoped to a specific business unit, which is what cal.com sees when it provisions the event-type. The tenant's main business is auto-resolved by the clone tool.

### 3. Publish (provisions cal.com)

```
booking_flow_publish({
  flow_id: "flow_...",
  title:          "Acme consultation",        # REQUIRED for booking — cal.com event title shown to attendees
  length_minutes: 30,                          # REQUIRED — event duration
  team_id:        12345                        # REQUIRED — your cal.com team ID
})
# → { dry_run: true, preview, confirm_token: "cft_..." }

booking_flow_publish({
  flow_id:        "flow_...",
  title:          "Acme consultation",
  length_minutes: 30,
  team_id:        12345,
  confirm_token:  "cft_..."
})
# → { status: "active", flow_id: "flow_...", cal_event_type_id: "evt_..." }
```

**Critical:** For `kind='booking'`, `title`, `length_minutes`, `team_id` are **REQUIRED**. The cal.com event-type is provisioned with these values — visitors see `title` in their calendar invite, the slot grid shows blocks of `length_minutes`, and the calendar pool is your `team_id`'s connected calendars.

(For `kind='form'`, the same fields are accepted but ignored — opposite of booking. The shared endpoint surface is why `form_publish` accepts the cal.com fields; they're for booking only.)

## Calendar pool — how slot resolution works

Once published, when a visitor lands on `/f/<flow_id>` and reaches the `BookingStep`:

1. SpiderPublish calls cal.com `GET /slots?team_id=<id>&event_type_id=<id>&start=...&end=...`.
2. cal.com aggregates availability across every connected staff calendar in the team.
3. cal.com returns 15-min (or `length_minutes`) blocks where ALL staff (or AT LEAST ONE staff, depending on team config) are available.
4. SpiderPublish renders these blocks. Visitor picks one.
5. SpiderPublish POSTs `POST /bookings` to cal.com with the visitor's name + email + chosen slot.
6. cal.com sends ICS invites to (a) the staff member resolved for that slot, (b) the visitor.
7. SpiderPublish writes the booking row to `booking_submissions`; webhook fires to the tenant's CRM if configured.

If no staff has connected their calendar yet, the slot grid is empty and visitors see "No availability." Solution: [`invite-staff-calendar.md`](invite-staff-calendar.md).

## Customize after clone

Same shape as form customization:

```
# Add a qualifying question to the FormStep
booking_flow_add_field({
  flow_id: "flow_...",
  step_id: "qualify",
  field: {
    id: "service_type",
    type: "select",
    label: "What are you booking?",
    options: [
      { label: "Initial consultation", value: "initial" },
      { label: "Follow-up",            value: "followup" }
    ]
  }
})

# Change the theme
booking_flow_update({
  flow_id: "flow_...",
  changes: { flow: { theme: { preset: "minimal-print", tokens: { "--primary": "#0f172a" } } } }
})

# Change calendar pool (which staff are eligible)
# NOTE: pool changes happen via cal.com directly — manage team membership there.
```

<!-- VERIFY: confirm whether `booking_flow_add_field` exists OR whether step-level field additions go through `booking_flow_update({ changes: { flow: { flow: [{ ... }] } } })`. Form tools have dedicated add_field; booking surface may not. -->

## Embed + share

Same as forms — `/f/<flow_id>` is the canonical URL for both kinds. Use `form_preview_url` (works for both) or compose `https://<tenant>/f/<flow_id>` directly. Or `form_get_embed_snippet` for inline / popup embeds.

```
form_preview_url({ flow_id: "flow_..." })
// → { public_url: "https://spideriq.ai/f/flow_...", ... }
```

## Verify

```
content_visual_check({
  page_url: "https://<tenant>/f/<flow_id>",     # NOT /book/<id> for newly-created flows
  viewport: "desktop"
})
# Assert on dom.shadow_hosts.includes("spideriq-form")
```

Also confirm:
- A test booking submission lands in `booking_submissions` (or trigger via the dashboard).
- The visitor receives the ICS invite.
- The staff member's calendar shows the new event.

If the ICS invite never arrives: check cal.com event-type config (event-type might be set to "private" or "require approval").

## Anti-patterns

1. **Calling `form_create_from_template` for a booking template.** It 422s — `Template "X" is kind="booking", not "form".` Use the booking equivalent (`booking_flow_clone_template`).
2. **Forgetting `title` / `length_minutes` / `team_id` on `booking_flow_publish`.** The cal.com provisioning step needs all three. Publish 422s without them. (For `kind='form'`, the same fields are ignored — opposite default.)
3. **Publishing before staff have connected their calendars.** The flow is live but the slot grid is empty → visitors see "No availability" and bounce. Always send the staff calendar-invite emails BEFORE publishing.
4. **Constructing `/book/<flow_id>` for the visitor URL.** Use `/f/<flow_id>` — same as forms. `/book/<id>` is a 301 redirect for `kind='booking'` (back-compat), but constructing the legacy URL is the W13-class footgun. Always use `form_preview_url` / `form_get_embed_snippet`. Rule 62.
5. **Mixing cal.com-managed config with SpiderPublish-managed.** Team membership, calendar pool, event-type duration → cal.com owns these. Qualifying questions, theme, embed → SpiderPublish owns. Don't try to set event-type duration via `booking_flow_update`.

## See also

- [`clone-form-template.md`](clone-form-template.md) — same path, `kind='form'` (no cal.com)
- [`invite-staff-calendar.md`](invite-staff-calendar.md) — connect staff calendars (do this BEFORE publish)
- [`build-form.md`](build-form.md) — theme / token / per-question media (applies to booking surface too)
- [`embed-form.md`](embed-form.md) — inline / popup / standalone embed
- [`../reference/booking-model.md`](../reference/booking-model.md) — `booking_flows` schema, cal.com integration, URL surface
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `booking_flow_*` tool catalog
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
