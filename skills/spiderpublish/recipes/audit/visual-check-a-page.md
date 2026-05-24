# recipes/audit/visual-check-a-page

Run a Playwright-sidecar visual check on a deployed page — screenshot, DOM probe, console-error capture. The regression net codified by the W13 incident. Rule 62 lives here.

## When to use

- After every production deploy, to confirm the page actually renders (the silent-200 failure class).
- Verifying a `kind='form'` flow embed renders the form (shadow-DOM host present).
- Smoke-testing a CRO component after insert.
- Verifying a custom-domain swap actually serves your tenant content (not Cloudflare's 404).
- Empirically confirming an agent's edit before declaring "done."

For LINK auditing (404s in nav, dead internal links) → [`link-audit.md`](link-audit.md). For a full pre-deploy checklist → [`deploy-readiness.md`](deploy-readiness.md). For ongoing audits → [`audit-driven-edit.md`](audit-driven-edit.md).

## Prerequisites

1. **Page is publicly reachable.** Visual-check sidecar runs against the public URL — auth-walled pages won't load.
2. **Visual-check sidecar healthy.** It runs as a separate container (`spideriq-visual-check`) on port 8080. If unreachable → 503 / no-screenshot envelope.

## The 1-call path

```
content_visual_check({
  page_url: "https://<tenant>/<page-slug>",      # NOT `url` — `page_url` is the param name
  viewport: "desktop"                            # OR "mobile" — enum, NOT `{width, height}` object
})
// → {
//   success: true,
//   screenshot_url: "https://media.spideriq.ai/visual-check/<sha>/screenshot.png",
//   dom: {
//     shadow_hosts: [ "spideriq-form", "spideriq-cmp" ],
//     elements_seen: 142,
//     scripts_loaded: 8
//   },
//   body_text_preview: "<!doctype html>... [host page chrome] ...",
//   console_errors: [],
//   request_log: [
//     { url: "...", status: 200, type: "script" },
//     ...
//   ],
//   timings: { dom_content_loaded_ms: 423, load_ms: 1234 }
// }
```

The sidecar:
1. Spins up a headless Chromium via Playwright.
2. Sets the viewport (desktop = 1280×800; mobile = 390×844).
3. Navigates to `page_url`.
4. Waits for `load` event + a settle delay.
5. Captures screenshot to R2.
6. Walks the DOM for shadow-host custom elements (`<spideriq-form>`, `<spideriq-cmp>`, …).
7. Captures `console.error` calls.
8. Captures the request log (which scripts/images/etc. loaded; their statuses).
9. Returns the envelope.

## Param shape — exact (codified by Rule 59 / B.2 incident)

Get these wrong and the sidecar 400s through MCP as a 500 INTERNAL_ERROR — the false-FAIL trap:

| ✅ Use | ❌ Don't (will 422/500) |
|---|---|
| `page_url: "https://..."` | `url: "https://..."` |
| `viewport: "desktop"` or `viewport: "mobile"` (enum) | `viewport: { width: 1280, height: 800 }` (object — pre-Rule-59 shape) |

`tenant_id` (optional) for verified-custom-domain allowlist resolution — pass when the page lives on a custom domain that may need explicit allowlist match.

## The assertion rule (Rule 62 — verbatim)

> **When verifying a form is rendering correctly, ALWAYS assert on `dom.shadow_hosts.includes("spideriq-form")`. DO NOT assert on `body_text_preview` for cross-origin iframe contents — the iframe body is opaque to the parent page's DOM, so field labels and button text are NOT in `body_text_preview` even when the form is rendering correctly. Same applies to any custom-element shadow-host: assert on its tag name in `dom.shadow_hosts`, not on body text.**

(Codified in [`learnings_visual_check_assert_on_shadow_hosts.md`](https://github.com/SpiderIQ/SpiderIQ/blob/master/docs/services/catalog/LEARNINGS.md#rule-62) — the source incident.)

Applies to ANY Shadow-DOM-hosted custom element:
- Forms → `dom.shadow_hosts.includes("spideriq-form")`
- Components (Tier 2+) → `dom.shadow_hosts.includes("spideriq-cmp")`
- Future custom elements → assert on the host tag name

## Common verifications

### A standard content page

```
content_visual_check({
  page_url: "https://acme.com/about",
  viewport: "desktop"
})
# Assert:
# - success: true
# - screenshot_url not null
# - body_text_preview contains "About Acme" (the hero headline literal)
# - console_errors: []
# - timings.load_ms < 3000 (reasonable load time)
```

### A page with an embedded form (`kind='form'` Path B)

```
content_visual_check({
  page_url: "https://acme.com/contact",
  viewport: "desktop"
})
# Assert:
# - success: true
# - dom.shadow_hosts.includes("spideriq-form")   # the form mounted
# - DO NOT assert: body_text_preview contains "First name"  ← Shadow DOM opaque
# - console_errors: [] (no loader script errors)
```

### A standalone `/f/<flow_id>` URL

```
content_visual_check({
  page_url: "https://spideriq.ai/f/<flow_id>",
  viewport: "desktop"
})
# Assert:
# - success: true
# - dom.shadow_hosts.includes("spideriq-form")
# - body_text_preview probably empty or minimal (form is the page)
```

### A mobile-shaped verification

```
content_visual_check({
  page_url: "https://acme.com/",
  viewport: "mobile"
})
# Mobile viewport: 390x844 (iPhone 14 Pro)
# Useful for forms with theme.preset 'fullscreen-dark' (mobile collapses left/right media splits)
# Useful for CRO components: sys-bar-sticky-cta-mobile only renders below 768px
```

### A page with Tier 3 components (CDN deps)

```
content_visual_check({
  page_url: "https://acme.com/landing",
  viewport: "desktop"
})
# Assert:
# - dom.shadow_hosts.includes("spideriq-cmp")   # at least one Tier 2+ component mounted
# - console_errors: []  (no "gsap is not defined" — Tier 3 dep loading failures)
# - request_log shows scripts for declared dependencies loaded with status 200
```

If `request_log` shows a script with status 404 (e.g. `chart.js@4.4.6/...` 404), your component's `dependencies[]` key resolves to a stale CDN URL — fix in `content_cdn_allowlist`.

## Verifying after a deploy (the canonical check-after-publish pattern)

```
# Right after content_deploy_site_production confirms:
content_deploy_status()
# → { status: "live", version_id: 49, ... }

content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
# Confirm the new content is actually visible — silent-200 failure class.
```

The deploy returning 200 means "the request was accepted." It does NOT mean "every visitor sees the new bytes." Edge cache propagation, KV consistency lag, and Workers-for-Platforms cold starts can all create a window where the deploy completed but a fraction of visitors still see the old version. Visual-check confirms the FIRST-visitor experience.

## What the sidecar can't do

- **Click through forms.** Visual-check renders the page; it doesn't fill or submit. For interactive flows, you need an actual browser session ([`agent-browser`](https://github.com/SpiderIQ/SpiderIQ/blob/master/CLAUDE.md#browser-automation-agent-browser) or Playwright directly).
- **Auth-walled pages.** No cookie injection (yet). Public URLs only.
- **JavaScript-driven popups that fire on `mouseleave`.** The screenshot won't capture the popup (no cursor movement). Verify CRO popups manually in a browser.
- **Per-tenant analytics events.** The sidecar's console may show GTM/GA initialisation, but `gtag('event', ...)` calls don't get verified — those need a real visitor session.
- **Real-device fidelity.** Headless Chromium ≠ Safari, real iPhone, real Android. For pixel-perfect mobile or Safari-specific quirks, manual device testing.

## Cost / token budget

Visual-check costs:
- ~1-5s per call (sidecar startup + page load + screenshot).
- Screenshot upload to R2 (~50-300 KB per shot).
- Free at the SpiderPublish API surface; no per-call billing.

Tight-loop usage (e.g. visual-check after every component insert in a long authoring session): cheap; no rate limit currently enforced. Production-deploy verification: always run.

## Anti-patterns

1. **`url:` instead of `page_url:`.** The B.2 incident root cause (Rule 59) — Antigravity Verifier B was given the wrong param name in a spawn prompt; sidecar 400'd, MCP surfaced as 500 INTERNAL_ERROR. Always `page_url`.
2. **`viewport: { width: 1280, height: 800 }`.** Old shape. Now `viewport: "desktop"` / `"mobile"` enum.
3. **Asserting `body_text_preview` includes form field labels.** Cross-origin iframe / Shadow DOM = opaque. Use `dom.shadow_hosts`. Rule 62.
4. **Skipping visual-check after deploy because "the tests passed."** Tests verify code correctness; visual-check verifies feature correctness. Different layer.
5. **Visual-checking a page with auth.** The sidecar gets a login wall, not your page. Public URLs only OR add auth-bypass infrastructure (not yet shipped).
6. **Treating `success: true` as "the page is correct."** `success: true` means "Playwright loaded the page." You still need to assert on `dom.shadow_hosts` / `body_text_preview` / `console_errors` for the actual content checks.

## See also

- [`deploy-readiness.md`](deploy-readiness.md) — pre-deploy checklist (run BEFORE deploy; visual-check runs AFTER)
- [`link-audit.md`](link-audit.md) — audit internal links (different surface; complementary)
- [`audit-and-fix.md`](audit-and-fix.md) — end-to-end audit + fix flow
- [`audit-driven-edit.md`](audit-driven-edit.md) — iterative authoring with audit feedback
- [`../booking/embed-form.md`](../booking/embed-form.md) — where Rule 62 most often applies
- [`../booking/form-as-page-section.md`](../booking/form-as-page-section.md) — same rule for in-page form embeds
- [`../reference/booking-model.md`](../reference/booking-model.md) — Rule 62 verbatim + W13 case study
- catalog/LEARNINGS.md Rules 59 + 62 — source incidents (param-shape drift + shadow-host assertion)
