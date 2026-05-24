# recipes/booking/share-form-standalone

Share a `kind='form'` flow via the standalone `/f/<flow_id>` URL — QR code, social bio link, share-with-reviewer link, paste in an email. No iframe, no host page, no embed snippet — just a clean URL.

## When to use

- A tenant wants a QR code on physical signage that takes scanners straight to the form.
- They want a "link in bio" social-media URL (Instagram, TikTok, Twitter bio).
- They want to share a draft with a stakeholder for review WITHOUT publishing or embedding.
- They want a paste-into-email URL ("Click here to register: ...") for outbound campaigns.

If you want to embed inside another site → [`embed-form.md`](embed-form.md). If you want it inside a SpiderPublish page → [`form-as-page-section.md`](form-as-page-section.md).

## The 1-call path

```
form_preview_url({ flow_id: "flow_..." })
// → {
//   public_url: "https://spideriq.ai/f/<flow_id>",
//   dashboard_preview_path: "/dashboard/booking/flows/<flow_id>/preview",
//   note: "public_url is the standalone /f/{flow_id} page..."
// }
```

That's it. `public_url` is the canonical shareable URL.

## Honest framing — what URL you actually get

The URL `form_preview_url` returns is **`${apiUrl}/f/{flow_id}`** where `apiUrl` is the workspace's configured API host — usually `https://spideriq.ai`.

**This is NOT necessarily the tenant's primary verified custom domain.** If the tenant has `demo.spideriq.ai` registered + verified, `form_preview_url` still returns `https://spideriq.ai/f/<flow_id>`, not `https://demo.spideriq.ai/f/<flow_id>`. (Pure string composition; no API round-trip to fetch domain config. S4-B5 honesty fix 2026-05-20.)

### When to use `spideriq.ai/f/<id>` (the default)

- The form is for an internal/sales audience that doesn't need brand consistency.
- The tenant hasn't deployed a custom domain yet.
- You're sharing a draft for review.
- You want the link to keep working even if the tenant changes domains.

### When to compose the tenant-domain URL yourself

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

## Make it a QR code

The simplest QR pattern: just encode the standalone URL.

```bash
# Pick your favorite QR encoder — example with qrencode
qrencode -o form-qr.png "https://demo.spideriq.ai/f/$FLOW_ID"
```

For high-density physical signage (small QR codes), keep the URL short. The `spideriq.ai/f/<flow_id>` default is ~40 chars — fine for most printed materials. If you need shorter, set up a redirect via `content_redirects` ([`../content/landing-page.md`](../content/landing-page.md) doesn't cover redirects yet; see catalog/CLAUDE.md → "Public API Endpoints" → `/content/redirects/check`).

## Make it a social-bio link

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

## Share-with-reviewer (the draft flow)

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

See [`lock-form-for-review.md`](#) <!-- VERIFY: confirm this recipe is queued for v0.4.0+; if not yet authored, link drops. --> for the full lock semantics.

## After publish — verify the URL works

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

## Anti-patterns

1. **Composing `/book/<flow_id>` for the standalone URL.** Always `/f/<flow_id>`. The W13 incident's exact failure shape — `/book/<id>` 301s for `kind='booking'` but silent-fails for `kind='form'`. Rule 62. Use `form_preview_url`; never string-template.
2. **Sharing a draft URL.** `/f/<flow_id>` returns 404 until `status: 'active'`. Always `form_publish` before sharing externally.
3. **Using QR codes for forms with required URL params.** QRs are typically the URL alone (no `?utm_source=...`). If you need params on a QR, encode them in the QR; otherwise the form receives no hidden-field values.
4. **Asserting on `body_text_preview` for the standalone URL screenshot.** Shadow DOM = opaque to `body_text_preview`. Use `dom.shadow_hosts.includes("spideriq-form")`. Rule 62.
5. **Sharing the dashboard preview path with non-dashboard-users.** `/dashboard/booking/flows/<id>/preview` requires SpiderPublish login. Use `/f/<flow_id>` for external sharing.
6. **Putting hidden fields in the URL that aren't declared via `form_add_hidden_field`.** Stripped at form load. Always declare hidden fields BEFORE publish + sharing the URL.

## See also

- [`embed-form.md`](embed-form.md) — embed `kind='form'` flow OUTSIDE SpiderPublish (iframe, popup)
- [`form-as-page-section.md`](form-as-page-section.md) — embed INSIDE a SpiderPublish page
- [`build-form.md`](build-form.md) — author the form before sharing
- [`build-lead-gen-form.md`](build-lead-gen-form.md) — end-to-end pipeline
- [`clone-form-template.md`](clone-form-template.md) — one-shot clone from template
- [`../reference/booking-model.md`](../reference/booking-model.md) — `kind='form'` URL surface, S4-B5 honesty fix, Rule 62
- [`../content/custom-domain.md`](../content/custom-domain.md) — verify a custom domain for tenant-domain standalone URLs
- catalog/LEARNINGS.md Rule 62 + W13 — the source incident
