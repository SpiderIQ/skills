# recipes/booking/embed-form

Embed a form (or booking) on any page — inline iframe, popup modal, or standalone URL. One MCP call returns the copy-paste snippet. Works on SpiderPublish pages AND external sites (Webflow, Shopify, WordPress, Framer, plain HTML).

## When to use

- A tenant wants the form to live inside one of their pages (`/contact`, `/get-started`) — use **inline**.
- A tenant has a CTA button that should open the form in a modal — use **popup**.
- A tenant wants a standalone URL to share via QR code, social bio, or paste into an email — use **standalone** (`/f/<flow_id>`).

All three work for both `kind='form'` AND `kind='booking'`. URL is always `/f/<flow_id>` — never `/book/<id>` for forms. This is the W13-incident-codified rule.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **Form exists + is published.** `status: active`. The embed snippet generates regardless of status (pure string composition), but the runtime needs `active` to render. Check with `form_get({flow_id})`.
3. **MCP server with `form_*`.** `@spideriq/mcp` kitchen-sink (134+) — see [`../reference/tool-surface.md`](../reference/tool-surface.md).

## The 1-call path (standalone URL)

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

Why `form_preview_url` doesn't auto-pick the tenant's custom domain: it's pure string composition, no API round-trip to fetch domain config. (S4-B5 honesty fix 2026-05-20.) See [`../reference/booking-model.md`](../reference/booking-model.md#why-form_preview_url-returns-a-spideriqaif-url-not-the-tenants-custom-domain).

## The 1-call path (inline / popup snippet)

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

### Inline embed

```html
<div data-spiderflow-flow="flow_..." data-spiderflow-mode="inline"></div>
<script src="https://embed.spideriq.ai/v1/loader.js" async></script>
```

What it does:
- Loader auto-discovers `<div data-spiderflow-flow="...">` on page load.
- Replaces the div with an `<iframe>` pointing at `forms.spideriq.ai/render/<flow_id>?embed=inline`.
- iframe inherits the parent page's width; auto-resizes its height as the form progresses through screens.

Use when: the form IS the page content (or a major section), not a hover-out modal.

### Popup embed

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

### Prefill from URL params

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

## Embed inside a SpiderPublish page (the cleanest way)

The dashboard supports a native form block — pick the form from a dropdown, and the renderer inlines it server-side instead of via iframe:

```
content_update_page({
  page_id: "<page-uuid>",
  blocks: [
    ...,
    {
      id: "blk_form",
      type: "component",
      component_slug: "spideriq-form-embed",
      data: { flow_id: "flow_..." }
    }
  ]
})
```

<!-- VERIFY: the canonical native-block component_slug for forms inside SpiderPublish pages. `spideriq-form-embed` is a best-guess; check `content_list_components({ category: "contact_form", include_global: true })` for the actual slug. -->

Inline server-side render avoids the iframe round-trip + CSP boundary. Use this when the form lives on a SpiderPublish-served page. The `form_get_embed_snippet` iframe path is for external (non-SpiderPublish) host pages.

## On external sites (Webflow, Shopify, WordPress, etc.)

The snippet from `form_get_embed_snippet` drops anywhere. The loader bundle is ~3 KB gzip, served from a single CDN URL (`embed.spideriq.ai/v1/loader.js`).

| Host | Where to paste |
|---|---|
| **Webflow** | Add an "Embed" element where you want the form. Paste the snippet. |
| **Shopify** | Theme → Customize → add a "Custom Liquid" section. Paste. |
| **WordPress** | Use the "Custom HTML" block in Gutenberg. Paste. |
| **Framer** | Add an "Embed" component. Paste. |
| **Plain HTML** | Paste anywhere in `<body>`. |

### Cross-origin postMessage protocol

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

## Verify the embed works

After dropping the snippet on a host page:

```
content_visual_check({
  page_url: "https://<host-page-url>",
  viewport: "desktop"
})
```

**Assert on `dom.shadow_hosts.includes("spideriq-form")`** — the loader mounts a `<spideriq-form>` custom element in the parent DOM (it's a Shadow DOM host). DO NOT assert on `body_text_preview` for the form labels — the iframe body is **opaque** to the parent page. (See [`../reference/booking-model.md`](../reference/booking-model.md#visual-check) — Rule 62.)

If `dom.shadow_hosts` doesn't include `spideriq-form`:
- Did the loader script load? Check `console_errors` — `script error: <loader>` means the CSP blocked it. Whitelist `embed.spideriq.ai` in the host page's CSP.
- Is the `data-spiderflow-flow` attribute spelled right? Typo → loader can't find the element.
- Is the form `status: active`? Draft forms 404 in the iframe.

## Update / re-embed

The snippet is bound to `flow_id`. If you change the form's structure (`form_update`, `form_add_field`), no re-embed needed — the loader fetches the latest flow JSON on every render. The snippet stays valid until you delete the flow.

If you replace the form with a new `flow_id`: re-call `form_get_embed_snippet({flow_id: <new>})` and update the host page's snippet.

## Anti-patterns

1. **Composing `/book/<flow_id>` for a `kind='form'`.** Use `/f/<flow_id>` for everything. The W13 incident's exact failure shape. Always call `form_preview_url` / `form_get_embed_snippet`; never string-template URLs. Rule 62.
2. **Asserting on `body_text_preview` after visual-check.** Cross-origin iframe = opaque. Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.
3. **Embedding a draft form.** The snippet renders but the iframe 404s. Always `form_publish` first.
4. **Pasting the snippet without `async` on the script tag.** The loader is design-only on first render; the form iframe takes over once it loads. Without `async`, the parent page blocks on loader fetch.
5. **Inline-embedding on a page with strict CSP that doesn't whitelist `embed.spideriq.ai` / `forms.spideriq.ai`.** Loader fails silently in some CSP configs (`script-src` blocks the loader; `frame-src` blocks the iframe). Test in DevTools after deploy.
6. **Using `prefill` without declaring the hidden field via `form_add_hidden_field`.** The loader passes the value, but the form drops it (only declared hidden fields persist). Declare hidden fields BEFORE embed.

## See also

- [`build-form.md`](build-form.md) — author the form before embedding
- [`build-lead-gen-form.md`](build-lead-gen-form.md) — end-to-end pipeline (create + publish + embed in 6 calls)
- [`clone-form-template.md`](clone-form-template.md) — clone from a template; ends in `form_get_embed_snippet`
- [`clone-booking-template.md`](clone-booking-template.md) — same embed flow works for booking
- [`../reference/booking-model.md`](../reference/booking-model.md) — URL surface, Rule 62, W13 incident
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `form_*` tool catalog
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
