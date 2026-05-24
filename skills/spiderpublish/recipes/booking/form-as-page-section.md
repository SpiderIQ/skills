# recipes/booking/form-as-page-section

Embed a conversational `kind='form'` flow as a block inside a SpiderPublish page (vs. as an external-site iframe). Two paths: native page-level form components (`sys-form-*`, no `flow_id`) for simple capture, OR the `kind='form'` flow embed for full conversational + logic.

## When to use

**Path A — Native page-level form (`sys-form-*` components):**

- Simple email capture, newsletter signup, 2-step opt-in.
- You want the form rendered INLINE on the page (no iframe; same origin).
- You don't need welcome screens, conditional logic, variables, or `/f/<id>` standalone share.

**Path B — `kind='form'` flow embed:**

- You've built a multi-step conversational form (welcome → fields → logic → thank-you).
- You want the SAME form available at `/f/<flow_id>` AND inside a page.
- You need theme presets, per-question media, logic jumps, variables.

If you ONLY want the form embedded outside SpiderPublish (Webflow / Shopify) → [`embed-form.md`](embed-form.md). If you want the form at `/f/<flow_id>` only → just publish it; the standalone URL is auto.

## Path A — Native page-level form (3 sys-form-* options)

### The catalog

| Slug | Use |
|---|---|
| `sys-form-newsletter-inline` | One-field email capture; rendered inline as a section |
| `sys-form-2step-optin` | Two-step (email → confirm) with cookie-based dismissal |
| `sys-form-multistep-funnel` | Multi-step page-level funnel (no /f/<id>; lives entirely in the page) |

These are part of the CRO catalog with `marketplace_category='capture'`. See [`../marketplace/browse-cro-components.md`](../marketplace/browse-cro-components.md) for the full CRO surface.

### The 3-call path

```
1. content_list_marketplace_components({ category: "capture" })
2. content_get_component_by_slug({ slug: "sys-form-2step-optin" })   # inspect props
3. page_insert_section({ page_id, component_slug, props })           # dry_run + confirm
```

### Insert

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

### When Path A is enough

- Email-only capture (newsletter).
- Single-step with light follow-up (2step opt-in).
- Linear multi-step where you don't need logic / branching (multistep-funnel).
- No requirement for the form to also be at `/f/<id>`.

## Path B — `kind='form'` flow embed inside a page

When you want one source of truth for the form (theme, fields, logic) and TWO surfaces: the page-block AND the standalone `/f/<flow_id>` URL.

The native form block component slug is `spideriq-form-embed` <!-- VERIFY: confirm canonical slug — `spideriq-form-embed` is best-guess from `dom.shadow_hosts.includes("spideriq-form")` shadow-host convention. Check `content_list_components({ category: "contact_form", include_global: true })` for the actual slug; may be `sys-form-flow-embed` or similar. -->.

### The 4-call path

```
1. form_create_from_template / form_create   — author the kind='form' flow
2. form_publish                              — flip to status='active'
3. content_get_component_by_slug             — confirm the page-block component exists
4. page_insert_section                       — insert into the target page
```

### Step 1-2 — author + publish the flow

See [`build-form.md`](build-form.md) (theme + fields) or [`clone-form-template.md`](clone-form-template.md) (one-shot template clone). The result: a `kind='form'` row in `booking_flows` with `status: active` and a `flow_id`.

### Step 3 — confirm the page-block component

```
content_get_component_by_slug({ slug: "spideriq-form-embed" })   # VERIFY actual slug
// → { props_schema: { properties: { flow_id: { type: "string" }, height_px: { ... } } } }
```

The native form block accepts `flow_id` as its primary prop. The renderer reads the form's flow JSON, server-side-renders the conversational steps, AND mounts the `<spideriq-form>` Shadow DOM host for client-side interactivity (logic, jumps, variables).

### Step 4 — insert into a page

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

### Step 5 — publish the page + deploy

```
content_publish_page({ page_id: "<page-uuid>" })
content_publish_page({ page_id: "<page-uuid>", confirm_token: "..." })
content_deploy_site_production({ confirm_token: "..." })
```

## Path A vs Path B — pick the right one

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

## Verify

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

## Submission handling

- **Path A — webhooks.** `webhook_url` on the component props receives the POST. No SpiderPublish submission storage; you handle persistence on your side.
- **Path B — full SpiderPublish submission flow.** Submits POST to `/api/v1/forms/{flow_id}/submit`, persists to `booking_submissions`, fires webhooks if configured, fires `spiderflow:complete` postMessage events (when in iframe contexts).

## Anti-patterns

1. **Path B with the wrong native-form slug.** Until the VERIFY marker resolves, confirm via `content_list_components({ category: "contact_form", include_global: true })` before composing `page_insert_section`. Don't guess.
2. **Asserting on `body_text_preview` for Path B field labels.** Shadow DOM = opaque to outer `body_text_preview`. Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.
3. **Using `sys-form-newsletter-inline` for a multi-field lead form.** It's email-only. For multi-field on a page → `sys-form-multistep-funnel` (Path A) OR `kind='form'` flow + Path B.
4. **Forgetting to publish the `kind='form'` flow before Path B insert.** The block embeds correctly but the form renders as "Form unavailable" because status is `draft`. Always `form_publish` first.
5. **Adding both Path A `sys-form-2step-optin` AND Path B `kind='form'` embed for the same email-capture intent on one page.** Visitor confusion + double-submission risk. Pick one.
6. **Treating `sys-form-multistep-funnel` as having `/f/<id>`-style URL.** It doesn't — it's a page-level multi-step component, not a `kind='form'` flow. Different surface entirely.

## See also

- [`build-form.md`](build-form.md) — author a `kind='form'` flow (Path B step 1)
- [`build-lead-gen-form.md`](build-lead-gen-form.md) — end-to-end Path B pipeline
- [`clone-form-template.md`](clone-form-template.md) — one-shot template clone for Path B
- [`embed-form.md`](embed-form.md) — embed `kind='form'` flow OUTSIDE SpiderPublish (iframe)
- [`share-form-standalone.md`](share-form-standalone.md) — `/f/<flow_id>` URL for QR / bio sharing
- [`../marketplace/browse-cro-components.md`](../marketplace/browse-cro-components.md) — full CRO catalog including the 3 sys-form-* components
- [`../content/landing-page.md`](../content/landing-page.md) — page authoring before insert
- [`../reference/booking-model.md`](../reference/booking-model.md) — `kind='form'` flow data model + Rule 62
- [`../reference/block-types.md`](../reference/block-types.md) — `type: "component"` block shape
