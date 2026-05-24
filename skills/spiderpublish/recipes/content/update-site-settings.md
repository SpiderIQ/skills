# recipes/content/update-site-settings

Change site-wide settings — site name, SEO defaults, analytics, primary color, favicon, custom head/body scripts. The `extra='forbid'` surface — unknown keys 422 loudly.

## When to use

- A tenant just got provisioned and needs `site_name`, `favicon_url`, `logo_url`, `tagline` set.
- You're updating SEO defaults (`default_meta_title`, `default_meta_description`) site-wide.
- You're rolling out analytics (`analytics_id` for GA, or `custom_head_scripts` for Plausible/Posthog).
- You're updating the brand palette (`primary_color`, secondary, etc.).
- You need to set `extensions.feeds` (RSS/Atom/JSON Feed config) — see Wave 6.1.

For per-page SEO overrides (different `<title>` per page) → set `seo_title` / `seo_description` on `content_create_page` / `content_update_page`. For the visual theme as a whole → [`apply-theme.md`](apply-theme.md). For navigation menus → [`navigation.md`](navigation.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You know the canonical field names.** Settings is `extra='forbid'` post-Antigravity hardening — unknown keys 422. Use the documented field list below.

## The 2-call path

```
1. content_get_settings              — see current state
2. content_update_settings           — Phase 11+12 dry_run + confirm
```

No deploy step needed for settings-only changes EXCEPT when you change `custom_head_scripts` / `custom_body_scripts` (those need a deploy to push the new HTML to CF edge).

### 1. Get current settings

```
content_get_settings()
// → {
//   site_name:                  "Acme Inc",
//   tagline:                    "We build things",
//   default_meta_title:         "Acme Inc — engineering blog",
//   default_meta_description:   "Notes from the Acme engineering team",
//   primary_color:              "#1f6feb",
//   favicon_url:                "https://media.spideriq.ai/acme/favicon.ico",
//   logo_url:                   "https://media.spideriq.ai/acme/logo.svg",
//   analytics_id:               "G-XXXXXXXXXX",
//   custom_head_scripts:        "<script>...</script>",
//   custom_body_scripts:        "",
//   social_twitter:             "@acme",
//   social_github:              "https://github.com/acme",
//   extensions:                 { feeds: { rss_enabled: true, atom_enabled: false, ... } },
//   ...
// }
```

Read the existing values before mutating. Settings are merged (PATCH semantics on the `settings` dict) — you only pass keys you want to change, but you need to know what's there to avoid clobbering accidentally.

### 2. Update (REQUIRED `settings:` wrapper)

```
content_update_settings({
  settings: {                          # REQUIRED top-level wrapper — NOT `changes`, NOT flat
    site_name:                "Acme — engineering",
    default_meta_title:       "Acme engineering blog — scaling systems at 50M users",
    default_meta_description: "Notes on Postgres, Kafka, and how we ship.",
    primary_color:            "#0f172a",
    custom_head_scripts:      "<script defer data-domain=\"acme.com\" src=\"https://plausible.io/js/script.js\"></script>"
  }
})
# → defaults to dry_run=true (settings is a destructive op)
# → { dry_run: true, preview, confirm_token: "cft_..." }

content_update_settings({
  settings: { ...same... },
  confirm_token: "cft_..."
})
# → { applied: true, updated_keys: ["site_name", "default_meta_title", ...] }
```

**Critical:** the `settings:` wrapper is REQUIRED. Calls without it return 422 "Field required".

| ✅ Right | ❌ Wrong (422) |
|---|---|
| `{ settings: { site_name: "X" } }` | `{ site_name: "X" }` (flat — missing wrapper) |
| `{ settings: { site_name: "X" } }` | `{ changes: { site_name: "X" } }` (wrong key — `form_update` uses `changes:`, this uses `settings:`) |

This is THE most common error for agents coming from `form_update`. Save yourself a 422.

### Phase 11+12 — safe-default dry_run

`content_update_settings` defaults to **`dry_run=true`** (destructive — settings affect every page render). The first call returns a preview + `confirm_token`; second call with the token applies.

Read the preview's `before` and `after` blocks carefully. Settings can affect every page on the site — a typo in `primary_color` propagates everywhere. The preview is your safety net.

## The canonical field list (post-Antigravity `extra='forbid'`)

Settings is `extra='forbid'`. Unknown keys 422. The documented fields:

### Identity

| Field | Type | Notes |
|---|---|---|
| `site_name` | string | Site's display name. Renders in `<title>` (when per-page seo_title is absent), nav logo alt, OG tags. |
| `tagline` | string | One-line subtitle. Some themes render under `site_name`. |
| `logo_url` | string (must end `_url`) | Site logo. Renders in header nav typically. |
| `favicon_url` | string (must end `_url`) | Favicon (ICO/PNG). |

### SEO defaults (migration 244)

| Field | Type | Notes |
|---|---|---|
| `default_meta_title` | string, max 255 | Site-wide default `<title>` when a page doesn't set its own `seo_title`. |
| `default_meta_description` | string, max 500 | Site-wide default `<meta name="description">`. |
| `default_og_image_url` | string | Default OG image when a page doesn't set its own. |
| `canonical_url` | string | Canonical site URL (e.g. `https://acme.com`). Used in `<link rel="canonical">` builds. |

### Colors + theme tokens

| Field | Type | Notes |
|---|---|---|
| `primary_color` | hex string | Brand primary. Themes use it for buttons, links, focus rings. |
| `secondary_color` | hex string | Brand secondary. Some themes use it for accents. |
| `body_text_color` | hex string | Body copy color. |

### Analytics + scripts

| Field | Type | Notes |
|---|---|---|
| `analytics_id` | string | GA4 / Plausible / etc. ID. Renderer injects standard snippets when set. |
| `custom_head_scripts` | string (HTML) | Free-form HTML inserted in `<head>`. Use for Plausible script, Posthog, custom OG tags. **Requires deploy.** |
| `custom_body_scripts` | string (HTML) | Free-form HTML inserted right before `</body>`. Use for chat widgets, GTM. **Requires deploy.** |

### Social

| Field | Type | Notes |
|---|---|---|
| `social_twitter` | string | Twitter handle (e.g. `@acme`). |
| `social_github` | string | GitHub org URL. |
| `social_linkedin` | string | LinkedIn URL. |
| `social_facebook` | string | Facebook page URL. |

### Extensions

| Field | Type | Notes |
|---|---|---|
| `extensions.feeds.rss_enabled` | bool | Enable `/feed.xml`. Wave 6.1. |
| `extensions.feeds.atom_enabled` | bool | Enable `/atom.xml`. |
| `extensions.feeds.json_feed_enabled` | bool | Enable `/feed.json` (JSON Feed 1.1). |
| `extensions.sitemap.exclude_paths` | string[] | Paths to exclude from `/sitemap.xml`. |
| `extensions.robots.allow_paths` | string[] | Whitelist for `/robots.txt`. |

### Map provider keys (W3.3 / W5.2)

| Field | Notes |
|---|---|
| `map_providers.mapbox.browser_key_encrypted` | Fernet-encrypted Mapbox browser key. Use the dashboard's encrypted-key UI to set; never paste plaintext via MCP (it'd persist plaintext). |
| `map_providers.google.browser_key_encrypted` | Same for Google Maps. |

### Agent-shift digest (W6 — agent-native)

| Field | Notes |
|---|---|
| `agent_shift_digest_cadence` | `"daily" | "weekly" | "off"`. Frequency for the agent-shift digest emails (the "what did my agents change this week" summary). |
| `geo_toggle_enabled` | bool. Whether the `sys-geo-*` primitives auto-inject. |

**This list is non-exhaustive but covers the common surface.** Run `content_get_settings()` to see your tenant's complete current shape. If you try to set a field NOT in this list, you get a 422 — Antigravity 2026-05-22 hardening closed the silent-collusion trap where unknown keys persisted but didn't do anything.

## Common patterns

### Set up analytics on a new tenant

```
content_update_settings({
  settings: {
    analytics_id: "G-XXXXXXXXXX"
  }
})
# Renderer auto-injects standard GA4 snippet — no custom_head_scripts needed
```

For Plausible / Posthog / non-GA analytics:

```
content_update_settings({
  settings: {
    custom_head_scripts: "<script defer data-domain=\"acme.com\" src=\"https://plausible.io/js/script.js\"></script>"
  }
})
# Requires deploy to push the new <head> HTML to CF edge.
```

### Rebrand — change site name + logo + colors

```
content_update_settings({
  settings: {
    site_name:        "Acme — Reimagined",
    tagline:          "AI-native, customer-first",
    primary_color:    "#ec4899",
    secondary_color:  "#a855f7",
    logo_url:         "https://media.spideriq.ai/acme/logo-v2.svg",
    favicon_url:      "https://media.spideriq.ai/acme/favicon-v2.ico"
  }
})
```

Visual changes propagate to every page on next deploy (or next render if rendering live from API).

### Enable RSS feed

```
content_update_settings({
  settings: {
    extensions: {
      feeds: {
        rss_enabled: true,
        atom_enabled: true,
        json_feed_enabled: false
      }
    }
  }
})
# After confirm, /feed.xml + /atom.xml are live for the tenant.
```

## Deploy after settings change?

- **No deploy needed** for: `site_name`, `tagline`, `logo_url`, `favicon_url`, `analytics_id`, `default_meta_*`, `primary_color`, `social_*`, `extensions.*`. The renderer reads settings live from the API per request.
- **Deploy required** for: `custom_head_scripts`, `custom_body_scripts`. These bake into the rendered HTML at deploy time; live changes don't propagate until next deploy.

For mixed changes (some live, some bake-time), do one `content_update_settings` covering all of them, then `content_deploy_site_production` to push the head/body script changes. The live-read fields update immediately; the baked-in ones update on deploy.

## Verify

```
# Read back
content_get_settings()
# Confirm the new values landed.

# Visual check
content_visual_check({ page_url: "https://<tenant>/", viewport: "desktop" })
# For visual changes (primary_color, logo): check screenshot.
# For SEO defaults: view-source on the page, check <title> + <meta>.
# For analytics: check the page source for the script injection.
```

## Anti-patterns

1. **Missing the `settings:` wrapper.** `{ site_name: "X" }` → 422 "Field required". Use `{ settings: { site_name: "X" } }`. The most-common agent error coming from `form_update` (which uses `changes:`).
2. **Setting unknown keys (`extra='forbid'`).** Unknown keys 422. Old behaviour silently persisted them with no effect — Antigravity 2026-05-22 fix closed this. Stick to the documented field list.
3. **Pasting plaintext map provider keys.** Use the dashboard's encrypted-key UI — MCP doesn't have a "set encrypted" tool today. Plaintext via MCP would persist plaintext.
4. **Setting `custom_head_scripts` to a multi-line `<script>` with embedded `</script>` tags inside literals.** Browser parses early. Escape: `<\/script>`.
5. **Forgetting to deploy after changing `custom_head_scripts` / `custom_body_scripts`.** Those bake at deploy time. Other settings update live.
6. **Confusing `default_meta_title` (site-wide default) with `seo_title` (per-page).** Set `default_meta_title` in settings; set `seo_title` on `content_create_page` / `content_update_page`.

## See also

- [`apply-theme.md`](apply-theme.md) — swap the whole theme (different from settings — templates, not data)
- [`navigation.md`](navigation.md) — menu config (separate from settings)
- [`custom-domain.md`](custom-domain.md) — domain config (separate again)
- [`landing-page.md`](landing-page.md) — per-page SEO overrides
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — gate flavour (safe-default dry_run=true)
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `content_*_settings` tool catalog
- catalog/CLAUDE.md → "Public API Endpoints" → `/content/settings` route
