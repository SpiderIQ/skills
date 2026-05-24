# recipes/integrations/cal/booking-flow

End-to-end: cal.com event type → SpiderPublish `kind='booking'` flow with staff calendar invites. The cal.com side provides the calendar pool + availability engine; SpiderPublish provides the public `/f/<flow_id>` booking surface + theme + custom fields.

## When to use

- The tenant uses cal.com internally for team scheduling and wants a branded public booking page.
- Multi-staff round-robin booking ("the next available account exec") — cal.com handles the pool, SpiderPublish renders the form.
- Replacing the default cal.com landing page with a SpiderPublish-themed flow that asks custom intake questions before slot selection.
- Pattern: "cal.com is the calendar engine; SpiderPublish is the front door."

## Prerequisites

- A cal.com team account with an Event Type configured.
- cal.com API key (org-level, with `event-types:read` and `team-members:read` scopes).
- A SpiderPublish PAT scoped to the tenant.
- Staff emails ready (the cal.com team members who'll receive booking notifications).

## Step 1 — Pull the cal.com event type

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

## Step 2 — Create the SpiderPublish booking flow

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

## Step 3 — Invite staff (calendar pool wire-up)

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

See [`../../booking/invite-staff-calendar.md`](../../booking/invite-staff-calendar.md) for the full staff-invite recipe (verify endpoint, list staff, re-invite).

## Step 4 — Confirm cal.com ↔ SpiderPublish wiring

After staff connect their calendars:

```
booking_flow_get({ flow_id })
# → { ..., connected_staff_count: 3, cal_event_type_id: 12345, calendar_pool_slug: "<pool>" }

# Spot-check: visit /f/<flow_id> in a browser
# → intake questions appear first
# → after submit, slot grid populates with available 30-min slots from the cal.com pool
```

If the slot grid is empty:
- Confirm at least one staff member's `connected_at` is non-null (see [`../../booking/invite-staff-calendar.md`](../../booking/invite-staff-calendar.md))
- Confirm `cal_event_type_id` matches the live cal.com event
- Confirm the cal.com event's availability schedule has slots in the next 14 days

## Step 5 — Publish + embed

```
form_publish({ flow_id })              # safe-default gated
form_preview_url({ flow_id })          # → https://<tenant>/f/<flow_id>
```

To embed on an external site:

```
form_get_embed_snippet({ flow_id, mode: "inline" })
# → "<div data-spiderflow-flow=\"flow_...\"></div><script src=\"https://embed.spideriq.ai/v1/loader.js\" async></script>"
```

For embed inside a SpiderPublish page, see [`../../booking/form-as-page-section.md`](../../booking/form-as-page-section.md).

## Steps — full flow

```python
1. event = pull_cal_event_type(EVENT_TYPE_ID)
2. flow  = form_create(kind="booking", cal_event_type_id=event.id, ...)
3. invite_staff(flow_id=flow.id, emails=[...])
4. (staff click email → OAuth) — out of band
5. verify: booking_flow_get(flow.id).connected_staff_count > 0
6. form_publish(flow.id)
7. form_preview_url(flow.id) → share / embed
```

## Gotchas

- **cal.com and SpiderPublish use DIFFERENT IDs.** `cal_event_type_id` is cal.com's `id`; SpiderPublish stores it as a reference. Don't try to use one for the other.
- **Slot grid is live-pulled from cal.com on every page load.** No caching on the SpiderPublish side — if cal.com is down, the form shows a "no slots available" empty state with a retry message.
- **Booking confirmation routing**: the booking confirmation email (with calendar invite) is sent by **cal.com**, not SpiderPublish. SpiderPublish sends an optional "thank you" email; cal.com sends the actual `.ics`.
- **`requires_confirmation: true`** means booked slots are tentative until an admin clicks "confirm" in cal.com. Surface this in the SpiderForms thank-you screen so visitors know to expect a follow-up.
- **Pool members vs flow staff.** A cal.com team can have 20 members; you might want only 5 in this flow's pool. Configure the pool in cal.com first, then reference its slug from SpiderPublish.
- **Time zones.** cal.com handles TZ conversion based on visitor's browser. SpiderPublish passes through; don't try to second-guess.
- **Multi-event-type bookings** (visitor picks "30-min intro" OR "60-min deep dive") need ONE flow per event type. Cluster them via a "service picker" page that routes to /f/<flow_id_30min> vs /f/<flow_id_60min>.

## Verify

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

## Anti-patterns

- **Trying to skip cal.com and use SpiderPublish alone for calendar management.** SpiderPublish doesn't have an availability engine. cal.com is the calendar primitive; SpiderPublish is the surface.
- **Hardcoding `cal_event_type_id` in client-side code.** It lives in the flow row, not in the embed snippet. The embed loader reads it server-side at render time.
- **Inviting staff before publishing the flow.** Invites work on draft flows but tokens reference the flow_id; if you delete + recreate the flow, the tokens orphan.
- **Embedding the cal.com native widget alongside the SpiderForms booking flow.** Confuses visitors + double-books cal.com slots.
- **Forgetting the `requires_confirmation` surface.** Visitors book, expect immediate confirmation, get a "tentative" email instead.

## See also

- [`../../booking/clone-booking-template.md`](../../booking/clone-booking-template.md) — start from a booking template; same primitive, less boilerplate
- [`../../booking/invite-staff-calendar.md`](../../booking/invite-staff-calendar.md) — the staff-invite flow in detail (with its MCP-gap REST fallback)
- [`../../booking/form-as-page-section.md`](../../booking/form-as-page-section.md) — embed inside a SpiderPublish page
- [`../../booking/test-form-submission.md`](../../booking/test-form-submission.md) — verify the booking end-to-end
- [`../../reference/booking-model.md`](../../reference/booking-model.md) — the `booking_flows` schema, `/f/<id>` URL surface, cal.com / OAuth-by-invite spec
