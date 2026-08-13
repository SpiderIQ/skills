# Design a docs site — the `docs` theme, the API reference, and the order that matters

> **REQUIRES — read before you plan.**
> **Package:** authoring + theming work in **every** universe. The reader-facing **query** tools (`search_docs`, `semantic_search_docs`, `ask_docs`, `get_doc`) are **kitchen-sink only**.
> **Tools:** `createDoc` `updateDoc` `publishDoc` `getDocsTree` `content_import_openapi` `content_import_markdown` `template_list_themes` `template_apply_theme` `template_get` `template_upsert` `updateSettings` (all universes)
> **Needs `deploySite`.** Templates, theme files and the deploy-time `_config.json` overlay live in per-tenant KV and only change on deploy — unlike content, which is live on publish.
> **Not sure which universe you are in?** SKILL.md → *Step 0*.

Writing doc pages is `content.md`. This file is about making them **look like a
docs product** — the `docs` theme, the structured API reference, and the four
shipped limitations you must design around.

## The one order you cannot get wrong

**Re-import the OpenAPI spec BEFORE applying the theme.**

The 3-column API reference renders from `content_docs.endpoints` (a jsonb column
added in migration 454). It is populated **only** by an OpenAPI import. A docs page
authored before that migration has `endpoints = NULL`, and applying the `docs` theme
renders the **prose fallback** — a plain article, not the reference. It returns 200.
Nothing errors. It just silently isn't the thing you promised.

```
1. content_import_openapi({ ... })      # idempotent — safe to re-run on existing docs
2. template_apply_theme({ theme: 'docs' })   # dry_run → confirm
3. deploySite()
```

Applying the theme first and importing after leaves you with a themed site whose
reference pages are prose. The fix is the same three steps in the right order.

## What the `docs` theme is

A second, self-contained theme (a full copy of `default` plus overrides — the
render-time fallback bundle is default-only, so it cannot be a thin diff). Themes
are directory-driven, so `template_apply_theme docs` turns any project into a docs
site and `template_list_themes` lists it automatically.

- `templates/doc.liquid` — 3-column layout (nav tree ∣ prose + params ∣ pinned
  tabbed code). It **branches on `doc.endpoints`**: structured cards when present,
  prose + auto-TOC when NULL.
- `snippets/docs-sidebar-node.liquid` — recurses (the default theme capped nesting
  at one level).
- `assets/docs.js` — progressive enhancement: globally-synced code tabs, copy
  buttons, JSON pretty-print, sidebar collapse/filter/mobile, TOC scroll-spy,
  inline `:::codegroup` → tabs.

### The structured endpoint shape

Each tag page holds one array of operations:

```
{ method, path, full_path, summary, description, params[],
  request_example, responses[],
  samples: { curl, python, javascript, go } }
```

The prose `body` is left unchanged by the import — it is the graceful fallback for
any renderer that does not consume `endpoints`.

## Four shipped limitations — design around them, don't report them as bugs

| Limitation | What you'll see | Work around it |
|---|---|---|
| **Hardcoded dark** | the theme uses `color:#fff` / `#a1a1aa`; on a light-brand tenant (`surface_color=#fff`) text is invisible | ship the docs project dark, or override the colours via `custom_head_scripts`. It is not palette-adaptive yet. |
| **Themes are per-CLIENT, not per-project** | `apply_theme docs` on a mixed client (marketing + docs) themes **everything** | don't apply the theme — **overlay** just the docs-route templates (`template_upsert` `templates/doc.liquid` + `templates/docs.liquid`) at client level, then deploy |
| **Assets cached immutable** | edits to `/_assets/theme.css` / `docs.js` don't propagate, and can't be purged on a tenant's own CF domain | inline the critical CSS into the template, or version the asset URL |
| **No chrome of its own** | a tenant whose `sections/header.liquid` is empty gets no header/footer on `/docs/*` | put the tenant's real header/footer component in `sections/`, **gated to the docs path**, so marketing pages don't double it |

The chrome gate:

```liquid
{% if request.path contains "/docs" %}{% component slug: "modern-header" %}{% endif %}
```

Note the **colon** in `{% component slug: "..." %}` — and remember published docs
render at a URL with **no `pages` row**, yet still carry site chrome. Chrome
components appearing in `/docs/*` HTML are expected, not stray injections.

## Restyling without touching a template

Most "make the docs match our brand" requests are a settings change. These inject
as CSS custom properties (`--primary`, `--surface`, `--body-text`, `--heading`)
into every page's `<head>`, **including `/docs/*`** — the default `doc.liquid` uses
them for link colour, borders and text:

```
updateSettings({ primary_color, surface_color, surface_elevated_color,
                 subtle_color, body_text_color, heading_color })
```

Then `custom_head_scripts` (a `<style>` block) for anything the palette can't reach.
A full template rewrite is the last resort, for **structural** changes only —
sidebar width, breadcrumbs.

## Authoring a custom docs template — the four rules

If you do write `templates/doc.liquid` yourself:

1. `{% layout 'layout/theme.liquid' %}` — the **full path**, not a bare name
2. `{% component slug %}` — never a raw `<spideriq-cmp>` tag
3. `{{ body | tiptap_html }}` — not `body_html`
4. `{% block content %}` — plus the per-template context vars

A missing template no longer 500s; the renderer answers *"Template error… did you
mean 'layout/theme.liquid'?"*. `strictFilters:false` means an unknown filter is a
pass-through, never a crash — which also means a typo'd filter fails **silently**.

## Reader-facing search / Ask-AI (kitchen sink, and Docs-Pro gated)

Every published docs site is also a hosted MCP server — `search_docs`,
`semantic_search_docs`, `ask_docs`, `get_doc`, scoped by `X-Content-Domain`. These
are **not** in `@spideriq/mcp-publish`.

The in-page **Try-it** and **Ask-AI** widgets relay through the tenant worker, so
when verifying them **probe a tenant domain** (`*.sites.spideriq.ai` or the custom
domain) — **not** `spideriq.ai`, whose `/api/*` is intercepted by the api-proxy and
returns 405. That 405 is a wrong-host artifact, not a broken relay.

`ask_docs` is metered and entitlement-gated: a **402** means the site owner is not
on Docs Pro or is over quota. That is billing, not a defect — surface it as such.

## The docs site is not done until…

| | |
|---|---|
| Content | doc pages **published** (draft docs don't render) |
| Tree | `getDocsTree` returns the hierarchy you intended — nesting beyond one level needs the `docs` theme's recursive sidebar |
| Reference | if it's an API reference: OpenAPI imported **before** the theme was applied, and `endpoints` is non-NULL |
| Chrome | header/footer present on `/docs/*`, gated so marketing doesn't double |
| Contrast | checked on the tenant's actual palette — the theme is hardcoded dark |
| Reachability | `/docs` **linked from navigation** |
| Live | **deployed** |

## Verify

```
deployStatus()
content_visual_check({ url: 'https://<tenant>/docs/<a-published-slug>' })
  → 3 columns present (not a single prose column) if you expected the reference
  → text is legible against the tenant's surface colour
```

A single prose column where you expected the 3-column reference means
`endpoints` is NULL → re-import the spec, re-apply, redeploy.

## See also

- `content.md` — creating docs, the tree, `importMarkdownDoc`
- `templates-deploy.md` — `template_apply_theme`, the two-phase deploy
- `integrations.md` — `content_import_openapi` in context
- `blog-page-design.md` — the same design problem for the blog
