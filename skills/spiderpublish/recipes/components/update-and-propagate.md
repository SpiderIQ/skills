# recipes/component-update-and-propagate

Update a component's HTML/CSS/props AND roll the new version across every consuming page — **one tool call**.

## The one-shot path (preferred, v2.88.0+)

```
component_update_and_propagate(
  slug = "hero",
  css = <new css string>,
  dry_run = true
)
```

Returns a preview envelope with `affected_pages: [...]` and a `confirm_token`. Re-run with the token to apply:

```
component_update_and_propagate(
  slug = "hero",
  css = <same new css>,
  confirm_token = "cft_..."
)
```

The server does all of this in one transaction:

1. Fetches the current `hero` component, auto-bumps semver (default `patch`: `1.4.2` → `1.4.3`).
2. Inserts a new **published** row with the bumped version + your new content.
3. Queries every page whose `blocks` reference `component_slug: "hero"`.
4. UPDATEs each page's `blocks` JSONB to pin the new version on every matching block.
5. Returns `{component, affected_pages, unaffected_pages}`.

## No tenant deploy needed

Block-level page content renders live via the content API on the next request. Only run `content_deploy_site_preview` + `content_deploy_site_production` if you ALSO changed templates, theme, or config.

## Common variants

### Staged rollout — update component everywhere, repoint only the home page

```
component_update_and_propagate(
  slug="hero",
  css=<new css>,
  pages=["home"],
  dry_run=true
)
```

Other pages keep their old version pin. Once you've verified the home page, call again with `pages` omitted to roll to all.

### Minor / major version bump

```
component_update_and_propagate(
  slug="hero",
  props_schema=<new schema>,
  bump="minor",
  dry_run=true
)
```

Use `minor` for backward-compatible prop additions, `major` for contract breaks (default is `patch`).

### Update multiple fields at once

```
component_update_and_propagate(
  slug="hero",
  html_template=<new html>,
  css=<new css>,
  props_schema=<new schema>,
  dependencies=["gsap"],
  dry_run=true
)
```

## Why not `component_update` + N `content_update_page` calls?

The legacy path:
1. PATCH `/components/{id}` with manually-bumped version
2. GET `/pages?has_component=hero` (doesn't exist; you paginate and filter client-side)
3. PATCH `/pages/{id}` per page, modifying its `blocks` JSONB
4. Each PATCH goes through its own Lock 4 confirm_token flow

`component_update_and_propagate` bundles this into one transaction with one confirm_token. Half-applied state is impossible — either everything lands or nothing does.

## Files in this skill

- `SKILL.md` — this file (human-readable recipe)
- `schema.yaml` — Tier 2 tool-sequence for MCP consumers

## See also

- [recipes/component-rollback](../component-rollback/SKILL.md) — undo a bad update using the same one-shot pattern
- [LEARNINGS.md → Component editing](../../../LEARNINGS.md#component-editing) — gotchas
- [SpiderIQ `/content/help` → `update_component_site_wide`](https://spideriq.ai/api/v1/content/help?format=yaml) — the canonical agent-facing description
