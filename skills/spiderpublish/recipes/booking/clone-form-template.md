# recipes/booking/clone-form-template

Clone a global form template into your tenant — one MCP call, one publish, you're live. Use `auto_create: true` for the one-shot path.

## When to use

- A tenant needs a standard form (contact, lead-gen, NPS survey, intake) and you want to start from a curated template instead of authoring from scratch.
- You're spinning up a new tenant and want to seed it with 3-5 baseline forms (contact-form, nps-survey, etc.).
- You want to start from a "good enough" template and then customize fields / theme / logic on top.

For a fully custom form authored field-by-field → [`build-form.md`](build-form.md). For booking-kind templates (cal.com integration) → [`clone-booking-template.md`](clone-booking-template.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Form tools available.** `form_*` tools live in `@spideriq/mcp` (kitchen-sink, 134+ tools), NOT in `@spideriq/mcp-publish` (the 87-tool atomic build). If your MCP entry is `mcp-publish`, switch to `mcp` for this recipe — see [`../reference/tool-surface.md`](../reference/tool-surface.md).

## The 3-call path (with `auto_create: true`)

```
1. form_list_template_categories         — see the ~20 category slugs
2. form_list_global_templates({ category }) — browse + pick the template slug
3. form_create_from_template({ slug, auto_create: true })  — clone AND materialize a draft form
```

Then `form_publish` to flip live, `form_get_embed_snippet` to embed.

### 1. List categories

```
form_list_template_categories()
// → { categories: [
//   "contact", "lead_gen", "survey", "application", "event_rsvp",
//   "registration", "order", "booking_intake", "donation", "feedback",
//   "quiz", "signup", "evaluation", "consent", "intake",
//   "onboarding", "assessment", "waitlist", "inquiry", "referral"
// ] }
```

Roughly 20 categories. Pick the closest match to what the tenant needs — there's no hard rule about which template goes in which (the catalog is shaped by authoring brand convention, not enforced taxonomy).

### 2. Browse templates

```
form_list_global_templates({ category: "contact", limit: 10 })
// → {
//     items: [
//       { template_id: "tmpl_...", slug: "contact-form", name: "Contact form (basic)",
//         category: "contact", description: "Name, email, message", is_official: true, usage_count: 412 },
//       { template_id: "tmpl_...", slug: "contact-form-with-phone", name: "Contact form (with phone)", ... }
//     ],
//     next_cursor: null
//   }
```

`slug` is the stable identifier. `usage_count` is a quality signal — popular templates have been used + battle-tested by many tenants. `is_official: true` = authored by the SpiderIQ team (vs community contributions).

Omit `category` to browse everything; use `cursor` for pagination (50 per page by default, 200 max).

### 3. Clone with `auto_create: true` (the one-shot)

```
form_create_from_template({
  slug: "contact-form",
  name: "Acme — contact us",     // optional rename; default: template's name
  auto_create: true              // one-shot: clones template AND creates a live draft form
})
// → {
//     success: true,
//     template_id: "tmpl_cloned_...",     // the per-tenant template copy
//     flow_id: "flow_...",                // the live draft form, ready to publish
//     form: { ... },
//     cloned_from: "tmpl_source_...",
//     source_slug: "contact-form",
//     source_name: "Contact form (basic)",
//     _auto_create_applied: true
//   }
```

That's the one-shot. After this call:

- A template clone lives in `booking_templates_global` (per-tenant).
- A live draft form lives in `booking_flows` (`flow_id`) — fields, theme, screens, all pre-populated from the template.
- Status is `draft`. The form is at `/f/<flow_id>` returns 404 until you publish.

### The two-step path (when you want to inspect before materializing)

If you want to look at the template, maybe mutate it, then decide whether to create a form — omit `auto_create`:

```
form_create_from_template({ slug: "contact-form" })
// → {
//     success: true,
//     template_id: "tmpl_cloned_...",    // ONLY the template clone
//     cloned_from: "tmpl_source_...",
//     source_slug: "contact-form",
//     template: { /* template body — flow.flow, fields, theme, etc. */ }
//   }
```

No `flow_id` in this response. Then `form_create({ fields: <template.flow.flow[0].fields>, theme: <template.flow.theme>, name, template_id: <tmpl_cloned_...> })` to materialize.

Use the two-step when you need to inspect / mutate the template before creating a form — uncommon. The one-shot is the high-traffic path.

## After cloning — publish + embed

```
# Form_validate is FREE — runs locally
form_validate({ flow: <flow JSON from the clone response> })
// → { valid: true, errors: [], warnings: [] }

# Publish — Phase 11+12 safe-default (dry_run=true)
form_publish({ flow_id: "flow_..." })
// → { dry_run: true, preview, confirm_token: "cft_..." }

form_publish({ flow_id: "flow_...", confirm_token: "cft_..." })
// → { status: "active", flow_id: "flow_..." }
```

For `kind='form'` flows, `title`, `length_minutes`, `team_id` on `form_publish` are accepted but **ignored** at render time (cal.com provisioning skipped). Pass `length_minutes: 1, team_id: 0, title: "any string"` OR omit them — both work. See [`../reference/booking-model.md`](../reference/booking-model.md#calcom-integration--kindbooking-only).

Once `status: active`, embed:

```
form_get_embed_snippet({ flow_id: "flow_...", mode: "inline" })
// → {
//     snippet: "<div data-spiderflow-flow=\"flow_...\" data-spiderflow-mode=\"inline\"></div>\n<script src=\"https://embed.spideriq.ai/v1/loader.js\" async></script>",
//     loader_url: "https://embed.spideriq.ai/v1/loader.js"
//   }
```

Drop into any page. See [`embed-form.md`](embed-form.md) for inline + popup + standalone embed paths.

## Customize after clone

The cloned form is yours — mutate freely:

```
# Change the theme
form_update({
  flow_id: "flow_...",
  changes: { flow: { theme: { preset: "agency-bold", tokens: { "--primary": "#ec4899" } } } }
})

# Add a follow-up field
form_add_field({
  flow_id: "flow_...",
  field: {
    id: "company_size",
    type: "select",
    label: "How big is your team?",
    options: [
      { label: "Just me",     value: "solo" },
      { label: "2-10",        value: "small" },
      { label: "11-50",       value: "medium" },
      { label: "51+",         value: "large" }
    ]
  }
})

# Add conditional logic
form_add_logic_rule({
  flow_id: "flow_...",
  rule: {
    when: { field: "company_size", op: "eq", value: "large" },
    then: { type: "jump_to", target: "enterprise_questions_step" }
  }
})
```

See [`build-form.md`](build-form.md) for the full field-authoring catalog and [`build-lead-gen-form.md`](build-lead-gen-form.md) for end-to-end customization.

## Verify

```
# 1. The standalone URL renders
content_visual_check({
  page_url: "https://<tenant>/f/<flow_id>",     # NOT /book/<id> — see Rule 62
  viewport: "desktop"
})
# Assert on dom.shadow_hosts.includes("spideriq-form") — NOT on body_text_preview.

# 2. The embed snippet works on a host page
# (paste the snippet into a SpiderPublish page block OR an external test page; visit)
```

## Anti-patterns

1. **Cloning a `kind='booking'` template via `form_create_from_template`.** The tool 422s with `Template "X" is kind="booking", not "form". Use booking_flow_clone_template for booking-kind templates.` See [`clone-booking-template.md`](clone-booking-template.md).
2. **Forgetting to publish.** `auto_create: true` gives you a draft form — `/f/<flow_id>` returns 404 until `form_publish` flips status to `active`.
3. **Composing `/book/<flow_id>` for a `kind='form'` URL.** The W13 incident. Use `form_preview_url` or `form_get_embed_snippet`. URL is always `/f/<id>`. Rule 62.
4. **Passing `business_id` on `form_create` after the two-step clone.** 422 — `kind='form'` resolves a per-tenant sentinel business. Omit `business_id`. (`auto_create: true` handles this for you.)
5. **Skipping `form_validate` after customizing.** Free client-side check; catches "added a picture_choice without image_url on its options."

## See also

- [`build-form.md`](build-form.md) — the gold-standard form design recipe (theme presets + tokens + per-question media)
- [`build-lead-gen-form.md`](build-lead-gen-form.md) — end-to-end 6-call lead-gen pipeline
- [`embed-form.md`](embed-form.md) — inline / popup / standalone embed
- [`clone-booking-template.md`](clone-booking-template.md) — booking-kind equivalent
- [`../reference/booking-model.md`](../reference/booking-model.md) — `booking_flows` schema, URL surface, Rule 62
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `form_*` tool catalog, MCP package picker
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
