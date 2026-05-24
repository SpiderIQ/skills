# recipes/booking/invite-staff-calendar

Invite staff to connect their calendar to a booking flow — calendar-OAuth-by-invite. The tenant doesn't ask each staff member to "log into the dashboard and click connect"; instead, staff click a per-staff email link, OAuth into Google/Outlook/iCloud, and they're done.

## When to use

- A tenant has a published `kind='booking'` flow but the slot grid is empty (no staff calendars connected).
- A staff member changed calendar providers (Gmail → Outlook) and needs to re-connect.
- A new staff member joined and you're adding them to the booking pool.

If you're cloning the booking template itself → [`clone-booking-template.md`](clone-booking-template.md). If you're authoring the booking flow → not yet covered; see the catalog/CLAUDE.md "Booking flows" section.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **A booking flow exists** (`kind='booking'`, status `draft` or `active`). The invite links scope to a specific `flow_id`.
3. **Staff members' email addresses.** The invite is sent to each staff email; they need to be able to receive it.
4. **A cal.com team for the tenant.** The team is what aggregates the connected calendars. Configured server-side at tenant onboarding.

## Why calendar-OAuth-by-invite (vs dashboard onboarding)

Staff who deliver bookings often aren't dashboard users — they're delivery contractors, hairdressers, sales reps, estate agents. Getting them through a "create an account, set a password, log in, navigate to Settings, click Integrations, click Connect Calendar" flow is brittle and often fails.

The invite flow:
1. Tenant adds the staff member by email.
2. SpiderPublish emails: "[Tenant] wants you to receive bookings via [Flow name]. Click here to connect your calendar."
3. Staff clicks. Lands on a hosted SpiderPublish page. OAuths into Google/Outlook/iCloud (provider auto-detected from email domain; staff confirms).
4. Done. Their calendar is in the pool. No password, no dashboard, no follow-up.

Mental model: this is the calendar-equivalent of "sign in with Google" for end users — one click, no account creation.

## The 3-call path

```
1. (book the flow if not done yet)         — clone-booking-template.md
2. booking_flow_invite_staff                — provision per-staff invite tokens + send emails
3. (staff click email, OAuth)               — outside SpiderPublish; verify via staff connection status
```

Then verify with a slot-grid check.

**Resolved 2026-05-24 — product gap flagged:** there is NO `booking_flow_invite_staff` MCP tool in `@spideriq/mcp` as of this writing. Staff-invite happens via REST at `POST /api/v1/booking/flows/{flow_id}/staff/invite` (file: [`app/api/v1/booking/`](https://github.com/SpiderIQ/SpiderIQ/tree/master/app/api/v1/booking)). Use CLI or curl until the MCP wrapper lands. Tracked for a future MCP-wrapper PR.

### 1. (Pre-flight) ensure the flow exists

```
booking_flow_get({ flow_id: "flow_..." })
// → { kind: "booking", status: "draft" | "active", calendar_pool: "main", ... }
```

If `status: "draft"` you can still invite staff — they'll be connected by the time you publish. If the response is `kind: "form"`, this recipe doesn't apply (forms don't use cal.com).

### 2. Send invites

```
booking_flow_invite_staff({
  flow_id: "flow_...",
  staff: [
    { email: "alice@<tenant-domain>.com", display_name: "Alice (lead consultant)" },
    { email: "bob@<tenant-domain>.com",   display_name: "Bob" },
    { email: "carol@<tenant-domain>.com", display_name: "Carol — Tuesdays only" }
  ],
  message: "Hi! We're switching to SpiderPublish for client consultations. Please connect your calendar — it's one click."   # optional intro text in the email
})
// → {
//     invited: [
//       { email: "alice@...", token: "inv_...", invite_url: "https://<tenant>/staff-invite/inv_...", sent_at: "..." },
//       ...
//     ],
//     errors: []   # populated for malformed emails or already-invited staff
//   }
```

Each staff member receives an email with the `invite_url`. The token in the URL is single-use, 30-day TTL.

### 3. Staff click + OAuth (outside SpiderPublish)

When the staff member clicks:

1. SpiderPublish hosts a page at `<tenant>/staff-invite/<token>`.
2. Page identifies the calendar provider from the email domain (e.g. `@gmail.com` → Google, `@<msft-org>.com` → Outlook). Staff can override.
3. Staff clicks "Connect Google Calendar." Standard OAuth handshake — Google asks for calendar read + write permission.
4. Token comes back; SpiderPublish stores it (encrypted at rest) keyed by `(tenant, staff_email, flow_id)`.
5. Calendar is in the pool. Staff sees a confirmation page; can close the tab.

You don't drive this step programmatically — wait for the staff member.

## Verify the connection landed

```
booking_flow_list_staff({ flow_id: "flow_..." })
// → [
//   { email: "alice@...", display_name: "Alice (lead consultant)", connected_at: "2026-05-...", calendar_provider: "google" },
//   { email: "bob@...",   display_name: "Bob", connected_at: null, invite_sent_at: "2026-05-..." },
//   { email: "carol@...", display_name: "Carol — Tuesdays only", connected_at: "2026-05-...", calendar_provider: "outlook" }
// ]
```

`connected_at: null` = invite sent but staff hasn't OAuthed yet. Either nudge them, or re-invite with `booking_flow_invite_staff` (idempotent — re-sends the email, refreshes the token).

Once at least one staff member shows `connected_at: <timestamp>`, the slot grid will populate when visitors hit `/f/<flow_id>`.

**Resolved 2026-05-24 — product gap flagged:** there is NO `booking_flow_list_staff` MCP tool. List staff via REST at `GET /api/v1/booking/flows/{flow_id}/staff` (returns `[{actor_id, email, role, calendar_status, connected_at, ...}, ...]`). Tracked for a future MCP-wrapper PR alongside `booking_flow_invite_staff`.

## Slot grid spot-check

The visitor's slot grid is empty if no staff connected. To verify slots populate:

```
content_visual_check({
  page_url: "https://<tenant>/f/<flow_id>?step=pick_slot",   # may need to walk through prior FormStep
  viewport: "desktop"
})
# Check for visible time slots in the screenshot.
```

Or hit the cal.com slot endpoint directly:

```bash
# Example — slot lookup for the next 7 days
curl -s "https://api.cal.com/v1/slots?event_type_id=<evt_id>&start=$(date -u +%Y-%m-%d)&end=$(date -u -d '+7 days' +%Y-%m-%d)" \
  -H "Authorization: Bearer <cal-com-token>"
# Returns array of slots; empty array = no availability.
```

## Re-invite / revoke

```
# Re-send the invite (refreshes the token, sends a new email)
booking_flow_invite_staff({ flow_id, staff: [{ email: "bob@..." }] })

# Revoke a staff member's access — they stop appearing in the slot grid pool
booking_flow_remove_staff({ flow_id, email: "carol@..." })
// → { removed: true, connected_at_removed: "..." }
```

Removal also revokes the stored OAuth token server-side (the cal.com integration disconnects). Staff can re-invite by repeating step 2.

## Anti-patterns

1. **Sending the invite email manually by copy-pasting the `invite_url`.** Use the email payload — it includes the right CTA + branding. Manual emails miss the auto-detected calendar provider hint + can land in spam.
2. **Publishing the booking flow BEFORE inviting staff.** The flow is live but `/f/<flow_id>` shows "No availability." Visitors bounce. Invite first, wait for connection, THEN publish.
3. **Inviting staff with personal calendars they don't want exposed.** Staff calendars are read for availability AND written-to with new bookings. If the staff member has personal events on the same calendar, they show as "busy" (good — avoids double-booking) but the calendar shows the booking event too (sometimes unwanted privacy-wise). Solution: a dedicated work calendar.
4. **Asking staff to "just give me their Google password" as a workaround.** Don't. Wait for them to OAuth. The OAuth flow is faster than account+password setup AND doesn't store their password.
5. **Mixing calendar providers in unsupported ways.** Some cal.com configs only allow one provider per team. Test the slot grid after every staff connects to confirm cal.com handles your mix.

## See also

- [`clone-booking-template.md`](clone-booking-template.md) — clone the booking flow before inviting staff
- [`embed-form.md`](embed-form.md) — embed the booking flow on a host page
- [`../reference/booking-model.md`](../reference/booking-model.md) — cal.com integration internals
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `booking_flow_*` tool catalog
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
- catalog/CLAUDE.md → "Calendar-OAuth-by-invite" — internal canonical pattern
