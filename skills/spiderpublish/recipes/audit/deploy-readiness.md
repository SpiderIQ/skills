# recipes/audit/deploy-readiness

Pre-flight checklist BEFORE running a production deploy — confirms settings/domain/templates/pages are configured + no blocking issues. Cheap probe; saves a failed deploy + a spent confirm_token.

## When to use

- BEFORE every `content_deploy_site_production` on a tenant you're not 100% sure is configured.
- After applying a site template + customizing — confirm the customizations didn't break readiness.
- After a major refactor (new domain, theme swap, settings change) — confirm everything still passes.
- As a daily / weekly health check via CI for production tenants.

For POST-deploy verification → [`visual-check-a-page.md`](visual-check-a-page.md). For an internal-link audit (404s in nav, dead links) → [`link-audit.md`](link-audit.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You're about to deploy** (otherwise this is just a status check — fine, but the recipe is sequenced for deploy use).

## The 1-call path

```
content_deploy_readiness()
// → {
//   ready: true,
//   checks: [
//     { item: "site_name",                   status: "pass" },
//     { item: "primary_domain",              status: "pass",  value: "acme.com" },
//     { item: "domain_verified",             status: "pass" },
//     { item: "home_page_published",         status: "pass",  value: "home" },
//     { item: "navigation_header",           status: "pass",  items_count: 5 },
//     { item: "templates_complete",          status: "pass" },
//     { item: "no_unresolved_block_warnings", status: "warn", warnings_count: 2 }
//   ],
//   blocking: [],
//   warnings: [
//     { item: "blog_post_count",  message: "0 published posts; /blog will be empty" },
//     { item: "no_unresolved_block_warnings", message: "2 pages have render.unused_field_in_default_theme warnings" }
//   ]
// }
```

The shape: `ready` is `true` if `blocking` is empty; deploy will refuse otherwise.

## The checklist (what gets verified)

These are the items the readiness probe walks. Exact list may drift as the catalog evolves; treat as canonical-ish.

### Settings + identity

| Item | Pass when | Fail when |
|---|---|---|
| `site_name` | `content_settings.site_name` is non-empty | Empty / null (defaults render as `<title>untitled</title>`) |
| `default_meta_title` | Set OR every page has its own `seo_title` | Neither (SEO is degraded) |
| `favicon_url` | Set | Not set (browsers show generic favicon) |
| `logo_url` | Set OR theme doesn't reference it | Theme uses `{{ settings.logo_url }}` but it's null |

### Domain

| Item | Pass when | Fail when |
|---|---|---|
| `primary_domain` | At least one verified domain set as primary | No primary set (URLs fall back to `<tenant>.sites.spideriq.ai`) |
| `domain_verified` | Primary domain has `verified_at` non-null | Primary is added but not verified — visitors see CF errors |

### Content

| Item | Pass when | Fail when |
|---|---|---|
| `home_page_published` | A page with `slug: "home"` exists + is published | Visitors hit `/` and see 404 |
| `at_least_one_published_page` | ≥1 published page | Empty tenant — nothing to render |
| `no_orphan_published_pages` | Every published page is reachable via nav OR is the home | Pages exist but no nav link → invisible to visitors |
| `nav_targets_exist` | Every nav item's `url` resolves to a real page / route | Dead links in nav |

### Templates

| Item | Pass when | Fail when |
|---|---|---|
| `templates_complete` | Theme has the minimum templates (`layout/theme.liquid`, `templates/page.liquid`, etc.) | Custom theme is missing a required template |
| `no_invalid_overrides` | All `content_templates` entries parse as valid Liquid | A `template_upsert` left a syntax error |

### Page-level audit aggregation

| Item | Pass when | Warn when |
|---|---|---|
| `no_unresolved_block_warnings` | No published page has open `render.unused_field_in_default_theme` warnings | One or more pages have silent-blank-section warnings |
| `no_locked_pages` | No published page is `is_locked: true` | A locked page (mid-review) is about to deploy |

### Booking / forms

| Item | Pass when | Warn when |
|---|---|---|
| `no_orphan_form_embeds` | Every form embed in any page's blocks references an `active` form | A page embeds a `draft` form → renders unavailable |

The set may grow over time — read the `checks: []` array to see what fired.

## The flow — readiness → deploy → visual-check

```
# 1. Readiness — must show ready: true (or you fix blocking items)
content_deploy_readiness()
# → { ready: true, blocking: [], warnings: [...] }

# 2. Review warnings (NOT blocking, but worth knowing)
# - "0 published posts; /blog will be empty" → maybe defer launching /blog
# - "2 pages have render.unused_field_in_default_theme warnings" → consider fixing first

# 3. Deploy preview
content_deploy_site_preview()
# → { preview_url: "https://preview-XXX.sites.spideriq.ai", confirm_token, ... }
# Eyeball the preview URL.

# 4. Confirm production
content_deploy_site_production({ confirm_token })
# → { status: "live", version_id: 50 }

# 5. Visual-check (Rule 62)
content_visual_check({ page_url: "https://<primary>/", viewport: "desktop" })
```

The full sequence on a confident deploy: readiness → preview → production → visual-check. ~10s total wall-clock; saves a wrong-deploy + agent confusion.

## When readiness says `ready: false`

`blocking: [...]` carries the items that MUST be fixed. Common shapes + fixes:

| Blocking | Fix |
|---|---|
| `primary_domain: not_set` | `content_add_domain` → `content_verify_domain` → `content_set_primary_domain`. See [`../content/custom-domain.md`](../content/custom-domain.md). |
| `domain_verified: false` | `content_verify_domain` (and confirm `success: true`). Customer DNS may not have propagated yet. |
| `home_page_published: missing` | `content_create_page({ slug: "home", title: "..." })` → `content_publish_page`. |
| `site_name: empty` | `content_update_settings({ settings: { site_name: "..." } })`. See [`../content/update-site-settings.md`](../content/update-site-settings.md). |
| `nav_targets_exist: dead_link` | Fix the nav item URL via `content_update_navigation`. See [`../content/navigation.md`](../content/navigation.md). |
| `no_orphan_form_embeds: <flow_id> not active` | `form_publish` the orphan flow. |

Don't proceed to deploy with blocking items — `content_deploy_site_*` will refuse with the same shape envelope.

## When readiness says `ready: true` but `warnings: [...]`

Warnings DON'T block the deploy — agent's choice whether to address them first. Common cases:

- **`/blog will be empty`**: the dynamic-list page exists but no published posts. Deploy is fine; `/blog` renders "No posts yet" until you publish one.
- **`render.unused_field_in_default_theme` on N pages**: silent-blank-section risk; pages publish, but some sections are blank. Run `content_get_page({ audit_level: "warnings" })` per page to fix.
- **Orphan published pages (in store but not in nav)**: visitors can't navigate to them. Fine for landing pages designed for paid traffic; fix if expected to be discoverable.

Decide case-by-case. The default agent posture: fix warnings BEFORE deploy on production tenants; ignore on dev / staging.

## Run as a daily / weekly health check

```bash
# Cron / CI / scheduled job — fail loudly if readiness drifts
RES=$(curl -s -H "Authorization: Bearer $CLI_ID:$KEY:$SECRET" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PID/content/deploy-readiness")

READY=$(echo "$RES" | jq -r '.ready')
if [ "$READY" != "true" ]; then
  BLOCKING=$(echo "$RES" | jq -c '.blocking')
  echo "Tenant $PID deploy-readiness FAIL: $BLOCKING"
  exit 1
fi
```

Add as a cron on the SpiderIQ ops side for production tenants. Surfaces "settings drifted" / "domain de-verified" / "nav has dead links" before the next deploy attempt.

## Anti-patterns

1. **Skipping readiness, jumping straight to `content_deploy_site_*`.** Deploy refuses with the same blocking envelope. Save a round-trip.
2. **Treating warnings as blocking.** They're advisory. Fix when worth it; ignore otherwise. Production tenants: usually fix. Dev tenants: skip.
3. **Re-running readiness without fixing the blocking items.** It'll return the same shape. Fix → re-check.
4. **Running readiness on a non-existent tenant.** Returns 404 / mismatch error (Lock 1/3 fires). Verify scope first.
5. **Assuming readiness covers visual fidelity.** It checks SETTINGS / DOMAIN / CONTENT — not "the hero looks right." For that, [`visual-check-a-page.md`](visual-check-a-page.md) post-deploy.

## See also

- [`visual-check-a-page.md`](visual-check-a-page.md) — POST-deploy verification (this recipe is PRE-deploy)
- [`link-audit.md`](link-audit.md) — internal link audit (different surface; readiness covers nav broadly)
- [`audit-and-fix.md`](audit-and-fix.md) — end-to-end audit + fix
- [`audit-driven-edit.md`](audit-driven-edit.md) — iterative authoring with audit feedback
- [`../content/custom-domain.md`](../content/custom-domain.md) — fix `primary_domain` / `domain_verified` blocking
- [`../content/update-site-settings.md`](../content/update-site-settings.md) — fix settings blocking
- [`../content/navigation.md`](../content/navigation.md) — fix nav blocking
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the two-phase deploy that readiness gates
