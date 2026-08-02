# Forms & booking — conversational forms, lead-gen, embed, cal.com bookings

Forms and bookings are one `booking_flows` table with a `kind` discriminator; both serve from
`https://<tenant>/f/<flow_id>`. The data model, the `kind='form'` vs `kind='booking'` URL
semantics, the cal.com slot-resolver, calendar-OAuth-by-invite, and the Rule 62 visual-check
assertion all live in [`booking-model.md`](booking-model.md) — read it first. Authoring uses the
`form_*` / `booking_flow_*` tools (and `/api/v1/dashboard/booking/...` over HTTP); public submit
is `/api/v1/booking/{flow_id}/submit`.

**Read when:** building a form or booking flow, wiring conditional logic/variables, embedding a
form, cloning a form/booking template, test-submitting, locking for review, sharing a standalone
URL, or inviting staff to connect calendars.


---

## Build Form

Give a Form a real visual identity — pick a preset, override the design tokens that matter, and add per-question media (background image, side-image split, video) where it fits. Everything ships through the `theme` argument on `form_create` / `form_update` plus the `media` field on individual form fields.

### When to use

- The neutral default look is fine for a developer preview but lands flat for a client demo.
- You want one form to feel "luxury hotel" and another to feel "agency portfolio" — same widget, different surface.
- A specific question deserves its own background image (e.g. the venue photo on a wedding inquiry form).
- You're matching a brand's exact `--primary` colour, button radius, or heading font.

### The four design knobs

| Knob | Where | Granularity | Trust |
|---|---|---|---|
| **Preset** | `theme.preset` | Form-wide | 6 author-owned bundles; trusted |
| **Token overrides** | `theme.tokens["--<name>"]` | Form-wide; layered on top of the preset | Sanitised — unknown keys + unsafe values dropped |
| **Per-question media** | `field.media` | Per field; coexists with theme | URL + position + opacity only |
| **Theme aliases** | `theme.tokens.primary_color` etc. | Same as tokens; convenience for non-CSS names | Maps to canonical `--<name>` keys |

The renderer applies them in that order: preset first, then `tokens` overrides, then media on the active question. Mobile breakpoints (≤ 768px) collapse left/right splits to stacked.

### The 6 bundled presets

Choose a preset by the *feeling* you want, not by the colour. Tokens always win on top.

| Slug | Tone | What it does |
|---|---|---|
| **`card-light`** | Default neutral | Light blue primary, 8px button radius, contained 640px card, light shadow. Safe choice for SaaS / B2B. |
| **`fullscreen-dark`** | Apple-product reveal | Black/white palette, pill buttons (radius 999px), 880px wide, 2.25rem headings, 2rem field-gap. Conversational pace. |
| **`conversational-left`** | Typeform classic | Green accent, underlined inputs (radius 0, transparent bg), 560px column, 1.75rem field-gap. Reads like a chat. |
| **`form-on-image`** | Editorial / luxury | Indigo-to-violet linear-gradient background, glassy translucent inputs (`rgba(255,255,255,0.10)`), gold (`#facc15`) primary, 720px wide. |
| **`minimal-print`** | Magazine / law-firm | All-black `--primary`, serif heading font (`ui-serif, Georgia, …`), zero shadows, square corners (`--input-radius: 0`). |
| **`agency-bold`** | Bright agency | Pink (`#db2777`) primary, violet accent, pill buttons, soft pink shadow. Pairs well with playful copy. |

```
form_create({
  ...,
  theme: { preset: "fullscreen-dark" }
})
```

Pass `theme.preset` alone and you get the bundle straight. The renderer applies the preset's ~15 token overrides on top of the neutral defaults; everything else (typography scale, spacing, transitions) stays at the baseline.

### Token overrides — the 15 you'll reach for most

Every token below accepts a plain CSS value (length / colour / font-stack / shadow). All custom property names start with `--` and are written kebab-case. The renderer drops **unknown keys** and **unsafe values** (`url(...)` from end-user input, `expression()`, `javascript:`) silently — see [Sanitisation](#sanitisation) below.

#### Colour

| Token | What it controls | Example |
|---|---|---|
| `--primary` | Buttons, progress fill, focused borders | `"#1f6feb"` |
| `--primary-contrast` | Text on top of `--primary` | `"#ffffff"` |
| `--bg` | Page background | `"#fafaf9"` |
| `--surface` | Card / input background | `"#ffffff"` |
| `--text` | Body text colour | `"#1f2328"` |
| `--accent` | Secondary highlight | `"#8957e5"` |

#### Type

| Token | What it controls | Example |
|---|---|---|
| `--font-body` | Body text font stack | `'"Inter", system-ui, sans-serif'` |
| `--font-heading` | Question + screen headings | `'ui-serif, Georgia, serif'` |
| `--font-size-heading` | Heading size | `"2rem"` |
| `--font-size-label` | Question-label size | `"1.25rem"` |

#### Shape

| Token | What it controls | Example |
|---|---|---|
| `--button-radius` | CTA corner radius — `0` = square, `8px` = rounded, `999px` = pill | `"999px"` |
| `--input-radius` | Input field corner radius | `"0"` (underlined) |
| `--layout-max-width` | Max width of the form column | `"720px"` |
| `--field-gap` | Vertical rhythm between screens | `"1.75rem"` |
| `--bg-overlay-color` | Tint over `--bg-image` | `"rgba(0, 0, 0, 0.4)"` |

#### Aliases (handy when you're translating from a brand guideline)

| Alias | Canonical | Note |
|---|---|---|
| `background` / `background_color` / `bg_color` | `--bg` | |
| `foreground` / `foreground_color` | `--text` | |
| `danger` / `danger_color` | `--error` | |
| `font` / `font_family` / `body_font` | `--font-body` | |
| `heading_font` | `--font-heading` | |
| `radius` / `border_radius` | `--radius-md` | |
| `shadow` | `--shadow-md` | |
| `primary_color` | `--primary` | Auto-derived from `<name>_color → --<name>` |
| `neutral_500` | `--neutral-500` | Auto-derived from snake_case → kebab-case |

```
theme: {
  preset: "minimal-print",
  tokens: {
    primary_color: "#0f172a",                           // alias → --primary
    "--font-heading": '"Playfair Display", serif',      // canonical
    "--button-radius": "0",                             // square buttons
    "--layout-max-width": "560px"
  }
}
```

### Per-question media (`field.media`)

Each form field can carry its own background / side / top image or video. Stays scoped to that question; the next screen reverts to the form-wide theme.

```
form_add_field({
  flow_id: "<flow_id>",
  field: {
    id: "venue_photo_q",
    type: "select",
    label: "Which ballroom did you have in mind?",
    options: [
      { label: "Grand", value: "grand" },
      { label: "Garden", value: "garden" },
      { label: "Rooftop", value: "rooftop" }
    ],
    media: {
      url:      "https://media.spideriq.ai/<tenant>/venues/ballroom-grand.jpg",
      type:     "image",
      position: "background",
      opacity:  0.45
    }
  }
})
```

#### Media schema

| Field | Type | Notes |
|---|---|---|
| `url` | string (1–2048 chars) | HTTPS URL. Origin must be reachable from the public renderer. |
| `type` | `"image"` \| `"video"` | Video uses `<video autoplay muted playsinline loop>`. |
| `position` | `"background"` \| `"left"` \| `"right"` \| `"top"` | See positions below. |
| `opacity` | `0.0` – `1.0` | **Only honoured for `position: "background"`** — used as the `--media-overlay-opacity` for that screen. Ignored on left/right/top. |
| `poster_url` | string (1–2048 chars) | Still-image fallback for `type: "video"` when autoplay is blocked or the user is on a data-saver connection. Ignored for `type: "image"`. |

Forbidden on `statement` fields backend-side (they keep their existing `attachment_url`).

#### The 4 positions

| Position | Layout | When it works best |
|---|---|---|
| **`background`** | Full-screen behind input + question | Atmospheric — single mood image / video. Pair with `opacity: 0.3 – 0.55` so the input stays legible. |
| **`left`** | 50/50 split, media left + input right | Catalogue or showcase — product shot next to "Which size?". Collapses to stacked at ≤ 768px (media on top). |
| **`right`** | 50/50 split, input left + media right | Same as `left`, mirrored. Good for forms read in right-to-left languages. |
| **`top`** | Stacked, media above input | Header-style hero per question. Works on all viewport widths without collapse. |

#### Mobile collapse

`left` and `right` collapse to stacked at viewport width ≤ 768px (media renders above the input). `background` and `top` are responsive at every breakpoint. The renderer handles this automatically — no separate mobile theme needed.

#### Video tips

```
media: {
  url:        "https://media.spideriq.ai/<tenant>/loops/coffee-pour.mp4",
  type:       "video",
  position:   "background",
  opacity:    0.4,
  poster_url: "https://media.spideriq.ai/<tenant>/loops/coffee-pour.jpg"
}
```

- Always supply a `poster_url`. Mobile Safari, Chrome data-saver, and low-power mode all block autoplay; the poster keeps the screen from being blank.
- Loops ≤ 8 seconds, ≤ 2 MB encoded. The renderer doesn't preload more than the current screen.
- For paid storage discipline, host videos on the SpiderMedia CDN (`media.spideriq.ai/<tenant>/...`) — same-origin caching keeps the watch budget tight.

### Sanitisation

The renderer is permissive with shape and strict with values:

- Unknown token keys (e.g. `"--made-up"` or `theme: { tokens: { random_thing: "x" } }`) — silently dropped.
- Token values longer than 256 chars — rejected.
- Token values matching `url(` / `expression(` / `javascript:` / `</script` — rejected. Preset-supplied `linear-gradient(...)` values for `--bg-image` bypass this (preset tokens are TRUSTED); end-user-supplied `--bg-image` is restricted to `none` / `linear-gradient(...)` / plain colour values.
- Preset slugs you don't recognise are forwarded as-is (forward-compat with renderer builds that add new presets); the renderer drops slugs it can't resolve.

This means you can paste a brand guideline straight into `theme.tokens` and the renderer keeps what it understands and discards the rest, without breaking the form.

### Common patterns

#### Luxury hotel feel

```
theme: {
  preset: "fullscreen-dark",
  tokens: {
    "--font-heading": '"Playfair Display", "Cormorant Garamond", serif',
    "--primary":      "#c9a86b",          // brushed gold
    "--bg":           "#0f0d0c"
  }
}
```

Pair with `media.position: "background"` on the first question (full-bleed venue photo, `opacity: 0.35`) and stay on neutral fields after.

#### Boutique agency pitch form

```
theme: {
  preset: "agency-bold",
  tokens: {
    "--primary":         "#ec4899",
    "--accent":          "#a855f7",
    "--button-radius":   "999px",
    "--font-heading":    '"Space Grotesk", system-ui, sans-serif',
    "--layout-max-width": "560px"
  }
}
```

Use `position: "left"` media on the "Which service are you interested in?" question with a portfolio shot.

#### Legal intake / serious tone

```
theme: {
  preset: "minimal-print",
  tokens: {
    "--font-heading": 'ui-serif, "Times New Roman", serif',
    "--primary":      "#1c1917",
    "--button-radius": "0"
  }
}
```

No media. The serif heading + zero corner radius + monochrome palette do the work.

#### Conversational survey (Typeform-feel)

```
theme: {
  preset: "conversational-left",
  tokens: {
    "--primary":     "#16a34a",
    "--accent":      "#16a34a",
    "--field-gap":   "2.5rem"
  }
}
```

Optionally `position: "right"` media on a couple of mid-survey questions (product shot, screenshot) to keep visual rhythm.

### End-to-end recipe

```
# 1. Create the form with a preset + a couple of overrides
form_create({
  name: "Wedding inquiry",
  fields: [
    { id: "name",    type: "text",  label: "Your name",     required: true },
    { id: "email",   type: "email", label: "Email address", required: true }
  ],
  theme: {
    preset: "fullscreen-dark",
    tokens: {
      "--primary":      "#c9a86b",
      "--font-heading": '"Playfair Display", serif',
      "--layout-padding-y": "4rem"
    }
  }
})

# 2. Add a venue-picker with its own background image
form_add_field({
  flow_id: "<flow_id>",
  field: {
    id: "venue",
    type: "select",
    label: "Where would you like to celebrate?",
    options: [
      { label: "Grand ballroom",  value: "grand" },
      { label: "Garden pavilion", value: "garden" },
      { label: "Rooftop terrace", value: "rooftop" }
    ],
    media: {
      url:      "https://media.spideriq.ai/<tenant>/venues/grand-ballroom.jpg",
      type:     "image",
      position: "background",
      opacity:  0.45
    }
  }
})

# 3. Reshape later if needed — overrides are mergeable
form_update({
  flow_id: "<flow_id>",
  patch: {
    flow: {
      theme: {
        preset: "fullscreen-dark",
        tokens: { "--primary": "#a8895a" }      // tone down the gold
      }
    }
  }
})

# 4. Preview
form_preview_url({ flow_id: "<flow_id>" })
# → /f/<flow_id>
```

### Anti-patterns

- **Don't paste a multi-line CSS string into `theme.tokens`** — values are capped at 256 chars and matched against the unsafe-value regex. One key, one short value.
- **Don't rely on `opacity` for `position: "left" | "right" | "top"`** — the renderer ignores it. For split layouts, dim the image at source.
- **Don't ship a video without `poster_url`** — autoplay-blocked viewers see a black box.
- **Don't tune the preset and then completely override it** — if you find yourself overriding 10+ tokens of a preset, you probably want a different preset. Browse the table above first.
- **Don't use `--bg-image` directly with `url(...)` from user input** — sanitisation rejects it. Either use one of the gradient-based presets (`form-on-image`) or set the image via `field.media` on the first question with `position: "background"`.

### See also

- [recipes/build-lead-gen-form](../SKILL.md) — end-to-end form pipeline (this recipe is what plugs into the `theme` argument there)
- [recipes/idap-fill-from-form](../SKILL.md) — IDAP-anchored field types + `crm_target`
- [core-skills/forms/SKILL.md](../SKILL.md) — full `form_*` tool catalog
- examples/design-a-form.sh — bash version of the wedding-inquiry example


---

## Build Lead Gen Form

Ship a multi-step lead-gen Form end-to-end — author the fields, give it a theme, publish, and embed on a SpiderPublish page (or any third-party site) in under ten tool calls.

### When to use

- A tenant needs a multi-step lead-capture form (email + company + team size, plus a contact-method picker).
- You're replacing a Typeform / Tally form and want one MCP-driven pipeline that lives next to the rest of the site.
- The form needs to ship on the tenant's own domain at `/f/<flow_id>` AND embed on an external site (Webflow, Shopify, plain HTML).
- You want the form themed (preset + token overrides) at create time so the first publish already matches the brand.

If you only need a single email field at the bottom of a page → use a `form` block on a page instead. Forms are for multi-step / conditional flows.

### Pre-flight (one-time, per session)

The `form_*` tools are in `@spideriq/mcp@1.13.0+`, **not** in `@spideriq/mcp-publish`. If your `.mcp.json` points at `mcp-publish`, you have two options before continuing:

1. Switch the existing entry to `@spideriq/mcp@1.13.0` — gets you the full surface (publish + booking + forms + mail + leads + gate + admin).
2. Add a second MCP server entry pointing at `@spideriq/mcp` and only enable it in form-authoring sessions.

See [core-skills/forms/SKILL.md → MCP package caveat](../SKILL.md) for the rationale.

### The 6-call path

```
1. form_create        — name + initial fields + theme         → flow_id
2. form_add_field     — append the "contact method" picker
3. form_add_field     — append a long_text "anything else?"
4. form_validate      — local structural check (no API call)
5. form_publish       — draft → active (2-phase confirm)
6. form_get_embed_snippet — copy-paste HTML for any page
```

Step 1 alone is enough for a minimal three-field form (email + company + team size). Steps 2–3 add depth; 4 is a free sanity check; 5 flips the form live; 6 hands you the embed snippet for any third-party page.

#### 1. Create the form

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
- **`type`** — see the [full list of field types](../SKILL.md) (15+ including `text`, `email`, `phone`, `number`, `select`, `checkbox`, `picture_choice`, `rating`, `nps`, `opinion_scale`, `date`, `file_upload`, plus the W13.3 IDAP-anchored types — see [recipes/idap-fill-from-form](../SKILL.md)).
- **`theme`** — optional, but ships better than the neutral fallback. See [recipes/design-a-form](../SKILL.md) for the full preset + token catalog.

#### 2 + 3. Add follow-up fields

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

#### 4. Validate (free)

```
form_validate({ flow: <full flow blob from form_get> })
// → { errors: [], warnings: [] }
```

`form_validate` runs entirely client-side against the locked schema (14 rule classes: shape, kind/schema_version, field-type invariants, hidden-field key uniqueness, logic rule cross-references, …). No API call. Useful as a pre-publish sanity check, especially after a long authoring session where the agent may have added a field whose options[] shape doesn't match its type.

#### 5. Publish (2-phase confirm)

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

#### 6. Get the embed snippet

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

### Embed on a SpiderPublish page

The cleanest way to drop the form on a tenant page is the `{% form %}` Liquid tag — it inlines the form server-side instead of loading the embed iframe. See examples/build-lead-gen-form.sh for the end-to-end shell pipeline (form_create → form_publish → page block referencing the flow_id).

### Embed on an external site

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

### Hidden fields (URL-param capture)

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

### Anti-patterns

- **Don't pass `business_id` on a form-kind `form_create` call** — backend `422`s. The sentinel-business is auto-resolved.
- **Don't skip `form_validate` if you've been mutating the form across many tool calls** — it's a free client-side check that catches "added a `picture_choice` field without `image_url` on its options".
- **Don't paste the embed snippet without `async`** on the script tag — the loader is design-only on first render; the form iframe takes over once it loads.
- **Don't author the form on a draft and then forget the publish step** — `/f/<flow_id>` will 404 until status flips to `active`.

### See also

- [recipes/design-a-form](../SKILL.md) — preset + token + per-question media catalog for the `theme` argument and field `media` field
- [recipes/idap-fill-from-form](../SKILL.md) — wire form fields to CRM columns via `crm_target` and use the 8 IDAP-anchored field types (url / country / region / postal_code / address / datetime / currency / place)
- [core-skills/forms/SKILL.md](../SKILL.md) — full `form_*` tool catalog (20 tools)
- examples/build-lead-gen-form.sh — runnable bash version of this recipe


---

## Add Logic And Variables

Add conditional logic + declared variables to a `kind='form'` flow — branch on answers, jump to specific questions, compute values, capture URL params. The "if X, then Y" surface.

### When to use

- A form needs to skip questions based on prior answers (e.g. "If team_size = solo, skip the 'How many seats?' question").
- You want to send respondents to different thank-you screens based on their answers.
- You want to capture URL params (`?utm_source=...`) as hidden fields.
- You want to compute derived values (e.g. `total = qty * price`) and surface them in subsequent questions.

For form authoring fundamentals (theme, fields) → [`build-form.md`](forms-booking.md#build-form). For an end-to-end pipeline (create → publish → embed) → [`build-lead-gen-form.md`](forms-booking.md#build-lead-gen-form).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **A draft form exists.** Logic and variables can be added on a draft OR before publish. Adding logic to an already-published form re-validates at publish time.
3. **You know your field IDs.** Logic rules reference fields by `id`, not by label. Inventory with `form_get({ flow_id })` first.

### The three constructs

| Construct | What | Tool |
|---|---|---|
| **Logic rule** | `when X then Y` — branch based on answers | `form_add_logic_rule` |
| **Variable** | Declared value (string/number/bool) settable from logic | `form_declare_variable` |
| **Hidden field** | URL-param-capturable value persisted on the lead row | `form_add_hidden_field` |

These compose: a logic rule can read a hidden field, set a variable, and jump to a target step.

### Logic rules — branching

#### Shape

```
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "solo" },
    then: { type: "jump_to", target: "step_thankyou" }
  }
})
```

Each rule has a `when` (the condition) and a `then` (the action). Rules evaluate in declaration order — the first matching rule fires.

#### The `when` operators

| Op | Meaning | Field types it works on |
|---|---|---|
| `eq` | Equals (case-insensitive for strings) | All |
| `neq` | Not equals | All |
| `gt` / `gte` | Greater than / ≥ | number, opinion_scale, rating, nps |
| `lt` / `lte` | Less than / ≤ | Same |
| `in` | Value in array | select, picture_choice, checkbox |
| `not_in` | Value not in array | Same |
| `contains` | Substring match | text, textarea, email |
| `is_empty` / `is_filled` | Field has/hasn't been answered | All |

Compound conditions via `all` (AND) or `any` (OR):

```
when: {
  all: [
    { field: "team_size", op: "in", value: ["small", "medium"] },
    { field: "company_size", op: "gte", value: 10 }
  ]
}
```

#### The `then` actions

| Action | What it does |
|---|---|
| `jump_to: { target: "<step_id>" }` | Skip to a specific step (forward only — no backward jumps) |
| `skip_to_thankyou: { screen_id: "<thx_id>" }` | Jump to a specific thank-you screen (different screens for different paths) |
| `set_variable: { name: "<var>", value: ... }` | Assign a variable that subsequent questions can recall via `{{variable:name}}` |
| `set_hidden: { key: "<key>", value: ... }` | Set a hidden field (alternative to URL-param capture) |
| `end` | Submit immediately, skipping remaining steps |

#### Example — multi-path form

```
# Rule 1: enterprise leads → enterprise thank-you + sales handoff
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "set_variable", name: "lead_tier", value: "enterprise" }
  }
})

# Rule 2: also jump enterprise to a specific thank-you screen
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "skip_to_thankyou", screen_id: "thx_enterprise" }
  }
})

# Rule 3: solo leads → self-serve thank-you
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "solo" },
    then: { type: "skip_to_thankyou", screen_id: "thx_selfserve" }
  }
})
```

The result: respondents picking `large` get the enterprise thank-you with sales contact info; respondents picking `solo` get the self-serve onboarding link.

### Variables — declared, typed, default-valued

Variables are session-scoped — they live for the duration of one form submission. Use them to compute derived values that subsequent questions / thank-you screens can reference.

```
form_declare_variable({
  flow_id: "<flow_id>",
  variable: {
    name: "estimated_total",
    type: "number",
    default: 0
  }
})

# Set it via a logic rule (after the relevant fields are answered)
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "qty", op: "is_filled" },
    then: {
      type: "set_variable",
      name: "estimated_total",
      value: { expression: "{{field:qty}} * {{field:price_per_unit}}" }
    }
  }
})
```

The renderer's recall-token syntax: `{{field:<field_id>}}` for answer values, `{{variable:<name>}}` for declared variables, `{{hidden:<key>}}` for hidden fields.

#### Variable types

| Type | Notes |
|---|---|
| `string` | Default `""`. Use for derived text (concatenated names, etc.). |
| `number` | Default `0`. Supports `+`, `-`, `*`, `/` in `expression`. |
| `boolean` | Default `false`. Toggle for conditional rendering. |

### Hidden fields — URL-param capture

Hidden fields are URL-querystring-captured at form load. Only DECLARED keys are sourced; arbitrary query params are stripped (security model).

```
form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "utm_source", label: "UTM source" }
})

form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "ref", label: "Referral code", default_value: "organic" }
})
```

When the visitor lands at `https://<tenant>/f/<flow_id>?utm_source=instagram&ref=ABC123`, both values persist on the lead row. If `ref` isn't in the URL, `default_value: "organic"` is used.

Hidden fields ALSO show up in `when` conditions, so you can branch on referral source:

```
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "ref", op: "eq", value: "ABC123" },
    then: { type: "set_variable", name: "discount_code", value: "VIP-15" }
  }
})
```

`when.field` accepts BOTH visible field IDs AND hidden field keys.

### Validate before publish

```
form_validate_logic({ flow_id: "<flow_id>" })
// → { valid: true, errors: [], warnings: [...] }
```

The server-side cross-validation runs 14 rule classes:

| Class | Catches |
|---|---|
| Field-reference | Rule references a `field` that doesn't exist in the flow |
| Step-reference | `jump_to.target` references a step that doesn't exist |
| Screen-reference | `skip_to_thankyou.screen_id` references a thank-you screen that doesn't exist |
| Variable-reference | `set_variable.name` references an undeclared variable |
| Operator-domain | Operator (`gt`, `contains`, etc.) used on incompatible field type |
| Forward-jump-only | `jump_to.target` points backward (loops) |
| Hidden-key-uniqueness | Duplicate `hidden_field.key` |
| Variable-default-type | Variable `default` type doesn't match declared `type` |

Run after EVERY logic mutation. The local `form_validate({ flow })` runs a subset (structural checks); `form_validate_logic` is the full cross-validation.

### Remove logic

```
form_remove_logic({
  flow_id: "<flow_id>",
  rule_id: "rule_..."           # from form_get's flow.logic[].id
})
```

Rules are indexed by `id`. Get them via `form_get` and look at `flow.logic[]`. Removal is immediate; no dry_run gate.

### End-to-end example — lead-gen with branching thank-you screens

```
# 1. Declare variables for the tier classification
form_declare_variable({ flow_id, variable: { name: "lead_tier", type: "string", default: "unknown" } })

# 2. Add hidden fields for attribution
form_add_hidden_field({ flow_id, hidden_field: { key: "utm_source", label: "UTM source" } })
form_add_hidden_field({ flow_id, hidden_field: { key: "campaign",   label: "Campaign" } })

# 3. Add branching logic
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "eq", value: "solo" },
    then: { type: "set_variable", name: "lead_tier", value: "solo" }
  }
})
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "in", value: ["small", "medium"] },
    then: { type: "set_variable", name: "lead_tier", value: "smb" }
  }
})
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "set_variable", name: "lead_tier", value: "enterprise" }
  }
})

# 4. Branch to different thank-you screens based on tier
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "skip_to_thankyou", screen_id: "thx_enterprise" }
  }
})

# 5. Validate
form_validate_logic({ flow_id })
# → { valid: true, errors: [], warnings: [] }

# 6. Publish
form_publish({ flow_id })   # safe-default dry_run=true
form_publish({ flow_id, confirm_token })
```

The lead row now carries: `team_size`, `lead_tier`, `utm_source`, `campaign`. Different visitors see different thank-you screens. Downstream (CRM, email) can branch on `lead_tier` for routing.

### Recall tokens — referencing values in field labels + thank-you screens

Once you've declared variables / hidden fields, reference them in subsequent field labels OR thank-you screen text:

```
# Field label that uses a previous answer
{ id: "confirm_name", type: "text", label: "Just to confirm — your name is {{field:name}}, correct?" }

# Thank-you screen that uses a variable
{
  id: "thx_enterprise",
  title: "Welcome, {{field:name}} — enterprise tier",
  description: "We'll be in touch via {{field:email}} within 24h. Tier: {{variable:lead_tier}}.",
  button_mode: "redirect",
  redirect_url: "https://calendly.com/sales/enterprise"
}
```

Tokens are interpolated by the renderer at submit time / render time.

### Anti-patterns

1. **Backward jumps (`jump_to.target` pointing to a step before the current one).** Validator rejects — would cause infinite loops. Use `set_variable` + a forward jump to a different branch.
2. **Logic on a hidden_field key you never declared.** `when.field: "utm_source"` without `form_add_hidden_field({key: "utm_source"})` → validator says `field not found`. Declare first.
3. **`set_variable` with an undeclared variable name.** Validator says `variable not declared`. Use `form_declare_variable` first.
4. **Operator-domain mismatch (`gt` on a `select` field, `contains` on a `number`).** Validator catches; pick the right operator for the field type.
5. **Adding 20+ logic rules.** Hard to reason about; debugging which rule fires becomes a maintenance burden. Refactor: use fewer rules that set variables (`lead_tier`), then a small number of variable-based jumps.
6. **Forgetting `form_validate_logic` after every mutation.** Each rule add is a chance to introduce a cross-reference bug. Re-run validation as a free safety net.

### See also

- [`build-form.md`](forms-booking.md#build-form) — theme + fields (foundation)
- [`build-lead-gen-form.md`](forms-booking.md#build-lead-gen-form) — end-to-end pipeline (logic plugs in at step 4)
- [`clone-form-template.md`](forms-booking.md#clone-form-template) — start from a template that may already have logic
- [`embed-form.md`](forms-booking.md#embed-form) — embed the logic-enabled form
- [`../reference/booking-model.md`](booking-model.md) — `kind='form'` flow shape (`flow.logic[]`, `flow.variables{}`)
- [`../reference/tool-surface.md`](tool-surface.md) — `form_*` tool catalog
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Embed Form

Embed a form (or booking) on any page — inline iframe, popup modal, or standalone URL. One MCP call returns the copy-paste snippet. Works on SpiderPublish pages AND external sites (Webflow, Shopify, WordPress, Framer, plain HTML).

### When to use

- A tenant wants the form to live inside one of their pages (`/contact`, `/get-started`) — use **inline**.
- A tenant has a CTA button that should open the form in a modal — use **popup**.
- A tenant wants a standalone URL to share via QR code, social bio, or paste into an email — use **standalone** (`/f/<flow_id>`).

All three work for both `kind='form'` AND `kind='booking'`. URL is always `/f/<flow_id>` — never `/book/<id>` for forms. This is the W13-incident-codified rule.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Form exists + is published.** `status: active`. The embed snippet generates regardless of status (pure string composition), but the runtime needs `active` to render. Check with `form_get({flow_id})`.
3. **MCP server with `form_*`.** `@spideriq/mcp` kitchen-sink (134+) — see [`../reference/tool-surface.md`](tool-surface.md).

### The 1-call path (standalone URL)

```
form_preview_url({ flow_id: "flow_..." })
// → {
//     public_url: "https://spideriq.ai/f/flow_...",
//     dashboard_preview_path: "/dashboard/booking/flows/flow_.../preview",
//     note: "public_url is the standalone /f/{flow_id} page..."
//   }
```

`public_url` is the canonical share URL. It serves a minimal-chrome standalone page (no marketing wrapping). The host is `apiUrl` (the workspace's configured API host — usually `spideriq.ai`), **NOT** the tenant's primary verified custom domain.

If you want the URL on the tenant's verified custom domain (e.g. `demo.spideriq.ai/f/<id>`):

1. Call `content_list_domains()`, pick the primary.
2. Compose `https://<primary-domain>/f/<flow_id>` yourself.
3. Verify the tenant has deployed (`content_deploy_status` shows `live`) — otherwise the custom domain doesn't route to the form yet.

Why `form_preview_url` doesn't auto-pick the tenant's custom domain: it's pure string composition, no API round-trip to fetch domain config. (S4-B5 honesty fix 2026-05-20.) See [`../reference/booking-model.md`](booking-model.md#why-form_preview_url-returns-a-spideriqaif-url-not-the-tenants-custom-domain).

### The 1-call path (inline / popup snippet)

```
form_get_embed_snippet({
  flow_id: "flow_...",
  mode:    "inline"            # or "popup"
})
// → {
//     flow_id: "flow_...",
//     mode: "inline",
//     snippet: "<div data-spiderflow-flow=\"flow_...\" data-spiderflow-mode=\"inline\"></div>\n<script src=\"https://embed.spideriq.ai/v1/loader.js\" async></script>",
//     loader_url: "https://embed.spideriq.ai/v1/loader.js"
//   }
```

#### Inline embed

```html
<div data-spiderflow-flow="flow_..." data-spiderflow-mode="inline"></div>
<script src="https://embed.spideriq.ai/v1/loader.js" async></script>
```

What it does:
- Loader auto-discovers `<div data-spiderflow-flow="...">` on page load.
- Replaces the div with an `<iframe>` pointing at `forms.spideriq.ai/render/<flow_id>?embed=inline`.
- iframe inherits the parent page's width; auto-resizes its height as the form progresses through screens.

Use when: the form IS the page content (or a major section), not a hover-out modal.

#### Popup embed

```
form_get_embed_snippet({
  flow_id: "flow_...",
  mode: "popup",
  button_text: "Start your free trial"
})
// → {
//     snippet: "<button data-spiderflow-flow=\"flow_...\" data-spiderflow-mode=\"popup\">Start your free trial</button>\n<script src=\"https://embed.spideriq.ai/v1/loader.js\" async></script>",
//     ...
//   }
```

```html
<button data-spiderflow-flow="flow_..." data-spiderflow-mode="popup">Start your free trial</button>
<script src="https://embed.spideriq.ai/v1/loader.js" async></script>
```

What it does:
- Renders the `<button>` as-is (you can style it with any CSS).
- On click, loader opens a modal `<iframe>` overlay; lazy-loaded (iframe doesn't exist until click).
- Modal has a close button (top-right); click-outside-to-close.

Use when: the form is a secondary action (CTA on a marketing page, not the page's main content).

#### Prefill from URL params

If you want the embedded form to capture URL params (`?utm_source=twitter` → hidden field):

```html
<div
  data-spiderflow-flow="flow_..."
  data-spiderflow-mode="inline"
  data-prefill-utm_source="twitter"
  data-prefill-ref="ABC123"
></div>
<script src="https://embed.spideriq.ai/v1/loader.js" async></script>
```

The loader reads `data-prefill-<key>` attributes and passes them as hidden field defaults. The form's `hidden_fields[]` declarations (via `form_add_hidden_field`) determine which keys actually persist — arbitrary `data-prefill-*` not in the hidden_fields whitelist are dropped.

You can also let the host page read URL params and inject them dynamically:

```html
<script>
  const params = new URLSearchParams(window.location.search);
  document.write(`
    <div data-spiderflow-flow="flow_..." data-spiderflow-mode="inline"
         data-prefill-utm_source="${params.get('utm_source') || ''}"></div>
    <script src="https://embed.spideriq.ai/v1/loader.js" async><\/script>
  `);
</script>
```

### Embed inside a SpiderPublish page (the cleanest way)

The dashboard supports a native form block — pick the form from a dropdown, and the renderer inlines it server-side instead of via iframe:

```
content_update_page({
  page_id: "<page-uuid>",
  blocks: [
    ...,
    {
      id: "blk_form",
      type: "component",
      component_slug: "form",
      data: { flow_id: "flow_..." }
    }
  ]
})
```

The canonical native-block component slug is **`"form"`** (literal four-character string). The server-side check is at [`app/services/form_submission_service.py:256`](https://github.com/SpiderIQ/SpiderIQ/blob/master/app/services/form_submission_service.py#L256) — `if block.get("component_slug") == "form"`. The rendered Web Component tag is `<spideriq-form>` (DOM-side), but the BLOCK-side slug stored in `content_pages.blocks[]` is `"form"`. Don't confuse them.

Inline server-side render avoids the iframe round-trip + CSP boundary. Use this when the form lives on a SpiderPublish-served page. The `form_get_embed_snippet` iframe path is for external (non-SpiderPublish) host pages.

### On external sites (Webflow, Shopify, WordPress, etc.)

The snippet from `form_get_embed_snippet` drops anywhere. The loader bundle is ~3 KB gzip, served from a single CDN URL (`embed.spideriq.ai/v1/loader.js`).

| Host | Where to paste |
|---|---|
| **Webflow** | Add an "Embed" element where you want the form. Paste the snippet. |
| **Shopify** | Theme → Customize → add a "Custom Liquid" section. Paste. |
| **WordPress** | Use the "Custom HTML" block in Gutenberg. Paste. |
| **Framer** | Add an "Embed" component. Paste. |
| **Plain HTML** | Paste anywhere in `<body>`. |

#### Cross-origin postMessage protocol

The loader sends `postMessage` events from the iframe to the parent for resize, ready, complete:

```javascript
window.addEventListener('message', (event) => {
  if (event.origin !== 'https://forms.spideriq.ai') return;   // origin guard
  if (event.data?.type === 'spiderflow:ready')    { /* form mounted */ }
  if (event.data?.type === 'spiderflow:resize')   { /* event.data.height */ }
  if (event.data?.type === 'spiderflow:complete') { /* form submitted */ }
  if (event.data?.type === 'spiderflow:error')    { /* event.data.message */ }
  if (event.data?.type === 'spiderflow:close')    { /* user closed popup */ }
});
```

For multi-form pages, the loader does origin validation on every `postMessage` (`event.source === iframe.contentWindow && event.origin === forms.spideriq.ai`) — two embeds on the same page never cross-talk.

Use the `spiderflow:complete` event to trigger analytics (`gtag`, `posthog`, etc.) without exposing the form internals.

### Verify the embed works

After dropping the snippet on a host page:

```
content_visual_check({
  page_url: "https://<host-page-url>",
  viewport: "desktop"
})
```

**Assert on `dom.shadow_hosts.includes("spideriq-form")`** — the loader mounts a `<spideriq-form>` custom element in the parent DOM (it's a Shadow DOM host). DO NOT assert on `body_text_preview` for the form labels — the iframe body is **opaque** to the parent page. (See [`../reference/booking-model.md`](booking-model.md#visual-check) — Rule 62.)

If `dom.shadow_hosts` doesn't include `spideriq-form`:
- Did the loader script load? Check `console_errors` — `script error: <loader>` means the CSP blocked it. Whitelist `embed.spideriq.ai` in the host page's CSP.
- Is the `data-spiderflow-flow` attribute spelled right? Typo → loader can't find the element.
- Is the form `status: active`? Draft forms 404 in the iframe.

### Update / re-embed

The snippet is bound to `flow_id`. If you change the form's structure (`form_update`, `form_add_field`), no re-embed needed — the loader fetches the latest flow JSON on every render. The snippet stays valid until you delete the flow.

If you replace the form with a new `flow_id`: re-call `form_get_embed_snippet({flow_id: <new>})` and update the host page's snippet.

### Anti-patterns

1. **Composing `/book/<flow_id>` for a `kind='form'`.** Use `/f/<flow_id>` for everything. The W13 incident's exact failure shape. Always call `form_preview_url` / `form_get_embed_snippet`; never string-template URLs. Rule 62.
2. **Asserting on `body_text_preview` after visual-check.** Cross-origin iframe = opaque. Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.
3. **Embedding a draft form.** The snippet renders but the iframe 404s. Always `form_publish` first.
4. **Pasting the snippet without `async` on the script tag.** The loader is design-only on first render; the form iframe takes over once it loads. Without `async`, the parent page blocks on loader fetch.
5. **Inline-embedding on a page with strict CSP that doesn't whitelist `embed.spideriq.ai` / `forms.spideriq.ai`.** Loader fails silently in some CSP configs (`script-src` blocks the loader; `frame-src` blocks the iframe). Test in DevTools after deploy.
6. **Using `prefill` without declaring the hidden field via `form_add_hidden_field`.** The loader passes the value, but the form drops it (only declared hidden fields persist). Declare hidden fields BEFORE embed.

### See also

- [`build-form.md`](forms-booking.md#build-form) — author the form before embedding
- [`build-lead-gen-form.md`](forms-booking.md#build-lead-gen-form) — end-to-end pipeline (create + publish + embed in 6 calls)
- [`clone-form-template.md`](forms-booking.md#clone-form-template) — clone from a template; ends in `form_get_embed_snippet`
- [`clone-booking-template.md`](forms-booking.md#clone-booking-template) — same embed flow works for booking
- [`../reference/booking-model.md`](booking-model.md) — URL surface, Rule 62, W13 incident
- [`../reference/tool-surface.md`](tool-surface.md) — `form_*` tool catalog
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Form As Page Section

Embed a conversational `kind='form'` flow as a block inside a SpiderPublish page (vs. as an external-site iframe). Two paths: native page-level form components (`sys-form-*`, no `flow_id`) for simple capture, OR the `kind='form'` flow embed for full conversational + logic.

### When to use

**Path A — Native page-level form (`sys-form-*` components):**

- Simple email capture, newsletter signup, 2-step opt-in.
- You want the form rendered INLINE on the page (no iframe; same origin).
- You don't need welcome screens, conditional logic, variables, or `/f/<id>` standalone share.

**Path B — `kind='form'` flow embed:**

- You've built a multi-step conversational form (welcome → fields → logic → thank-you).
- You want the SAME form available at `/f/<flow_id>` AND inside a page.
- You need theme presets, per-question media, logic jumps, variables.

If you ONLY want the form embedded outside SpiderPublish (Webflow / Shopify) → [`embed-form.md`](forms-booking.md#embed-form). If you want the form at `/f/<flow_id>` only → just publish it; the standalone URL is auto.

### Path A — Native page-level form (3 sys-form-* options)

#### The catalog

| Slug | Use |
|---|---|
| `sys-form-newsletter-inline` | One-field email capture; rendered inline as a section |
| `sys-form-2step-optin` | Two-step (email → confirm) with cookie-based dismissal |
| `sys-form-multistep-funnel` | Multi-step page-level funnel (no /f/<id>; lives entirely in the page) |

These are part of the CRO catalog with `marketplace_category='capture'`. See [`../marketplace/browse-cro-components.md`](marketplace.md#browse-cro-components) for the full CRO surface.

#### The 3-call path

```
1. content_list_marketplace_components({ category: "capture" })
2. content_get_component_by_slug({ slug: "sys-form-2step-optin" })   # inspect props
3. page_insert_section({ page_id, component_slug, props })           # dry_run + confirm
```

#### Insert

```
page_insert_section({
  page_id:        "<page-uuid>",
  component_slug: "sys-form-2step-optin",
  props: {
    step1_headline:        "Get our weekly digest",
    step1_subheadline:     "One email per week. No spam.",
    step1_cta_label:       "Subscribe",
    step2_email_label:     "Your email",
    step2_email_placeholder: "you@company.com",
    step2_cta_label:       "Confirm",
    success_message:       "Welcome! Check your inbox.",
    webhook_url:           "https://hooks.acme.com/spideriq-newsletter",
    slug:                  "weekly-digest"
  },
  position: "after",
  anchor_block_id: "blk_hero",
  dry_run: true
})
# → { dry_run: true, preview, confirm_token }
```

`webhook_url` receives a form-encoded POST with the field values when the user submits. Without JS, the browser submits natively. With JS, `fetch()` is used and the `success_message` shows inline.

`slug` is the cookie-key suffix — lets you have multiple `sys-form-2step-optin` on different sites (or the same site with different intents) without sharing dismissal cookies.

#### When Path A is enough

- Email-only capture (newsletter).
- Single-step with light follow-up (2step opt-in).
- Linear multi-step where you don't need logic / branching (multistep-funnel).
- No requirement for the form to also be at `/f/<id>`.

### Path B — `kind='form'` flow embed inside a page

When you want one source of truth for the form (theme, fields, logic) and TWO surfaces: the page-block AND the standalone `/f/<flow_id>` URL.

The native form block component slug is **`"form"`** (literal four-character string). Confirmed at [`app/services/form_submission_service.py:256`](https://github.com/SpiderIQ/SpiderIQ/blob/master/app/services/form_submission_service.py#L256): `if block.get("component_slug") == "form"`. The rendered Web Component tag is `<spideriq-form>` (DOM-side, what `dom.shadow_hosts` reports); the block-side slug in `content_pages.blocks[]` is `"form"`. The two are different layers — slug = STORE-side identifier; `<spideriq-form>` = the SERVE-side custom-element tag the renderer emits.

#### The 4-call path

```
1. form_create_from_template / form_create   — author the kind='form' flow
2. form_publish                              — flip to status='active'
3. content_get_component_by_slug             — confirm the page-block component exists
4. page_insert_section                       — insert into the target page
```

#### Step 1-2 — author + publish the flow

See [`build-form.md`](forms-booking.md#build-form) (theme + fields) or [`clone-form-template.md`](forms-booking.md#clone-form-template) (one-shot template clone). The result: a `kind='form'` row in `booking_flows` with `status: active` and a `flow_id`.

#### Step 3 — confirm the page-block component

```
content_get_component_by_slug({ slug: "spideriq-form-embed" })   # VERIFY actual slug
// → { props_schema: { properties: { flow_id: { type: "string" }, height_px: { ... } } } }
```

The native form block accepts `flow_id` as its primary prop. The renderer reads the form's flow JSON, server-side-renders the conversational steps, AND mounts the `<spideriq-form>` Shadow DOM host for client-side interactivity (logic, jumps, variables).

#### Step 4 — insert into a page

```
page_insert_section({
  page_id:        "<page-uuid>",
  component_slug: "spideriq-form-embed",                # VERIFY slug
  props: {
    flow_id: "<flow_id from form_create>",
    height_px: 600,
    autoplay_welcome: true
  },
  position: "after",
  anchor_block_id: "blk_hero",
  dry_run: true
})
```

After publish + deploy, the page has the conversational form inline (same-origin, no cross-origin iframe). The form ALSO remains at `https://<tenant>/f/<flow_id>` as the standalone URL.

#### Step 5 — publish the page + deploy

```
content_publish_page({ page_id: "<page-uuid>" })
content_publish_page({ page_id: "<page-uuid>", confirm_token: "..." })
content_deploy_site_production({ confirm_token: "..." })
```

### Path A vs Path B — pick the right one

| Question | Path A (sys-form-*) | Path B (kind='form' embed) |
|---|---|---|
| Multi-step with conditional logic? | ❌ multistep-funnel is linear | ✅ logic + jumps |
| Welcome screens / thank-you screens? | ❌ | ✅ |
| Theme presets (card-light, fullscreen-dark, …)? | ❌ — uses the page's CSS | ✅ — six form presets |
| Per-question media (image / video)? | ❌ | ✅ |
| Same form ALSO at `/f/<flow_id>`? | ❌ — page-only | ✅ — both surfaces |
| Cross-origin iframe? | ❌ — same-origin (faster paint) | ⚠️ — Shadow DOM host server-side; conversational logic client-side |
| Form analytics / submissions in `booking_submissions`? | ❌ — webhook only | ✅ — full submission tracking |
| Setup complexity | 1 page_insert_section call | form_create → publish → page_insert_section |

**Default to Path A** for simple capture (email, newsletter). **Reach for Path B** when you need conversational shape OR same form across multiple surfaces.

### Verify

For Path A (native form):
```
content_visual_check({ page_url: "https://<tenant>/<page-slug>", viewport: "desktop" })
# `body_text_preview` should contain the form's headline literals.
# Form is server-rendered inline — visible in screenshot.
```

For Path B (`kind='form'` embed):
```
content_visual_check({ page_url: "https://<tenant>/<page-slug>", viewport: "desktop" })
# Assert on `dom.shadow_hosts.includes("spideriq-form")` (the Shadow DOM host mounted).
# DO NOT assert on `body_text_preview` for the form's field labels — Shadow DOM
# field labels are inside the shadow root and may not surface in body_text_preview.
# This is the same Rule 62 rule that applies to cross-origin iframe embeds.
```

### Submission handling

- **Path A — webhooks.** `webhook_url` on the component props receives the POST. No SpiderPublish submission storage; you handle persistence on your side.
- **Path B — full SpiderPublish submission flow.** Submits POST to `/api/v1/forms/{flow_id}/submit`, persists to `booking_submissions`, fires webhooks if configured, fires `spiderflow:complete` postMessage events (when in iframe contexts).

### Anti-patterns

1. **Path B with the wrong native-form slug.** Until the VERIFY marker resolves, confirm via `content_list_components({ category: "contact_form", include_global: true })` before composing `page_insert_section`. Don't guess.
2. **Asserting on `body_text_preview` for Path B field labels.** Shadow DOM = opaque to outer `body_text_preview`. Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.
3. **Using `sys-form-newsletter-inline` for a multi-field lead form.** It's email-only. For multi-field on a page → `sys-form-multistep-funnel` (Path A) OR `kind='form'` flow + Path B.
4. **Forgetting to publish the `kind='form'` flow before Path B insert.** The block embeds correctly but the form renders as "Form unavailable" because status is `draft`. Always `form_publish` first.
5. **Adding both Path A `sys-form-2step-optin` AND Path B `kind='form'` embed for the same email-capture intent on one page.** Visitor confusion + double-submission risk. Pick one.
6. **Treating `sys-form-multistep-funnel` as having `/f/<id>`-style URL.** It doesn't — it's a page-level multi-step component, not a `kind='form'` flow. Different surface entirely.

### See also

- [`build-form.md`](forms-booking.md#build-form) — author a `kind='form'` flow (Path B step 1)
- [`build-lead-gen-form.md`](forms-booking.md#build-lead-gen-form) — end-to-end Path B pipeline
- [`clone-form-template.md`](forms-booking.md#clone-form-template) — one-shot template clone for Path B
- [`embed-form.md`](forms-booking.md#embed-form) — embed `kind='form'` flow OUTSIDE SpiderPublish (iframe)
- [`share-form-standalone.md`](forms-booking.md#share-form-standalone) — `/f/<flow_id>` URL for QR / bio sharing
- [`../marketplace/browse-cro-components.md`](marketplace.md#browse-cro-components) — full CRO catalog including the 3 sys-form-* components
- [`../content/landing-page.md`](content.md#landing-page) — page authoring before insert
- [`../reference/booking-model.md`](booking-model.md) — `kind='form'` flow data model + Rule 62
- [`../reference/block-types.md`](block-types.md) — `type: "component"` block shape


---

## Clone Form Template

Clone a global form template into your tenant — one MCP call, one publish, you're live. Use `auto_create: true` for the one-shot path.

### When to use

- A tenant needs a standard form (contact, lead-gen, NPS survey, intake) and you want to start from a curated template instead of authoring from scratch.
- You're spinning up a new tenant and want to seed it with 3-5 baseline forms (contact-form, nps-survey, etc.).
- You want to start from a "good enough" template and then customize fields / theme / logic on top.

For a fully custom form authored field-by-field → [`build-form.md`](forms-booking.md#build-form). For booking-kind templates (cal.com integration) → [`clone-booking-template.md`](forms-booking.md#clone-booking-template).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Form tools available.** `form_*` tools live in `@spideriq/mcp` (kitchen-sink, 134+ tools), NOT in `@spideriq/mcp-publish` (the 87-tool atomic build). If your MCP entry is `mcp-publish`, switch to `mcp` for this recipe — see [`../reference/tool-surface.md`](tool-surface.md).

### The 3-call path (with `auto_create: true`)

```
1. form_list_template_categories         — see the ~20 category slugs
2. form_list_global_templates({ category }) — browse + pick the template slug
3. form_create_from_template({ slug, auto_create: true })  — clone AND materialize a draft form
```

Then `form_publish` to flip live, `form_get_embed_snippet` to embed.

#### 1. List categories

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

#### 2. Browse templates

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

#### 3. Clone with `auto_create: true` (the one-shot)

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

#### The two-step path (when you want to inspect before materializing)

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

### After cloning — publish + embed

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

For `kind='form'` flows, `title`, `length_minutes`, `team_id` on `form_publish` are accepted but **ignored** at render time (cal.com provisioning skipped). Pass `length_minutes: 1, team_id: 0, title: "any string"` OR omit them — both work. See [`../reference/booking-model.md`](booking-model.md#calcom-integration--kindbooking-only).

Once `status: active`, embed:

```
form_get_embed_snippet({ flow_id: "flow_...", mode: "inline" })
// → {
//     snippet: "<div data-spiderflow-flow=\"flow_...\" data-spiderflow-mode=\"inline\"></div>\n<script src=\"https://embed.spideriq.ai/v1/loader.js\" async></script>",
//     loader_url: "https://embed.spideriq.ai/v1/loader.js"
//   }
```

Drop into any page. See [`embed-form.md`](forms-booking.md#embed-form) for inline + popup + standalone embed paths.

### Customize after clone

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

See [`build-form.md`](forms-booking.md#build-form) for the full field-authoring catalog and [`build-lead-gen-form.md`](forms-booking.md#build-lead-gen-form) for end-to-end customization.

### Verify

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

### Anti-patterns

1. **Cloning a `kind='booking'` template via `form_create_from_template`.** The tool 422s with `Template "X" is kind="booking", not "form". Use booking_flow_clone_template for booking-kind templates.` See [`clone-booking-template.md`](forms-booking.md#clone-booking-template).
2. **Forgetting to publish.** `auto_create: true` gives you a draft form — `/f/<flow_id>` returns 404 until `form_publish` flips status to `active`.
3. **Composing `/book/<flow_id>` for a `kind='form'` URL.** The W13 incident. Use `form_preview_url` or `form_get_embed_snippet`. URL is always `/f/<id>`. Rule 62.
4. **Passing `business_id` on `form_create` after the two-step clone.** 422 — `kind='form'` resolves a per-tenant sentinel business. Omit `business_id`. (`auto_create: true` handles this for you.)
5. **Skipping `form_validate` after customizing.** Free client-side check; catches "added a picture_choice without image_url on its options."

### See also

- [`build-form.md`](forms-booking.md#build-form) — the gold-standard form design recipe (theme presets + tokens + per-question media)
- [`build-lead-gen-form.md`](forms-booking.md#build-lead-gen-form) — end-to-end 6-call lead-gen pipeline
- [`embed-form.md`](forms-booking.md#embed-form) — inline / popup / standalone embed
- [`clone-booking-template.md`](forms-booking.md#clone-booking-template) — booking-kind equivalent
- [`../reference/booking-model.md`](booking-model.md) — `booking_flows` schema, URL surface, Rule 62
- [`../reference/tool-surface.md`](tool-surface.md) — `form_*` tool catalog, MCP package picker
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Clone Booking Template

Clone a global booking template into your tenant — cal.com-backed calendar slots, staff calendar resolution, ICS invites. Sibling to `clone-form-template.md` but for `kind='booking'`.

### When to use

- A tenant runs a service business (clinic, salon, agency, consultant) that needs visitors to book time slots on a real calendar.
- You want a multi-step intake-then-book flow: qualifying questions → calendar slot picker → confirmation.
- You're matching a Calendly/SavvyCal-style flow but want it on your tenant's domain + your tenant's branding.

For a simple data-collection form (no calendar) → [`clone-form-template.md`](forms-booking.md#clone-form-template). For inviting staff to connect their calendars → [`invite-staff-calendar.md`](forms-booking.md#invite-staff-calendar).

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **MCP server with `booking_flow_*` tools.** Lives in `@spideriq/mcp` (kitchen-sink) alongside `form_*`. Same package picker rules as forms.
3. **A cal.com team set up for the tenant.** Booking flows back onto cal.com for the slot grid + staff calendar resolution. Without a cal.com team, `booking_flow_publish` can't provision an event-type. Check with the tenant whether their cal.com team exists; if not, set it up via the dashboard (Settings → Integrations → cal.com).
4. **(For each staff calendar)** Calendar-OAuth completed via invite. See [`invite-staff-calendar.md`](forms-booking.md#invite-staff-calendar).

### The 3-call path

```
1. (browse) — same as form_list_global_templates but filter for kind='booking'
2. booking_flow_clone_template / booking_create_flow — clone the template
3. booking_flow_publish — provision the cal.com event-type + go live
```

The exact MCP tool names for the booking surface match the form surface where there's parity (`booking_flow_get`, `booking_flow_update`, `booking_flow_delete`, etc.) and add cal.com-specific tools (`booking_flow_publish` provisions cal.com, the staff-invite flow uses dedicated endpoints).

**Resolved 2026-05-24:** there is NO `booking_flow_list_templates` MCP tool. Booking templates browse via `form_list_global_templates({ kind: "booking" })` — the same tool the form-flow surface uses, filtered server-side by `kind`. The `booking_flows` table holds both kinds; the `kind` column disambiguates. Tool at [`packages/mcp-tools/src/publish/forms.ts:1665`](https://github.com/SpiderIQ/SpiderIQ/blob/master/packages/mcp-tools/src/publish/forms.ts#L1665).

#### 1. Browse booking templates

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

#### 2. Clone

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

#### 3. Publish (provisions cal.com)

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

### Calendar pool — how slot resolution works

Once published, when a visitor lands on `/f/<flow_id>` and reaches the `BookingStep`:

1. SpiderPublish calls cal.com `GET /slots?team_id=<id>&event_type_id=<id>&start=...&end=...`.
2. cal.com aggregates availability across every connected staff calendar in the team.
3. cal.com returns 15-min (or `length_minutes`) blocks where ALL staff (or AT LEAST ONE staff, depending on team config) are available.
4. SpiderPublish renders these blocks. Visitor picks one.
5. SpiderPublish POSTs `POST /bookings` to cal.com with the visitor's name + email + chosen slot.
6. cal.com sends ICS invites to (a) the staff member resolved for that slot, (b) the visitor.
7. SpiderPublish writes the booking row to `booking_submissions`; webhook fires to the tenant's CRM if configured.

If no staff has connected their calendar yet, the slot grid is empty and visitors see "No availability." Solution: [`invite-staff-calendar.md`](forms-booking.md#invite-staff-calendar).

### Customize after clone

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

**Resolved 2026-05-24:** there is NO `booking_flow_add_field` MCP tool. Booking flows use the same `form_add_field` ([`packages/mcp-tools/src/publish/forms.ts:853`](https://github.com/SpiderIQ/SpiderIQ/blob/master/packages/mcp-tools/src/publish/forms.ts#L853)) — they share the `booking_flows` row schema. Pass the booking flow's `flow_id` and `form_add_field` will land the field correctly regardless of `kind`. For step-level additions on multi-step booking flows, pass the explicit `step_id`.

### Embed + share

Same as forms — `/f/<flow_id>` is the canonical URL for both kinds. Use `form_preview_url` (works for both) or compose `https://<tenant>/f/<flow_id>` directly. Or `form_get_embed_snippet` for inline / popup embeds.

```
form_preview_url({ flow_id: "flow_..." })
// → { public_url: "https://spideriq.ai/f/flow_...", ... }
```

### Verify

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

### Anti-patterns

1. **Calling `form_create_from_template` for a booking template.** It 422s — `Template "X" is kind="booking", not "form".` Use the booking equivalent (`booking_flow_clone_template`).
2. **Forgetting `title` / `length_minutes` / `team_id` on `booking_flow_publish`.** The cal.com provisioning step needs all three. Publish 422s without them. (For `kind='form'`, the same fields are ignored — opposite default.)
3. **Publishing before staff have connected their calendars.** The flow is live but the slot grid is empty → visitors see "No availability" and bounce. Always send the staff calendar-invite emails BEFORE publishing.
4. **Constructing `/book/<flow_id>` for the visitor URL.** Use `/f/<flow_id>` — same as forms. `/book/<id>` is a 301 redirect for `kind='booking'` (back-compat), but constructing the legacy URL is the W13-class footgun. Always use `form_preview_url` / `form_get_embed_snippet`. Rule 62.
5. **Mixing cal.com-managed config with SpiderPublish-managed.** Team membership, calendar pool, event-type duration → cal.com owns these. Qualifying questions, theme, embed → SpiderPublish owns. Don't try to set event-type duration via `booking_flow_update`.

### See also

- [`clone-form-template.md`](forms-booking.md#clone-form-template) — same path, `kind='form'` (no cal.com)
- [`invite-staff-calendar.md`](forms-booking.md#invite-staff-calendar) — connect staff calendars (do this BEFORE publish)
- [`build-form.md`](forms-booking.md#build-form) — theme / token / per-question media (applies to booking surface too)
- [`embed-form.md`](forms-booking.md#embed-form) — inline / popup / standalone embed
- [`../reference/booking-model.md`](booking-model.md) — `booking_flows` schema, cal.com integration, URL surface
- [`../reference/tool-surface.md`](tool-surface.md) — `booking_flow_*` tool catalog
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth


---

## Test Form Submission

Submit a **fake test answer** to a published form to verify validation + routing + storage end-to-end, without polluting production responses. Uses `form_test_submit` (or the marketplace twin `marketplace_form_test_submit`).

### When to use

- After editing a form's validation rules — confirm a bad payload returns the right `declared_fields` envelope.
- After wiring up routing/email notifications — confirm the submission shows up in the responses dashboard.
- CI / scripted smoke tests after deploys — see [`../audit/deploy-readiness.md`](audit.md#deploy-readiness).
- Verifying a marketplace form template behaves correctly before recommending it.
- Pattern: "I want to know this form actually works without filling it in by hand."

### Prerequisites

- A PAT scoped to the tenant.
- The form's `flow_id`.
- The form **must be published** — `form_test_submit` reads only `status='active'` rows and returns 404 for drafts. Call `form_publish` first.
- An answer payload that matches the form's declared fields.

### The one call

```
form_test_submit({
  flow_id: "<uuid>",
  answers: {
    "email":      "qa@example.com",
    "first_name": "QA Bot",
    "company":    "ACME"
  }
})
# → {
#     success: true,
#     status:  200,
#     accepted: true,
#     body: { submission_id: "sub_...", ... }
#   }
```

The tool POSTs to `/api/v1/booking/{flow_id}/submit?test=true` with auto-generated `Idempotency-Key` and `X-Customer-Timezone: UTC` headers. Body can be **flat** `{field_id: value}` OR **nested** `{step_id: {field_id: value}}` — match whichever shape your form's `flow.json` uses.

#### With explicit headers

```
form_test_submit({
  flow_id:         "<uuid>",
  answers:         { ... },
  idempotency_key: "qa-2026-05-24-001",     # for reproducible runs
  timezone:        "Europe/Berlin"            # affects timestamp interpretation server-side
})
```

### ⚠️ What `?test=true` actually does

**Honest framing**: the `?test=true` query param is forwarded to the endpoint, but it **only suppresses SendGrid confirmation emails for the shared QA load-test tenant** (`LOAD_TEST_CLIENT_ID`). For arbitrary tenants, it does NOT:

- Bypass the published-required gate (you still need `status='active'`).
- Suppress notification webhooks or other configured automations.
- Mark the submission as "test" in the responses table — it shows up as a real submission.
- Suppress count metrics on the dashboard.

If you need true isolation, use a **dedicated test tenant** (a sandbox `cli_*` you can wipe) rather than relying on `?test=true` on a production tenant.

### The marketplace twin

For marketplace-listed form templates (browsing the public catalog, validating examples before adopting):

```
marketplace_form_test_submit({
  template_slug: "newsletter-2step",
  answers:       { email: "qa@example.com" }
})
```

Submits against the canonical published example of the marketplace template, NOT against a tenant flow. Same envelope shape; same idempotency semantics. Use it when validating a template before `form_create_from_template`.

### Validation-error envelopes

Bad payloads return a structured envelope:

```json
{
  "success": false,
  "status": 400,
  "accepted": false,
  "body": {
    "code": "field_validation_failed",
    "errors": [
      { "field_id": "email", "code": "format", "message": "Not a valid email." }
    ],
    "declared_fields": ["email", "first_name", "company"]
  }
}
```

`declared_fields` is the canonical list of field IDs the form expects — surface it when you got a field-mismatch 400 to help the caller fix the payload shape.

Common error codes: `required` (missing), `format` (bad email/phone/url), `enum` (not in choices), `range` (out of min/max), `pattern` (regex mismatch).

### Steps — typical QA flow

```
1. form_get({ flow_id })                      — read the field list to construct payload
2. form_publish({ flow_id })                  — if not already; safe-default gated
3. form_test_submit({ flow_id, answers })     — happy path
4. form_test_submit({ flow_id, answers: {...with one bad field} })
                                              — confirm validation envelope
5. (Eyeball the responses dashboard or query the `form_responses` table)
```

For CI:

```bash
# Smoke test on every deploy
spideriq form submit test --flow-id <uuid> --answers '{"email":"qa@example.com"}'
# Exit 0 on accepted=true; non-zero on any validation error
```

### Gotchas

- **404 on a draft form is the most common failure.** `form_test_submit` requires `status='active'`. Publish first.
- **Idempotency-Key is auto-generated if absent** — fine for one-off tests, problematic for retries. Pass an explicit key for reproducible runs (a duplicate key returns the original response without re-inserting).
- **Field-id mismatch returns 400 with `declared_fields`.** Read the envelope — the field IDs in your payload may differ from the form's actual field IDs (especially after `form_remove_field` + `form_add_field` re-runs).
- **Nested vs flat payload depends on the form's step structure.** Single-step forms accept flat. Multi-step forms accept either, but if you're testing per-step validation, use nested to scope errors correctly.
- **Submissions land in the real responses table.** Use a dedicated test tenant for high-volume tests; relying on `?test=true` to "clean up later" doesn't work — there's no automatic test-submission purge.
- **Notifications fire.** If the form has an email-routing rule or webhook, a test submission triggers them. Disable routing for QA flows OR use a dummy email + webhook URL.

### Verify

```
# Confirm the submission landed
GET /api/v1/dashboard/booking/flows/<flow_id>/responses?limit=1
# → most recent submission carries your test payload

# OR via CLI
spideriq form responses list <flow_id> --limit 1
```

For visual confirmation that the form itself is rendering before testing:

```
content_visual_check({
  page_url: "https://<tenant>/f/<flow_id>",
  viewport: "desktop"
})
# Assert: dom.shadow_hosts.includes("spideriq-form")
# DO NOT assert on body_text_preview — see Rule 62 in ../reference/booking-model.md
```

### Anti-patterns

- **Testing against draft forms expecting it to "just work."** 404. Publish first.
- **Relying on `?test=true` for test/prod isolation.** It only suppresses SendGrid for the load-test tenant. Use a sandbox tenant.
- **Looping `form_test_submit` 100× to load-test.** Use the load-test tenant + dedicated tooling; you'll trip rate limits on a real tenant.
- **Hardcoding field IDs from old form versions.** Read `form_get` → `flow.json.fields[]` for current IDs every time; `form_update_field` may have renamed them.
- **Composing the submit URL by hand.** Use the MCP tool — the path encoding + headers + idempotency-key generation all matter and are easy to get wrong manually.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "submit a test answer to a form"
# Top-1 should be: recipes/booking/test-form-submission.md
```

### See also

- [`build-form.md`](forms-booking.md#build-form) — author the form before testing it
- [`lock-form-for-review.md`](forms-booking.md#lock-form-for-review) — freeze the form during QA so it doesn't change mid-test
- [`form-as-page-section.md`](forms-booking.md#form-as-page-section) — embed the form in a page; test-submit still hits the same endpoint
- [`../audit/deploy-readiness.md`](audit.md#deploy-readiness) — wire test-submit into the pre-deploy checklist
- [`../reference/booking-model.md`](booking-model.md) — `booking_flows` schema + Rule 62 visual-check assertion


---

## Lock Form For Review

Park a form against accidental edits while a human reviews it — `form_lock` / `form_unlock`. Idempotent, returns 423 to other editors with the unlock endpoint baked in. Pairs with [`../content/lock-page-during-review.md`](content.md#lock-page-during-review) for the page-level twin.

### When to use

- An agent (or another teammate) is about to send the form to a client for approval and you don't want a second editor accidentally mutating fields between "sent" and "approved."
- You're running a live A/B with two field orderings and want one variant frozen while the other iterates.
- A regulated form (legal, compliance, KYC) needs a "no changes after this point" guarantee before going to audit.
- Pattern: "freeze this exactly the way it is for the next 48 hours."

### Prerequisites

- A PAT scoped to the tenant that owns the form.
- The form's `flow_id` (UUID). Works for both `kind='form'` and `kind='booking'` (same `booking_flows` table).
- For unlock: either the lock holder's session, OR `super_admin` / `brand_admin` with `force=true`.

### Lock — the one call

```
form_lock({
  flow_id: "<uuid>",
  reason:  "Sent to client for approval — do not edit until ack"
})
# → {
#     success: true,
#     flow: {
#       ...,
#       is_locked: true,
#       locked_by_actor_id: "act_...",   # your PAT's actor id
#       locked_at: "2026-05-24T12:34:56Z",
#       locked_reason: "Sent to client for approval — do not edit until ack"
#     }
#   }
```

Idempotent — re-locking refreshes `locked_at` and `locked_reason`. Any role with form-CRUD access can lock; unlock is more restrictive.

### Unlock — the same shape

```
form_unlock({ flow_id: "<uuid>" })
# → { success: true, flow: { is_locked: false, ... } }
```

The lock holder can unlock unconditionally. Other callers get **403** (or **404** if they aren't the holder — the API does NOT leak the lock-holder identity to unprivileged callers; you'd see "not found" rather than "you can't").

#### Force-unlock (`super_admin` / `brand_admin` only)

```
form_unlock({
  flow_id: "<uuid>",
  force:   true
})
# → { success: true, flow: { ... } }    (overrides any holder)
```

`force=true` is rejected for non-super_admin / non-brand_admin callers regardless of who locked. Use sparingly — there's an audit log row for every force-unlock.

### What lock blocks vs allows

| Operation | Blocked when locked? |
|---|---|
| `form_update`, `form_add_field`, `form_remove_field`, `form_update_field`, `form_reorder_fields` | **Yes** — 423 Locked with the unlock endpoint in the envelope |
| `form_add_choice`, `form_add_logic_rule`, `form_remove_logic` | **Yes** — 423 |
| `form_publish`, `form_delete`, `form_restore_version` | **Yes** — 423 |
| `form_duplicate` | **No** — duplicates are NEW rows; the new flow is unlocked |
| `form_get`, `form_preview_url`, `form_get_embed_snippet`, `form_validate` | **No** — reads always allowed |
| `form_test_submit` | **No** — submissions to the locked form's public URL still work (lock blocks AUTHORING, not USE) |
| `form_lock` (re-lock by holder) | **No** — idempotent refresh of reason/timestamp |

The 423 envelope returns:

```json
{
  "status": 423,
  "code": "form_locked",
  "locked_by_actor_id": "act_xxx",
  "locked_reason": "Sent to client for approval",
  "locked_at": "2026-05-24T12:34:56Z",
  "unlock_endpoint": "/api/v1/booking/flows/<uuid>/unlock"
}
```

Use the `unlock_endpoint` field to compose a "request unlock" UI affordance rather than hardcoding the path.

### Steps — typical review flow

```
1. form_update / form_add_field / ...     — finalize the form
2. form_publish                            — flip to status='active' (safe-default gated)
3. form_lock({ flow_id, reason })          — freeze for review
4. form_preview_url({ flow_id })           — share the /f/<id> URL with the reviewer
5. (reviewer eyeballs, sends ack)
6. form_unlock({ flow_id })                — reopen for edits
   OR
6'. form_unlock({ flow_id, force: true })  — admin override if the lock holder is unavailable
```

### Gotchas

- **404 vs 403 on unlock is intentional.** Non-holders get 404, not "you can't" — protects the lock holder's identity. If you expected 200 and got 404, check if you're actually the lock holder (`form_get` returns `locked_by_actor_id`).
- **Lock survives form duplication, but the duplicate is unlocked.** `form_duplicate` creates a new row with `is_locked=false`. If you want the duplicate locked too, call `form_lock` on the new flow_id.
- **Lock does NOT freeze the live `/f/<flow_id>` URL.** Submissions keep landing in the same flow's responses. The lock is editor-side only. If you need to STOP accepting submissions, call `form_unpublish` (separate from `form_lock`).
- **No TTL — locks persist until explicitly unlocked.** Forget to unlock and the form sits frozen indefinitely. Pair every lock with a calendar reminder or a follow-up task.
- **`reason` is free-text shown in the dashboard.** Keep it short and actionable ("Sent to ACME for approval — Slack #client-acme") so the next teammate doesn't have to chase context.

### Verify

```
form_get({ flow_id })
# → { ..., is_locked: true, locked_by_actor_id, locked_reason, locked_at }
```

Try to mutate as another user to confirm the gate:

```
form_update({ flow_id, changes: { name: "test" } })
# → 423 Locked envelope (if you're not the holder)
```

### Anti-patterns

- **Locking a form and forgetting to unlock for weeks.** No TTL. Always set a follow-up.
- **Using `force=true` to bypass a teammate's lock without coordinating.** Force-unlock is logged. Ping the holder in chat first; locks exist precisely to avoid this surprise.
- **Locking to "stop submissions."** Wrong primitive. Lock freezes authoring; `form_unpublish` freezes submissions.
- **Treating 404-on-unlock as "form doesn't exist."** It probably means you aren't the lock holder. Run `form_get` to check `is_locked` + `locked_by_actor_id`.
- **Composing the unlock URL by hand.** Use the `unlock_endpoint` field from the 423 envelope — the path may change; the field is canonical.

### Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "freeze a form during review"
# Top-1 should be: recipes/booking/lock-form-for-review.md
```

### See also

- [`../content/lock-page-during-review.md`](content.md#lock-page-during-review) — page-level twin (same primitive on `content_pages`)
- [`share-form-standalone.md`](forms-booking.md#share-form-standalone) — share the `/f/<id>` URL with reviewers (lock-friendly: reads are allowed)
- [`build-form.md`](forms-booking.md#build-form) — author the form before locking it
- [`../reference/booking-model.md`](booking-model.md) — `booking_flows` schema (lock columns are on the same row)
- [`../../_shared/auth.md`](../SKILL.md) — PAT actor identity + role check for `force=true`


---

## Share Form Standalone

Share a `kind='form'` flow via the standalone `/f/<flow_id>` URL — QR code, social bio link, share-with-reviewer link, paste in an email. No iframe, no host page, no embed snippet — just a clean URL.

### When to use

- A tenant wants a QR code on physical signage that takes scanners straight to the form.
- They want a "link in bio" social-media URL (Instagram, TikTok, Twitter bio).
- They want to share a draft with a stakeholder for review WITHOUT publishing or embedding.
- They want a paste-into-email URL ("Click here to register: ...") for outbound campaigns.

If you want to embed inside another site → [`embed-form.md`](forms-booking.md#embed-form). If you want it inside a SpiderPublish page → [`form-as-page-section.md`](forms-booking.md#form-as-page-section).

### The 1-call path

```
form_preview_url({ flow_id: "flow_..." })
// → {
//   public_url: "https://spideriq.ai/f/<flow_id>",
//   dashboard_preview_path: "/dashboard/booking/flows/<flow_id>/preview",
//   note: "public_url is the standalone /f/{flow_id} page..."
// }
```

That's it. `public_url` is the canonical shareable URL.

### Honest framing — what URL you actually get

The URL `form_preview_url` returns is **`${apiUrl}/f/{flow_id}`** where `apiUrl` is the workspace's configured API host — usually `https://spideriq.ai`.

**This is NOT necessarily the tenant's primary verified custom domain.** If the tenant has `demo.spideriq.ai` registered + verified, `form_preview_url` still returns `https://spideriq.ai/f/<flow_id>`, not `https://demo.spideriq.ai/f/<flow_id>`. (Pure string composition; no API round-trip to fetch domain config. S4-B5 honesty fix 2026-05-20.)

#### When to use `spideriq.ai/f/<id>` (the default)

- The form is for an internal/sales audience that doesn't need brand consistency.
- The tenant hasn't deployed a custom domain yet.
- You're sharing a draft for review.
- You want the link to keep working even if the tenant changes domains.

#### When to compose the tenant-domain URL yourself

If the tenant has a verified custom domain AND you want the form's standalone URL on that domain:

```
content_list_domains()
// → [{ host: "demo.spideriq.ai", is_primary: true, verified_at: "..." }, ...]

# Compose the URL yourself
const primary_host = "demo.spideriq.ai";
const standalone_url = `https://${primary_host}/f/${flow_id}`;
```

The custom-domain URL works only if:
1. The domain is verified (`verified_at` non-null).
2. The tenant has deployed (`content_deploy_status` shows `live`).
3. The form is published (`status: active`).

All three need to be true for the URL to render. Otherwise the visitor gets a 404 from the renderer fleet or an "unverified domain" error from Cloudflare.

### Make it a QR code

The simplest QR pattern: just encode the standalone URL.

```bash
# Pick your favorite QR encoder — example with qrencode
qrencode -o form-qr.png "https://demo.spideriq.ai/f/$FLOW_ID"
```

For high-density physical signage (small QR codes), keep the URL short. The `spideriq.ai/f/<flow_id>` default is ~40 chars — fine for most printed materials. If you need shorter, set up a redirect via `content_redirects` ([`../content/landing-page.md`](content.md#landing-page) doesn't cover redirects yet; see catalog/CLAUDE.md → "Public API Endpoints" → `/content/redirects/check`).

### Make it a social-bio link

Same standalone URL. Paste into Instagram/TikTok bio. For tracking:

- Add hidden fields to the form via `form_add_hidden_field` BEFORE publishing.
- Pass them as URL params: `https://<tenant>/f/<flow_id>?utm_source=instagram&campaign=spring24`.
- Only DECLARED hidden_fields are captured — arbitrary query params are stripped (the form's security model).

```
form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "utm_source", label: "UTM source" }
})
form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "campaign", label: "Campaign code" }
})
# After publish, the URL with params persists those values on the lead row.
```

### Share-with-reviewer (the draft flow)

To share a form with a stakeholder for review BEFORE publishing:

**Option 1 — Internal dashboard preview URL.** `form_preview_url` returns `dashboard_preview_path: "/dashboard/booking/flows/<flow_id>/preview"`. The reviewer needs dashboard access (a SpiderPublish user account) to view it. Useful for internal stakeholders only.

**Option 2 — Publish to a staging-shaped flow.**
- `form_publish` the flow.
- Share `https://spideriq.ai/f/<flow_id>`.
- After review, either leave published OR `form_lock` it to prevent edits during review.

**Option 3 — Form-lock-for-review pattern.** Lock the form mid-edit so other collaborators can't change it while the reviewer is testing.

```
form_lock({ flow_id: "<flow_id>", reason: "Under review by client; do not edit." })
# Share the URL
# After review:
form_unlock({ flow_id: "<flow_id>" })
```

See [`lock-form-for-review.md`](forms-booking.md#lock-form-for-review) for the full lock semantics.

### After publish — verify the URL works

```
# 1. Confirm the form is active
form_get({ flow_id: "<flow_id>" })
# → { status: "active", ... }

# 2. Visual check (with Rule 62 assertion)
content_visual_check({
  page_url: "https://spideriq.ai/f/<flow_id>",
  viewport: "desktop"
})
# Assert on dom.shadow_hosts.includes("spideriq-form")
```

For mobile (QR-scanner audience usually scans on phone):

```
content_visual_check({
  page_url: "https://spideriq.ai/f/<flow_id>",
  viewport: "mobile"
})
```

Check screenshot for mobile-shaped layout. Forms with `theme.preset: 'fullscreen-dark'` and per-question media render differently on mobile (left/right splits collapse to stacked).

### Anti-patterns

1. **Composing `/book/<flow_id>` for the standalone URL.** Always `/f/<flow_id>`. The W13 incident's exact failure shape — `/book/<id>` 301s for `kind='booking'` but silent-fails for `kind='form'`. Rule 62. Use `form_preview_url`; never string-template.
2. **Sharing a draft URL.** `/f/<flow_id>` returns 404 until `status: 'active'`. Always `form_publish` before sharing externally.
3. **Using QR codes for forms with required URL params.** QRs are typically the URL alone (no `?utm_source=...`). If you need params on a QR, encode them in the QR; otherwise the form receives no hidden-field values.
4. **Asserting on `body_text_preview` for the standalone URL screenshot.** Shadow DOM = opaque to `body_text_preview`. Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.
5. **Sharing the dashboard preview path with non-dashboard-users.** `/dashboard/booking/flows/<id>/preview` requires SpiderPublish login. Use `/f/<flow_id>` for external sharing.
6. **Putting hidden fields in the URL that aren't declared via `form_add_hidden_field`.** Stripped at form load. Always declare hidden fields BEFORE publish + sharing the URL.

### See also

- [`embed-form.md`](forms-booking.md#embed-form) — embed `kind='form'` flow OUTSIDE SpiderPublish (iframe, popup)
- [`form-as-page-section.md`](forms-booking.md#form-as-page-section) — embed INSIDE a SpiderPublish page
- [`build-form.md`](forms-booking.md#build-form) — author the form before sharing
- [`build-lead-gen-form.md`](forms-booking.md#build-lead-gen-form) — end-to-end pipeline
- [`clone-form-template.md`](forms-booking.md#clone-form-template) — one-shot clone from template
- [`../reference/booking-model.md`](booking-model.md) — `kind='form'` URL surface, S4-B5 honesty fix, Rule 62
- [`../content/custom-domain.md`](integrations.md#custom-domain) — verify a custom domain for tenant-domain standalone URLs
- catalog/LEARNINGS.md Rule 62 + W13 — the source incident


---

## Invite Staff Calendar

Invite staff to connect their calendar to a booking flow — calendar-OAuth-by-invite. The tenant doesn't ask each staff member to "log into the dashboard and click connect"; instead, staff click a per-staff email link, OAuth into Google/Outlook/iCloud, and they're done.

### When to use

- A tenant has a published `kind='booking'` flow but the slot grid is empty (no staff calendars connected).
- A staff member changed calendar providers (Gmail → Outlook) and needs to re-connect.
- A new staff member joined and you're adding them to the booking pool.

If you're cloning the booking template itself → [`clone-booking-template.md`](forms-booking.md#clone-booking-template). If you're authoring the booking flow → not yet covered; see the catalog/CLAUDE.md "Booking flows" section.

### Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **A booking flow exists** (`kind='booking'`, status `draft` or `active`). The invite links scope to a specific `flow_id`.
3. **Staff members' email addresses.** The invite is sent to each staff email; they need to be able to receive it.
4. **A cal.com team for the tenant.** The team is what aggregates the connected calendars. Configured server-side at tenant onboarding.

### Why calendar-OAuth-by-invite (vs dashboard onboarding)

Staff who deliver bookings often aren't dashboard users — they're delivery contractors, hairdressers, sales reps, estate agents. Getting them through a "create an account, set a password, log in, navigate to Settings, click Integrations, click Connect Calendar" flow is brittle and often fails.

The invite flow:
1. Tenant adds the staff member by email.
2. SpiderPublish emails: "[Tenant] wants you to receive bookings via [Flow name]. Click here to connect your calendar."
3. Staff clicks. Lands on a hosted SpiderPublish page. OAuths into Google/Outlook/iCloud (provider auto-detected from email domain; staff confirms).
4. Done. Their calendar is in the pool. No password, no dashboard, no follow-up.

Mental model: this is the calendar-equivalent of "sign in with Google" for end users — one click, no account creation.

### The 3-call path

```
1. (book the flow if not done yet)         — clone-booking-template.md
2. booking_flow_invite_staff                — provision per-staff invite tokens + send emails
3. (staff click email, OAuth)               — outside SpiderPublish; verify via staff connection status
```

Then verify with a slot-grid check.

**Resolved 2026-05-24 — product gap flagged:** there is NO `booking_flow_invite_staff` MCP tool in `@spideriq/mcp` as of this writing. Staff-invite happens via REST at `POST /api/v1/booking/flows/{flow_id}/staff/invite` (file: [`app/api/v1/booking/`](https://github.com/SpiderIQ/SpiderIQ/tree/master/app/api/v1/booking)). Use CLI or curl until the MCP wrapper lands. Tracked for a future MCP-wrapper PR.

#### 1. (Pre-flight) ensure the flow exists

```
booking_flow_get({ flow_id: "flow_..." })
// → { kind: "booking", status: "draft" | "active", calendar_pool: "main", ... }
```

If `status: "draft"` you can still invite staff — they'll be connected by the time you publish. If the response is `kind: "form"`, this recipe doesn't apply (forms don't use cal.com).

#### 2. Send invites

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

#### 3. Staff click + OAuth (outside SpiderPublish)

When the staff member clicks:

1. SpiderPublish hosts a page at `<tenant>/staff-invite/<token>`.
2. Page identifies the calendar provider from the email domain (e.g. `@gmail.com` → Google, `@<msft-org>.com` → Outlook). Staff can override.
3. Staff clicks "Connect Google Calendar." Standard OAuth handshake — Google asks for calendar read + write permission.
4. Token comes back; SpiderPublish stores it (encrypted at rest) keyed by `(tenant, staff_email, flow_id)`.
5. Calendar is in the pool. Staff sees a confirmation page; can close the tab.

You don't drive this step programmatically — wait for the staff member.

### Verify the connection landed

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

### Slot grid spot-check

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

### Re-invite / revoke

```
# Re-send the invite (refreshes the token, sends a new email)
booking_flow_invite_staff({ flow_id, staff: [{ email: "bob@..." }] })

# Revoke a staff member's access — they stop appearing in the slot grid pool
booking_flow_remove_staff({ flow_id, email: "carol@..." })
// → { removed: true, connected_at_removed: "..." }
```

Removal also revokes the stored OAuth token server-side (the cal.com integration disconnects). Staff can re-invite by repeating step 2.

### Anti-patterns

1. **Sending the invite email manually by copy-pasting the `invite_url`.** Use the email payload — it includes the right CTA + branding. Manual emails miss the auto-detected calendar provider hint + can land in spam.
2. **Publishing the booking flow BEFORE inviting staff.** The flow is live but `/f/<flow_id>` shows "No availability." Visitors bounce. Invite first, wait for connection, THEN publish.
3. **Inviting staff with personal calendars they don't want exposed.** Staff calendars are read for availability AND written-to with new bookings. If the staff member has personal events on the same calendar, they show as "busy" (good — avoids double-booking) but the calendar shows the booking event too (sometimes unwanted privacy-wise). Solution: a dedicated work calendar.
4. **Asking staff to "just give me their Google password" as a workaround.** Don't. Wait for them to OAuth. The OAuth flow is faster than account+password setup AND doesn't store their password.
5. **Mixing calendar providers in unsupported ways.** Some cal.com configs only allow one provider per team. Test the slot grid after every staff connects to confirm cal.com handles your mix.

### See also

- [`clone-booking-template.md`](forms-booking.md#clone-booking-template) — clone the booking flow before inviting staff
- [`embed-form.md`](forms-booking.md#embed-form) — embed the booking flow on a host page
- [`../reference/booking-model.md`](booking-model.md) — cal.com integration internals
- [`../reference/tool-surface.md`](tool-surface.md) — `booking_flow_*` tool catalog
- [`../../_shared/auth.md`](../SKILL.md) — PAT auth
- catalog/CLAUDE.md → "Calendar-OAuth-by-invite" — internal canonical pattern
