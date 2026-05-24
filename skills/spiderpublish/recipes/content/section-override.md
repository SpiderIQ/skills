# recipes/content/section-override

Replace a single section (header, footer, hero, blog listing) for this tenant only — without forking the entire theme. Plus the layout-preset shortcut for chrome-only changes.

## When to use

- A tenant wants a custom header (their logo, their nav style) but the rest of the theme is fine.
- You want to swap the footer's copyright + links without touching anything else.
- You're A/B-ing a new blog-listing layout without affecting individual blog posts.
- You want to switch the whole site to "no header, no footer" (a `blank` layout) for a campaign — without writing Liquid.

If you want to swap the ENTIRE theme → [`apply-theme.md`](apply-theme.md). If you want a brand-new Liquid template at a new path → use `template_upsert` directly. This recipe is for the named-section shortcut.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You know the section slug.** Common: `header`, `footer`, `hero`. Special: `blog-listing`, `blog-post`, `layout`, `head`. See "Section slugs" below.
3. **(Recommended) Read the current section.** Use `content_get_section_source` first — start from the existing source rather than from scratch.

## Section slugs

| Slug | Maps to | What it controls |
|---|---|---|
| `header` | `sections/header.liquid` | Site-wide top nav |
| `footer` | `sections/footer.liquid` | Site-wide footer |
| `hero`   | `sections/hero.liquid` | The default-theme hero section (if your pages use `{% section 'hero' %}`) |
| `blog-listing` | `templates/blog.liquid` | The `/blog` index page |
| `blog-post` | `templates/blog-post.liquid` | Individual `/blog/<slug>` chrome |
| `layout` | `layout/theme.liquid` | The outer HTML shell (head, body, where main content + sections render) |
| `head`   | `snippets/head.liquid` | The `<head>` contents (meta tags, favicon links, analytics snippets) |

Any other slug like `myfeature` maps to `sections/myfeature.liquid`. The section then must be referenced from a layout or template via `{% section 'myfeature' %}` to appear — otherwise it's stored but never rendered.

## The 3-call path

```
1. content_get_section_source({ section_slug })   — see what's currently rendering
2. content_override_section({ section_slug, liquid_source })   — write the new source
3. content_deploy_site_production                  — push to edge (~2-5s)
```

Plus visual-check at the end.

### 1. Get the current source

```
content_get_section_source({ section_slug: "header" })
// → {
//     section_slug: "header",
//     path: "sections/header.liquid",
//     origin: "client_override" | "theme_default",
//     source: "<liquid string OR null if origin is theme_default>"
//   }
```

If `origin: "client_override"` you've already got a custom version — `source` is the Liquid you'd be replacing. If `origin: "theme_default"`, the source is `null` and the response includes a `next_steps` hint pointing at the public theme repo (`github.com/SpiderIQ/SpiderPublish`) so you can grab the baseline as a starting point.

Don't try to fetch the default-theme source via this tool — it lives in the public repo, not in the API. Copy-paste it into your editor as the starting template.

### 2. Override

```
content_override_section({
  section_slug: "header",
  liquid_source: `
<header class="bg-surface border-b border-neutral-800 sticky top-0 z-10">
  <div class="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
    <a href="/" class="flex items-center gap-2">
      <img src="{{ settings.logo_url }}" alt="{{ settings.site_name }}" class="h-8" />
      <span class="font-semibold">{{ settings.site_name }}</span>
    </a>
    <nav class="flex gap-6">
      {% for item in navigation.header.items %}
        <a href="{{ item.url }}" target="{{ item.target | default: '_self' }}"
           class="text-neutral-300 hover:text-white">{{ item.label }}</a>
      {% endfor %}
    </nav>
  </div>
</header>`
})
// → { success: true, path: "sections/header.liquid", written: true }
```

The override is written to the tenant's per-tenant KV. **The site has NOT changed yet** — templates are cached at deploy time. Step 3 pushes the change live.

**Param-name compatibility** (the tool accepts either pair):
- Canonical: `{ section_slug, liquid_source }`
- Legacy: `{ section, liquid }`

Pass either. If both are supplied, the canonical names win. (Historical detail: there used to be two tools — they were merged in 2026-05-20 per Rule 64.)

**No dry_run/confirm gate** on `content_override_section` by default — it's opt-in via `template_upsert`'s gate fields (`dry_run`, `confirm_token`). For most tenant authoring, immediate writes are fine; the deploy step is the actual customer-facing change.

### 3. Deploy

```
content_deploy_readiness()
# → { ready: true, ... }

content_deploy_site_preview()
# → { preview_url: "https://preview-XXX.sites.spideriq.ai", confirm_token, ... }
# Eyeball the preview URL before confirming.

content_deploy_site_production({ confirm_token: "cft_..." })
# → { status: "live", version_id: 50 }
```

Site is live in ~2-5s.

## Layout presets — the chrome-only shortcut

If you don't want to write Liquid and you just want a different "shape" of chrome (header? footer? edge-to-edge?), use `content_apply_layout_preset`:

```
content_apply_layout_preset({ preset: "blank" })
// → { success: true, preset: "blank", description: "No header, no footer; full-page content", next_steps: "Deploy ..." }
```

Available presets (writes the corresponding `layout/theme.liquid`):

| Preset | Chrome shape | When to use |
|---|---|---|
| `default` | header + main + footer | Standard site |
| `blank` | no header, no footer | Landing pages where the page content owns the full canvas |
| `minimal` | footer only | Docs / legal — site attribution at bottom, no global nav |
| `landing` | header only | Marketing landing — CTA / form owns the lower viewport |
| `chromed` | header + footer; main is edge-to-edge (no padding) | Pages where content renders wide hero / full-bleed sections |

After applying, deploy. The layout preset only changes `layout/theme.liquid` — individual sections (header, footer) are still whatever you've got. So you can `content_apply_layout_preset({preset: "landing"})` AND have a custom `header` override; the layout switches but your header customization persists.

## Anti-patterns

1. **Customizing `templates/form.liquid` thinking it's the form-page chrome.** That file isn't read. Form pages at `/f/<flow_id>` render via `templates/forms-standalone.liquid` (kind='form') or `templates/booking-standalone.liquid` (kind='booking'), picked server-side by the `/f/` route from the flow's `kind`. To customize form-page chrome, override `forms-standalone` instead. Rule 65.
2. **Targeting `template == 'form'` in `layout/theme.liquid` Liquid conditionals.** Use `template == 'forms-standalone'` — the Liquid `template` variable mirrors the file basename, not a friendly synonym. Rule 65.
3. **Forgetting that the section override survives theme swaps.** `template_apply_theme` lists `templates_to_overwrite` in its dry_run — if your override is in that list, it'll be reset. Save + re-apply. See [`apply-theme.md`](apply-theme.md).
4. **Writing CSS in `<style>` tags inside section Liquid (vs the theme's `assets/styles.css` or a `{% style %}` tag).** Sections render in normal DOM, not Shadow DOM, so `<style>` works — but conventionally CSS lives in theme assets or settings.custom_head_code. Inline `<style>` in a section is fine but noisy.
5. **Deploying without `content_deploy_readiness` first.** Save the round-trip on a failed deploy.
6. **Section with no `{% section 'X' %}` reference in any layout / template.** The override is written but never rendered. Add the reference to a layout (or template) that uses the section.

## See also

- [`apply-theme.md`](apply-theme.md) — swap the entire theme (vs override one section)
- [`landing-page.md`](landing-page.md) — author pages that use the overridden sections
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the two-phase deploy after override
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `template_*` + `content_override_section` tools
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
- catalog/LEARNINGS.md Rules 64 + 65 — source incidents
