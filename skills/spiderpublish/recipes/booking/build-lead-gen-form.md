# recipes/build-lead-gen-form

Ship a multi-step lead-gen Form end-to-end — author the fields, give it a theme, publish, and embed on a SpiderPublish page (or any third-party site) in under ten tool calls.

## When to use

- A tenant needs a multi-step lead-capture form (email + company + team size, plus a contact-method picker).
- You're replacing a Typeform / Tally form and want one MCP-driven pipeline that lives next to the rest of the site.
- The form needs to ship on the tenant's own domain at `/f/<flow_id>` AND embed on an external site (Webflow, Shopify, plain HTML).
- You want the form themed (preset + token overrides) at create time so the first publish already matches the brand.

If you only need a single email field at the bottom of a page → use a `form` block on a page instead. Forms are for multi-step / conditional flows.

## Pre-flight (one-time, per session)

The `form_*` tools are in `@spideriq/mcp@1.13.0+`, **not** in `@spideriq/mcp-publish`. If your `.mcp.json` points at `mcp-publish`, you have two options before continuing:

1. Switch the existing entry to `@spideriq/mcp@1.13.0` — gets you the full surface (publish + booking + forms + mail + leads + gate + admin).
2. Add a second MCP server entry pointing at `@spideriq/mcp` and only enable it in form-authoring sessions.

See [core-skills/forms/SKILL.md → MCP package caveat](../../core-skills/forms/SKILL.md#mcp-package-caveat) for the rationale.

## The 6-call path

```
1. form_create        — name + initial fields + theme         → flow_id
2. form_add_field     — append the "contact method" picker
3. form_add_field     — append a long_text "anything else?"
4. form_validate      — local structural check (no API call)
5. form_publish       — draft → active (2-phase confirm)
6. form_get_embed_snippet — copy-paste HTML for any page
```

Step 1 alone is enough for a minimal three-field form (email + company + team size). Steps 2–3 add depth; 4 is a free sanity check; 5 flips the form live; 6 hands you the embed snippet for any third-party page.

### 1. Create the form

```
form_create({
  name: "Free trial signup",
  fields: [
    {
      id: "work_email",
      type: "email",
      label: "Your work email",
      required: true,
      placeholder: "you@company.com"
    },
    {
      id: "company_name",
      type: "text",
      label: "Company name",
      required: true
    },
    {
      id: "team_size",
      type: "select",
      label: "Team size",
      required: true,
      options: [
        { label: "Just me",  value: "solo"   },
        { label: "2 – 10",   value: "small"  },
        { label: "11 – 50",  value: "medium" },
        { label: "51+",      value: "large"  }
      ]
    }
  ],
  theme: {
    preset: "card-light",
    tokens: {
      "--primary":        "#1f6feb",
      "--font-heading":   '"Inter", system-ui, sans-serif',
      "--button-radius":  "999px"
    }
  }
})
// → { flow_id: "<uuid>", kind: "form", schema_version: "1.0.0" }
```

**Notes:**

- **`business_id`** — do NOT pass it. As of `@spideriq/mcp@1.13.0+` the backend resolves a per-tenant sentinel business automatically for `kind="form"`; passing it now returns `422`.
- **`id`** — lowercase letters / digits / underscores, must start with a letter, ≤ 64 chars.
- **`type`** — see the [full list of field types](../../core-skills/forms/SKILL.md) (15+ including `text`, `email`, `phone`, `number`, `select`, `checkbox`, `picture_choice`, `rating`, `nps`, `opinion_scale`, `date`, `file_upload`, plus the W13.3 IDAP-anchored types — see [recipes/idap-fill-from-form](../idap-fill-from-form/SKILL.md)).
- **`theme`** — optional, but ships better than the neutral fallback. See [recipes/design-a-form](../design-a-form/SKILL.md) for the full preset + token catalog.

### 2 + 3. Add follow-up fields

```
form_add_field({
  flow_id: "<flow_id>",
  field: {
    id: "contact_method",
    type: "select",
    label: "How should we reach you?",
    required: true,
    options: [
      { label: "Email",       value: "email" },
      { label: "Phone",       value: "phone" },
      { label: "Either works", value: "either" }
    ]
  }
})

form_add_field({
  flow_id: "<flow_id>",
  field: {
    id: "anything_else",
    type: "textarea",
    label: "Anything we should know about your use case?",
    required: false,
    placeholder: "Optional — but it helps us prep your trial"
  }
})
```

### 4. Validate (free)

```
form_validate({ flow: <full flow blob from form_get> })
// → { errors: [], warnings: [] }
```

`form_validate` runs entirely client-side against the locked schema (14 rule classes: shape, kind/schema_version, field-type invariants, hidden-field key uniqueness, logic rule cross-references, …). No API call. Useful as a pre-publish sanity check, especially after a long authoring session where the agent may have added a field whose options[] shape doesn't match its type.

### 5. Publish (2-phase confirm)

```
form_publish({
  flow_id:         "<flow_id>",
  title:           "Free trial signup",
  length_minutes:  1,
  team_id:         0
})
// → { dry_run: true, confirm_token: "cft_xxx", expires_at: "<+7d>" }

form_publish({
  flow_id:         "<flow_id>",
  title:           "Free trial signup",
  length_minutes:  1,
  team_id:         0,
  confirm_token:   "cft_xxx"
})
// → { status: "active", flow_id: "<flow_id>" }
```

**Backend caveat (current state):** `title`, `length_minutes`, `team_id` are required because `form_publish` shares the underlying endpoint with cal.com bookings. For form-kind flows pass any non-empty `title`, `length_minutes=1`, `team_id=0` — they're ignored at render time. Resolved in P1.M1 (backend goes kind-aware).

### 6. Get the embed snippet

```
form_get_embed_snippet({
  flow_id:       "<flow_id>",
  mode:          "popup",
  button_text:   "Start Free Trial"
})
// → {
//     snippet: "<button data-spiderflow-flow=\"<flow_id>\" data-spiderflow-mode=\"popup\" data-spiderflow-trigger-text=\"Start Free Trial\">Start Free Trial</button>\n<script src=\"https://embed.spideriq.ai/v1/loader.js\" async></script>",
//     loader_url: "https://embed.spideriq.ai/v1/loader.js"
//   }
```

Two modes:

| Mode | Use when |
|---|---|
| `inline` | The form is the page hero / a dedicated section — replaces a `<div>` with the rendered widget |
| `popup` | The form opens from a CTA button (modal iframe, lazy-loaded so it doesn't fetch until clicked) |

`prefill` lets you pre-populate hidden fields from the host page (e.g. `{ utm_source: "twitter" }` → `data-prefill-utm_source="twitter"` on the embed element).

## Embed on a SpiderPublish page

The cleanest way to drop the form on a tenant page is the `{% form %}` Liquid tag — it inlines the form server-side instead of loading the embed iframe. See [examples/build-lead-gen-form.sh](../../examples/build-lead-gen-form.sh) for the end-to-end shell pipeline (form_create → form_publish → page block referencing the flow_id).

## Embed on an external site

The snippet from step 6 drops anywhere — Webflow, Shopify, WordPress, Framer, plain HTML. The loader bundle is ~3 KB gzip, served from a single CDN URL, and one `<script>` tag handles both inline and popup embeds.

```html
<!-- Inline -->
<div data-spiderflow-flow="<flow_id>" data-spiderflow-mode="inline"></div>
<script src="https://embed.spideriq.ai/v1/loader.js" async></script>

<!-- Popup -->
<button data-spiderflow-flow="<flow_id>" data-spiderflow-mode="popup"
        data-spiderflow-trigger-text="Start Free Trial">Start Free Trial</button>
<script src="https://embed.spideriq.ai/v1/loader.js" async></script>
```

The loader does origin validation on every postMessage from the form iframe (`event.source === iframe.contentWindow && event.origin === configured_domain`) — two embeds on the same page never cross-talk.

## Hidden fields (URL-param capture)

If you want to capture `utm_source`, `ref`, or any other URL-param onto the lead row, declare them as hidden fields BEFORE you publish:

```
form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "utm_source", label: "UTM source" }
})

form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "utm_campaign", label: "UTM campaign" }
})
```

Hidden-field keys are matched against the URL's query string at form load (`?utm_source=twitter&utm_campaign=launch`). Duplicates rejected client-side.

## Anti-patterns

- **Don't pass `business_id` on a form-kind `form_create` call** — backend `422`s. The sentinel-business is auto-resolved.
- **Don't skip `form_validate` if you've been mutating the form across many tool calls** — it's a free client-side check that catches "added a `picture_choice` field without `image_url` on its options".
- **Don't paste the embed snippet without `async`** on the script tag — the loader is design-only on first render; the form iframe takes over once it loads.
- **Don't author the form on a draft and then forget the publish step** — `/f/<flow_id>` will 404 until status flips to `active`.

## See also

- [recipes/design-a-form](../design-a-form/SKILL.md) — preset + token + per-question media catalog for the `theme` argument and field `media` field
- [recipes/idap-fill-from-form](../idap-fill-from-form/SKILL.md) — wire form fields to CRM columns via `crm_target` and use the 8 IDAP-anchored field types (url / country / region / postal_code / address / datetime / currency / place)
- [core-skills/forms/SKILL.md](../../core-skills/forms/SKILL.md) — full `form_*` tool catalog (20 tools)
- [examples/build-lead-gen-form.sh](../../examples/build-lead-gen-form.sh) — runnable bash version of this recipe
