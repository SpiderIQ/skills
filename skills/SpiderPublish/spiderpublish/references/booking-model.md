# reference/booking-model

The `booking_flows` data model — `kind` discriminator, `flow` JSONB shape, cal.com integration, calendar-OAuth-by-invite, the `kind='form'` vs `kind='booking'` URL collision, and the W13 incident that codified Rule 62. Cited by every `booking/` recipe.

## TL;DR

- **One table, four discriminators.** `booking_flows.kind ∈ { 'form' | 'booking' | 'funnel' | 'commerce' }`. `funnel` is alpha (Funnels P2/P3); `commerce` is reserved (future).
- **Same URL surface for all kinds.** `https://<tenant>/f/<flow_id>` regardless of kind. Legacy `/book/<id>` 301-redirects for `kind='booking'` only and silent-fails for `kind='form'` (the W13 incident root cause).
- **cal.com only fronts `kind='booking'`** for staff calendars + slot resolution. `kind='form'` ignores `length_minutes`, `team_id`, `title` even though `form_publish` accepts them (back-compat with the shared endpoint).
- **Visual-check assertion:** `dom.shadow_hosts.includes("spideriq-form")`. NEVER `body_text_preview` (cross-origin iframe = opaque to parent DOM). Rule 62.

## The `booking_flows` row

One row per form / booking / funnel / commerce flow. Key columns:

| Column | Type | Notes |
|---|---|---|
| `flow_id` | UUID | Canonical handle. Use this in every URL + tool call. |
| `kind` | text | `'form' | 'booking' | 'funnel' | 'commerce'`. Discriminator — every tool must branch on it. |
| `name` | text | Display name. Shown on the dashboard list + as `<title>` on `/f/<id>` chrome (when settings.SEO defaults apply). |
| `business_id` | UUID | FK → `businesses`. For `kind='form'`, the backend resolves a per-tenant sentinel business — pass nothing. For `kind='booking'`, your tenant's main business. |
| `status` | text | `'draft' | 'active' | 'archived'`. `/f/<id>` 404s until status flips to `'active'` via `form_publish` / `booking_flow_publish`. |
| `flow` | JSONB | The flow document — see "Flow JSONB shape" below. |
| `schema` | JSONB | Reserved for per-flow schema overrides (rarely used). |
| `schema_version` | text | Currently `'1.0.0'` for everything. Reserved for forward-compat. |
| `version` | int | Incremented on every publish. |
| `published_at` | timestamptz | Last publish time. |
| `is_locked`, `locked_by_actor_id`, `locked_at`, `locked_reason` | various | P4 page-lock pattern extended to forms — see `form_lock` / `form_unlock`. |
| `template_id` | UUID | When the form was cloned from a `booking_templates_global` row. Optional. |

## Flow JSONB shape (the `flow` column)

```json
{
  "kind": "form",
  "flow": [
    {
      "type": "FormStep",
      "id": "step_1",
      "fields": [
        { "id": "name",  "type": "text",  "label": "Your name",  "required": true },
        { "id": "email", "type": "email", "label": "Work email", "required": true }
      ]
    }
  ],
  "logic": [],
  "variables": {},
  "hidden_fields": [],
  "welcome_screens": [],
  "thankyou_screens": [],
  "theme": { "preset": "card-light", "tokens": { "--primary": "#ec4899" } }
}
```

| Key | Shape | Notes |
|---|---|---|
| `kind` | `'form'` etc. | Mirrors the column. Validated for consistency. |
| `flow[]` | Array of `{type, id, fields/...}` step objects | `FormStep` for forms; `BookingStep` / `SelectStep` / `PageStep` for booking + funnel. |
| `logic[]` | Array of `{id, when, op, then}` rules | Conditional routing — see `form_add_logic_rule`. |
| `variables{}` | `{ <name>: {type, default} }` | Declared variables for arithmetic / branching. |
| `hidden_fields[]` | Array of `{key, label, default_value?}` | URL-query-string capture (`?utm_source=twitter` → only declared keys are sourced; everything else is stripped). |
| `welcome_screens[]` | 4-key max: `title, description?, button_text, attachment?` | Pre-form intro. |
| `thankyou_screens[]` | 7-key strict (`extra=forbid` post-PR-#841): `id, title, description?, attachment?, button_mode, redirect_url?, is_default` | Post-submit screen. Exactly one MUST have `is_default=true` when the list is non-empty. **No `button_text` on ThankyouScreen** — CTA label is derived from `button_mode`. |
| `theme` | `{preset?, tokens?}` | Visual identity — see [recipes/booking/build-form.md](../booking/build-form.md) for the 6 presets + token catalog. |

## URL surface — the most-important table in this doc

| URL | Status | What it does |
|---|---|---|
| `https://<tenant>/f/<flow_id>` | ✅ Canonical | Renders both `kind='form'` AND `kind='booking'`. The Liquid renderer picks `templates/forms-standalone.liquid` (form) or `templates/booking-standalone.liquid` (booking) server-side based on `kind`. |
| `https://spideriq.ai/f/<flow_id>` | ✅ Also canonical | If the tenant hasn't deployed a custom domain (no `domain_list` entry), the form serves from `spideriq.ai/f/<id>` with minimal chrome. This is what `form_preview_url` returns by default. |
| `https://<tenant>/book/<flow_id>` | 🔁 301 → `/f/<id>` for `kind='booking'` only | Legacy URL kept for back-compat. **Silent-fails for `kind='form'`** — that's the W13 incident. |
| `https://forms.spideriq.ai/render/<flow_id>?embed=inline` | Internal cross-site iframe shell | What `embed.spideriq.ai/v1/loader.js` mounts inside the host page. Don't link to it directly. |

### Why the same URL serves both kinds

Forms and bookings share infrastructure (auth, sessions, submission persistence, embed loader). Splitting URL space `/f/` vs `/b/` would have meant two renderer templates, two CF Worker routes, two cache layers, two SEO surfaces — none of which add user value. The `kind` discriminator on the DB row is enough; the renderer reads it and picks the right Liquid template.

### Why `form_preview_url` returns a `spideriq.ai/f/<id>` URL, not the tenant's custom domain

`form_preview_url` is pure string composition — it doesn't call `domain_list` to find your tenant's verified domain. It returns `${apiUrl}/f/<flow_id>` where `apiUrl` is the workspace's configured `api_url` (default `https://spideriq.ai`). For a shareable URL on the tenant's verified domain (e.g. `demo.spideriq.ai/f/<id>`), call `content_list_domains`, pick the primary, and compose the URL yourself — OR deploy the tenant's site so the `spideriq.ai/f/<id>` URL is the canonical one. (S4-B5 fix 2026-05-20.)

## cal.com integration — `kind='booking'` only

For `kind='booking'` flows, SpiderPublish uses cal.com as the slot-resolver — cal.com owns the calendar grid, availability, conflict-detection, and ICS invites; SpiderPublish owns the conversational flow surrounding it (welcome screens, qualifying questions, post-booking thank-you).

### Flow

```
1. tenant creates booking flow via booking_flow_create or clone-booking-template
2. tenant invites staff via the calendar-OAuth-by-invite link (see invite-staff-calendar.md)
3. staff connects their calendar (Google / Outlook / iCloud) — OAuth tokens stored encrypted
4. tenant publishes the flow → booking_flow_publish provisions a cal.com event-type
   on the tenant's cal.com team (length_minutes, title, team_id are all consumed here)
5. visitor lands on /f/<flow_id>
   → answers qualifying questions
   → SpiderPublish queries cal.com /slots for the relevant staff calendars
   → visitor picks a slot
   → SpiderPublish POSTs /bookings to cal.com
   → cal.com sends the ICS invite to all parties
6. booking row written to booking_submissions; webhook fires to the tenant's CRM if configured
```

### `length_minutes`, `team_id`, `title` on `form_publish`

`form_publish` and `booking_flow_publish` share the same backend endpoint. The endpoint *accepts* `length_minutes`, `team_id`, `title` for both kinds — but for `kind='form'`, the cal.com provisioning step is skipped entirely. The fields are ignored.

This means:

- For a form: pass `length_minutes: 1` and `team_id: 0` and any `title` — they're noise but the endpoint accepts them. (Or use `auto_create: true` on `form_create_from_template`, which calls `form_create` then `form_publish` with sensible defaults.)
- For a booking: pass real values. `length_minutes` is the event duration shown to visitors; `team_id` MUST match a real cal.com team your tenant owns; `title` is what appears in the visitor's calendar invite.

## Calendar-OAuth-by-invite (the staff onboarding pattern)

The tenant doesn't ask each staff member to log into the dashboard and click "Connect calendar." Instead:

1. Tenant creates a booking flow + identifies which staff members should receive bookings.
2. Tenant generates per-staff invite links (`POST /booking/flows/{flow_id}/invite-staff`).
3. SpiderPublish emails each staff member: "Click here to connect your calendar to <flow name>."
4. Staff clicks → goes to a hosted SpiderPublish page → OAuths into Google / Outlook / iCloud → done.
5. Their calendar is now in the slot-resolver pool for that booking flow.

Why the indirection: staff often aren't dashboard users (they're a delivery contractor, an estate agent, a salon stylist). Calendar-OAuth-by-invite skips the dashboard onboarding and gets them productive in one click. See [`../booking/invite-staff-calendar.md`](../booking/invite-staff-calendar.md) for the recipe.

## Visual-check — the Rule 62 assertion

When you `content_visual_check({ page_url: "https://<tenant>/f/<flow_id>", viewport: "desktop" })` on a form-rendering URL, the sidecar Playwright instance loads the page and returns:

```json
{
  "success": true,
  "screenshot_url": "https://media.spideriq.ai/visual-check/...",
  "dom": {
    "shadow_hosts": [ "spideriq-form" ],
    "elements_seen": 142
  },
  "body_text_preview": "<!doctype html>... [host page chrome, NOT iframe contents] ...",
  "console_errors": []
}
```

**To assert the form mounted correctly, check `dom.shadow_hosts.includes("spideriq-form")`. NEVER `body_text_preview`.**

### Why

The form renders inside a cross-origin iframe served by `forms.spideriq.ai/render/<id>?embed=inline`. The iframe's body is **opaque** to the parent page's DOM — Playwright sees the host page's HTML, not the iframe's contents. Asserting `expected_text: ["First name"]` against a working form returns `expected_text_missing: ["First name"]` and incorrectly reports FAIL. The correct signal is the presence of the `<spideriq-form>` custom element in `dom.shadow_hosts` — that proves the loader mounted the host element, which only happens after the loader's preflight succeeds.

This rule is codified in:
- The `content_visual_check` MCP tool description (`packages/mcp-tools/src/publish/content.ts:1805`)
- VSCode extension v0.4.0 visualCheckPanel's "Add assertion" affordance
- `?format=llm` `guidance.warn` on `GET /forms/<id>`
- catalog/LEARNINGS.md Rule 62

If you remove the rule, the cycle is: visual-check FAILs → agent assumes the form is broken → agent re-deploys / patches a non-existent bug → cycle repeats. Empirically caught by Antigravity Verifier B 2026-05-20.

## The W13 incident (why honest URL composition matters)

2026-05-18: Antigravity (a paying IDE-agent client) called `form_preview_url` on a `kind='form'` flow and received `https://<tenant>/book/<flow_id>` — because the tool's `description` had been written when only `kind='booking'` existed and was never updated for forms. The agent confidently built 8 iframes around `/book/<id>` URLs and shipped 8 "We couldn't load this booking" cards to production. ~24h triage cycle; client trust damaged.

What `form_preview_url` returns now (post-S4-B5):

```
{ "public_url": "https://spideriq.ai/f/<flow_id>", ... }
```

Notice it returns `/f/<id>`, not `/book/<id>`, regardless of `kind`. Same for `form_get_embed_snippet`. **Never compose form URLs by hand.** The W13-class incident class is structurally closed by the tools themselves; recipes must reinforce by always calling the tool, never string-templating.

Codified in:
- LEARNINGS.md Rule 62 (visual-check assertion)
- LEARNINGS.md Rule 65 (template-honesty about server-side picker variants)
- LEARNINGS.md Rule 67 (probe deploy path before naming a URL in a worktree)
- catalog/CLAUDE.md "Agent honesty contract"

## Field types (25, verbatim from `app/schemas/booking.py FieldType`)

When authoring fields via `form_create` / `form_add_field`, only these `type` values are accepted. The validator 422s on anything else.

```
Basics:        text · email · phone · tel · textarea · select · checkbox · consent ·
               number · date · time
Specialty:     rating · nps · opinion_scale · picture_choice · file_upload · statement
IDAP-anchored: url · country · region · postal_code · address · datetime · currency · place
```

**Anti-hallucinations the API 422s on:**

| ❌ Don't | ✅ Do |
|---|---|
| `short_text` | `text` |
| `long_text` | `textarea` |
| `yes_no` / `boolean` / `radio` | `select` with two `options`, OR `checkbox` for single toggle |
| `file` | `file_upload` (with required `accept` array) |

**Per-field-type conditional requirements** (422 with structured envelope post-PR-#841):

| Field type | Required | Forbidden |
|---|---|---|
| `rating` | `shape ∈ {star, heart, thumb, thunderbolt}` | — |
| `opinion_scale` | `steps` (integer, 5..11) | — |
| `nps` | — | `steps` (fixed 0..10) |
| `picture_choice` | `options[]` (≥2, each with `image_url`) | — |
| `file_upload` | `accept[]` (MIME types) | — |
| `statement` | `body` | `required: true`, `crm_target`, `media` |

`crm_target` is NOT accepted on `form_create`; set per-field after with `form_update_field` (F-9).

## Anti-patterns

1. **Composing `/book/<id>` for a `kind='form'`.** Use `form_preview_url` / `form_get_embed_snippet`. The W13 root cause.
2. **Asserting on `body_text_preview` after `content_visual_check` for a form.** Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.
3. **Passing `business_id` on `form_create` for `kind='form'`.** 422. The backend resolves the per-tenant sentinel business — pass nothing.
4. **Passing `crm_target` on `form_create` field shapes.** Use `form_update_field` after create — F-9 caveat.
5. **Adding a `button_text` to a `ThankyouScreen`.** 422 post-PR-#841 — the CTA label is derived from `button_mode`. To customize, set `button_mode: "redirect"` + `redirect_url`. `WelcomeScreen` DOES accept `button_text` (different shape).
6. **Forgetting to publish.** `/f/<flow_id>` returns 404 until `status='active'`. `form_validate` runs locally; `form_publish` flips the status.
7. **Skipping `form_validate` after a long edit session.** 14 rule classes for free — catches "added a `picture_choice` field without `image_url` on its options."

## See also

- [`../booking/build-form.md`](../booking/build-form.md) — gold-standard form-design recipe (theme presets, tokens, per-question media)
- [`../booking/build-lead-gen-form.md`](../booking/build-lead-gen-form.md) — end-to-end 6-call lead-gen pipeline
- [`../booking/clone-form-template.md`](../booking/clone-form-template.md) — one-shot template clone
- [`../booking/clone-booking-template.md`](../booking/clone-booking-template.md) — booking equivalent (cal.com-backed)
- [`../booking/invite-staff-calendar.md`](../booking/invite-staff-calendar.md) — calendar-OAuth-by-invite
- [`../booking/embed-form.md`](../booking/embed-form.md) — inline / popup / standalone embed
- [`deploy-protocol.md`](deploy-protocol.md) — `form_publish` and `form_delete` gate flavour
- [`tool-surface.md`](tool-surface.md) — `form_*` tool family map
- catalog/LEARNINGS.md Rules 62 / 65 / 67 — source incidents
