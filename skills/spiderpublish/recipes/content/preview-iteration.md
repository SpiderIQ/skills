# recipes/preview-iteration

The safe component-edit loop. Lets you iterate on a component's HTML/CSS/JS without touching DB state or production, then promote once it's right.

## The 4-stage loop

```
  template_preview (pure — no DB write, no deploy)
          │
          ▼
  open preview URL in a browser
          │
          ▼
  happy with look?  ──NO──▶ edit source, back to template_preview
          │
          ▼
  content_create_component or content_update_component (dry_run → confirm_token)
          │
          ▼
  content_publish_component (dry_run → confirm_token)
          │
          ▼
  content_deploy_site_preview  →  verify  →  content_deploy_site_production
```

## Why this matters

Before `template_preview` existed, the only way to check a component's rendering was to create-publish-deploy it — full round-trip, impossible to back out cleanly. This recipe is the "dev environment" Antigravity's report asked for. It already exists — it just wasn't obvious.

## Step-by-step

1. **Draft locally** — write your HTML / CSS / JS / props_schema in your editor. No MCP calls yet.

2. **Preview** — call `template_preview`:
   ```json
   {
     "component": {
       "html_template": "<section>...</section>",
       "css": ":host { ... }",
       "js": "root.querySelector(...)",
       "props_schema": { "type": "object", "properties": { ... } }
     },
     "props": { "headline": "Test", "cta_url": "#" }
   }
   ```
   Returns: `{ preview_url, rendered_html, resolved_context }`. **No DB write. No KV write. No deploy.**

3. **Browser-check** — open `preview_url` in your own browser (or an agent-browser). Look for:
   - Layout collapsed / font wrong → CSS issue
   - Props not binding → props_schema mismatch
   - JS error in console → scoped-JS issue (probably `document.querySelector` instead of `root.querySelector`)

4. **Iterate** — edit, call `template_preview` again. Repeat until correct.

5. **Save draft** — `content_create_component` (or `content_update_component`). Destructive mutation, gated:
   ```
   content_create_component({...}, dry_run=true)   → returns confirm_token
   content_create_component({...}, confirm_token)  → actually creates
   ```

6. **Publish** — `content_publish_component(id, dry_run=true → confirm_token)`. Now it's referenceable from page blocks as `component_slug`.

7. **Deploy** — reference it in a page block, then:
   ```
   content_deploy_site_preview()              → preview_url + confirm_token
   # verify in browser
   content_deploy_site_production(confirm_token)
   ```

## What NOT to do

- **Don't skip `template_preview`.** Creating-publishing-deploying a broken component pollutes your version history and costs you a rollback cycle.
- **Don't reuse a `confirm_token`.** They're single-use. Call `dry_run=true` again to issue a fresh one.
- **Don't hold a `confirm_token` for more than 10 minutes.** They expire. Re-issue.

## See also

- [skills/templates-engine](../../templates-engine/SKILL.md) — full template tool surface including `template_preview`
- [skills/content-platform](../../content-platform/SKILL.md) — component CRUD
- CLAUDE.md in the repo root has the full Phase 11+12 preview→confirm flow
