# recipes/design-a-form

Give a Form a real visual identity — pick a preset, override the design tokens that matter, and add per-question media (background image, side-image split, video) where it fits. Everything ships through the `theme` argument on `form_create` / `form_update` plus the `media` field on individual form fields.

## When to use

- The neutral default look is fine for a developer preview but lands flat for a client demo.
- You want one form to feel "luxury hotel" and another to feel "agency portfolio" — same widget, different surface.
- A specific question deserves its own background image (e.g. the venue photo on a wedding inquiry form).
- You're matching a brand's exact `--primary` colour, button radius, or heading font.

## The four design knobs

| Knob | Where | Granularity | Trust |
|---|---|---|---|
| **Preset** | `theme.preset` | Form-wide | 6 author-owned bundles; trusted |
| **Token overrides** | `theme.tokens["--<name>"]` | Form-wide; layered on top of the preset | Sanitised — unknown keys + unsafe values dropped |
| **Per-question media** | `field.media` | Per field; coexists with theme | URL + position + opacity only |
| **Theme aliases** | `theme.tokens.primary_color` etc. | Same as tokens; convenience for non-CSS names | Maps to canonical `--<name>` keys |

The renderer applies them in that order: preset first, then `tokens` overrides, then media on the active question. Mobile breakpoints (≤ 768px) collapse left/right splits to stacked.

## The 6 bundled presets

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

## Token overrides — the 15 you'll reach for most

Every token below accepts a plain CSS value (length / colour / font-stack / shadow). All custom property names start with `--` and are written kebab-case. The renderer drops **unknown keys** and **unsafe values** (`url(...)` from end-user input, `expression()`, `javascript:`) silently — see [Sanitisation](#sanitisation) below.

### Colour

| Token | What it controls | Example |
|---|---|---|
| `--primary` | Buttons, progress fill, focused borders | `"#1f6feb"` |
| `--primary-contrast` | Text on top of `--primary` | `"#ffffff"` |
| `--bg` | Page background | `"#fafaf9"` |
| `--surface` | Card / input background | `"#ffffff"` |
| `--text` | Body text colour | `"#1f2328"` |
| `--accent` | Secondary highlight | `"#8957e5"` |

### Type

| Token | What it controls | Example |
|---|---|---|
| `--font-body` | Body text font stack | `'"Inter", system-ui, sans-serif'` |
| `--font-heading` | Question + screen headings | `'ui-serif, Georgia, serif'` |
| `--font-size-heading` | Heading size | `"2rem"` |
| `--font-size-label` | Question-label size | `"1.25rem"` |

### Shape

| Token | What it controls | Example |
|---|---|---|
| `--button-radius` | CTA corner radius — `0` = square, `8px` = rounded, `999px` = pill | `"999px"` |
| `--input-radius` | Input field corner radius | `"0"` (underlined) |
| `--layout-max-width` | Max width of the form column | `"720px"` |
| `--field-gap` | Vertical rhythm between screens | `"1.75rem"` |
| `--bg-overlay-color` | Tint over `--bg-image` | `"rgba(0, 0, 0, 0.4)"` |

### Aliases (handy when you're translating from a brand guideline)

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

## Per-question media (`field.media`)

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

### Media schema

| Field | Type | Notes |
|---|---|---|
| `url` | string (1–2048 chars) | HTTPS URL. Origin must be reachable from the public renderer. |
| `type` | `"image"` \| `"video"` | Video uses `<video autoplay muted playsinline loop>`. |
| `position` | `"background"` \| `"left"` \| `"right"` \| `"top"` | See positions below. |
| `opacity` | `0.0` – `1.0` | **Only honoured for `position: "background"`** — used as the `--media-overlay-opacity` for that screen. Ignored on left/right/top. |
| `poster_url` | string (1–2048 chars) | Still-image fallback for `type: "video"` when autoplay is blocked or the user is on a data-saver connection. Ignored for `type: "image"`. |

Forbidden on `statement` fields backend-side (they keep their existing `attachment_url`).

### The 4 positions

| Position | Layout | When it works best |
|---|---|---|
| **`background`** | Full-screen behind input + question | Atmospheric — single mood image / video. Pair with `opacity: 0.3 – 0.55` so the input stays legible. |
| **`left`** | 50/50 split, media left + input right | Catalogue or showcase — product shot next to "Which size?". Collapses to stacked at ≤ 768px (media on top). |
| **`right`** | 50/50 split, input left + media right | Same as `left`, mirrored. Good for forms read in right-to-left languages. |
| **`top`** | Stacked, media above input | Header-style hero per question. Works on all viewport widths without collapse. |

### Mobile collapse

`left` and `right` collapse to stacked at viewport width ≤ 768px (media renders above the input). `background` and `top` are responsive at every breakpoint. The renderer handles this automatically — no separate mobile theme needed.

### Video tips

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

## Sanitisation

The renderer is permissive with shape and strict with values:

- Unknown token keys (e.g. `"--made-up"` or `theme: { tokens: { random_thing: "x" } }`) — silently dropped.
- Token values longer than 256 chars — rejected.
- Token values matching `url(` / `expression(` / `javascript:` / `</script` — rejected. Preset-supplied `linear-gradient(...)` values for `--bg-image` bypass this (preset tokens are TRUSTED); end-user-supplied `--bg-image` is restricted to `none` / `linear-gradient(...)` / plain colour values.
- Preset slugs you don't recognise are forwarded as-is (forward-compat with renderer builds that add new presets); the renderer drops slugs it can't resolve.

This means you can paste a brand guideline straight into `theme.tokens` and the renderer keeps what it understands and discards the rest, without breaking the form.

## Common patterns

### Luxury hotel feel

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

### Boutique agency pitch form

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

### Legal intake / serious tone

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

### Conversational survey (Typeform-feel)

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

## End-to-end recipe

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

## Anti-patterns

- **Don't paste a multi-line CSS string into `theme.tokens`** — values are capped at 256 chars and matched against the unsafe-value regex. One key, one short value.
- **Don't rely on `opacity` for `position: "left" | "right" | "top"`** — the renderer ignores it. For split layouts, dim the image at source.
- **Don't ship a video without `poster_url`** — autoplay-blocked viewers see a black box.
- **Don't tune the preset and then completely override it** — if you find yourself overriding 10+ tokens of a preset, you probably want a different preset. Browse the table above first.
- **Don't use `--bg-image` directly with `url(...)` from user input** — sanitisation rejects it. Either use one of the gradient-based presets (`form-on-image`) or set the image via `field.media` on the first question with `position: "background"`.

## See also

- [recipes/build-lead-gen-form](../build-lead-gen-form/SKILL.md) — end-to-end form pipeline (this recipe is what plugs into the `theme` argument there)
- [recipes/idap-fill-from-form](../idap-fill-from-form/SKILL.md) — IDAP-anchored field types + `crm_target`
- [core-skills/forms/SKILL.md](../../core-skills/forms/SKILL.md) — full `form_*` tool catalog
- [examples/design-a-form.sh](../../examples/design-a-form.sh) — bash version of the wedding-inquiry example
