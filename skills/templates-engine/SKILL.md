---
name: templates-engine
version: "1.0.0"
description: >
  Liquid template engine for content sites — manage custom templates, themes, config, preview rendering, and deploy to Cloudflare edge.

category: content
requires_auth: true
requires_brand: true
triggers:
  - template
  - theme
  - liquid
  - deploy site
  - content deploy
client: templates-engine
client_version: "1.0.0"
metadata:
  openclaw:
    primaryEnv: OPVS_PAT
---

# Templates Engine

## When to Use

<!-- TODO: Add decision guidance — when should the agent reach for this skill? -->

## Key Rules

<!-- TODO: Add business rules, constraints, lifecycle rules -->

## Anti-Patterns

<!-- TODO: Add things the agent should NOT do -->

## Available Methods

All methods are available via `templates-engine_*` tool calls:

- `templates-engine_listTemplates()` — List all custom templates for the site.
- `templates-engine_getTemplate(path)` — Get template source code by path (e.g. "pages/home.liquid").
- `templates-engine_upsertTemplate(path, content, theme?)` — Create or update a custom template. Provide Liquid source code. Overrides the theme default for this path.
- `templates-engine_deleteTemplate(path)` — Delete a custom template (reverts to theme default).
- `templates-engine_listThemes()` — List available pre-built themes.
- `templates-engine_applyTheme(theme)` — Apply a theme to the content site.
- `templates-engine_getConfig()` — Get template configuration (theme, routes, settings, data_sources).
- `templates-engine_updateConfig(theme?, routes?, settings?, data_sources?)` — Update template configuration — theme, routes, settings, or data_sources.
- `templates-engine_preview(template_path, data?)` — Render a template with mock data. Returns HTML preview. Use for testing templates before deploying.
- `templates-engine_deploySite()` — Deploy content site to Cloudflare edge. Renders all templates, uploads static assets, and publishes to the CDN.
- `templates-engine_getDeployStatus()` — Get status of the latest deployment.
- `templates-engine_getDeployHistory(limit?)` — List recent deployments with status and timing.
