# reference/tool-surface

CLI vs MCP map, which MCP package to install, the 128-tool ceiling story, the three discovery endpoints, and the "prefer one-shot tools over multi-step choreography" rule. Read once per session.

## TL;DR

- **Pick by runtime ceiling.** `@spideriq/mcp-publish` is 87 atomic tools (content + media + booking minus `form_*`). `@spideriq/mcp` is 134+ kitchen-sink. If your host (Antigravity, Claude Desktop) has a 128-tool ceiling, use mcp-publish. If your host (Claude Code, Cursor, Codex) doesn't, use mcp.
- **Three discovery endpoints** for live capability scan. Call once per session, cache.
- **Prefer one-shot tools** (`content_get_component_by_slug` over paginating `list_components`; `form_create_from_template({ auto_create: true })` over `form_create` + N×`form_add_field`) — saves tokens AND avoids partial-state bugs.

## The MCP package picker

| Package | Tools | When to use |
|---|---|---|
| `@spideriq/mcp-publish` | 87 atomic (publish/content + media + booking minus `form_*`) | Antigravity, Claude Desktop, ChatGPT MCP-bridge clients — anything with a hard tool-list ceiling around 128. Atomic = each tool does one thing; lower descriptive overhead. |
| `@spideriq/mcp` | 134+ kitchen-sink (everything above + `form_*` + mcp-mail + mcp-gate + mcp-leads + mcp-admin) | Claude Code, Cursor, Codex — IDE-class hosts without a ceiling. One MCP entry covers every SpiderPublish/Forms/Mail/Gate surface. |

If you're not sure: `@spideriq/mcp` covers more, install that. If you hit "tools/list response too large" errors or your client truncates the schema, switch to `@spideriq/mcp-publish`.

### Installation

```bash
# mcp-publish (atomic 87)
npx @spideriq/mcp-publish@latest

# mcp (kitchen-sink 134+)
npx @spideriq/mcp@latest
```

Both pull from `https://npm.spideriq.ai` (Verdaccio mirror). Auth: configure `.mcp.json` with the standard MCP-server entry:

```json
{
  "mcpServers": {
    "spideriq": {
      "command": "npx",
      "args": ["@spideriq/mcp"],
      "env": { "SPIDERIQ_FORMAT": "yaml" }
    }
  }
}
```

After install, run `request_access` → `check_access_status` (PAT flow) before any tenant-scoped call. See [`../_shared/auth.md`](../_shared/auth.md).

## The 128-tool ceiling story (why the split exists)

Antigravity, Claude Desktop, and a handful of other hosts cap tool-list payload size at roughly 128 tools — beyond that, the host either truncates silently or fails the entire MCP handshake. The full SpiderIQ surface (publish + mail + gate + leads + admin) ships ~134 tools. To stay under the ceiling for those hosts, the `publish/` slice is packaged separately as `@spideriq/mcp-publish` with the `form_*` family carved out (forms are a separate enough domain that they live in `mcp` only).

If you want forms on a 128-tool host: install `@spideriq/mcp` and accept the host may not render every tool, OR install `@spideriq/mcp-publish` and call form endpoints directly via curl/CLI.

(The split is also discussed at: catalog/CLAUDE.md → "Tool surface — pointer only.")

## CLI vs MCP — when to reach for which

| Tool | When | Auth |
|---|---|---|
| **MCP** (`@spideriq/mcp*`) | Agentic flows — IDE assistant authoring content, multi-tool composition, anything where the agent decides what to call next | PAT auto-loaded from `~/.spideriq/credentials.json` (set by `spideriq auth request`) |
| **CLI** (`@spideriq/cli`, `spideriq`) | Scripted pipelines (CI, ansible, bash runbooks), interactive human ops (`spideriq content pages list`), one-shot diagnostics | PAT auto-loaded; interactive prompts gate destructive ops |
| **HTTP** (curl / Python) | Edge cases — debugging an envelope shape, hitting an admin-only route, writing a smoke-test script | Bearer `cli_id:api_key:api_secret` header |

CLI commands map 1:1 to MCP tools where possible (`spideriq content pages create` ↔ `content_create_page`). The CLI's interactive prompts implement the same dry_run/confirm flow MCP tools use — they're not a separate gate.

## The three discovery endpoints

Call once per session and cache. Each saves 1-3 round-trips per recipe.

| Endpoint | Returns | When to call |
|---|---|---|
| `GET /api/v1/content/help` | ~2,867-token YAML reference: block types, 14 Liquid filters, 4 custom tags, template structure, data sources, agent-natural alias hints | First call in any SpiderPublish-related conversation. Sets the schema vocabulary. |
| `GET /api/v1/content/help/block-fields` | Per-block-type field maps + alias map + anti-patterns | Before composing any non-component block (catches the silent-blank trap from [`block-types.md`](block-types.md)). |
| `GET /api/v1/dashboard/idap/merge-tags?page_id={id}` | Merge-tag vocabulary for dynamic landing pages (`{{firstname}}`, `{{company_name}}`, etc.) | Before authoring a `template: dynamic_list` / `dynamic_item` page that uses merge tags. |

All three are public reads — no auth required. Hit them via curl in any session:

```bash
curl -s https://spideriq.ai/api/v1/content/help | head -50
curl -s https://spideriq.ai/api/v1/content/help/block-fields | jq 'keys'
```

Or via MCP tool wrappers:

```
template_get_help()                             # endpoint 1 + recipe index + site context
template_inspect_block_fields({ block_type })    # endpoint 2
content_get_variables()                          # adjacent — merge tag vocab without page binding
```

`template_get_help` wraps endpoint 1 plus injects `site_context` (the current `spideriq.json` binding) and `recipes` (this skill bundle's recipe index). Use it as the first call in any SpiderPublish session — it tells you which tenant you're on and which recipes apply.

## "Prefer one-shot tools over multi-step choreography"

A recurring SpiderPublish pattern: there's a low-level "compose your own" tool AND a high-level "do the common thing" tool. **Always check for the one-shot first.** It saves tokens, surfaces validation server-side in one place, and avoids partial-state bugs where step 3 of 5 succeeds and step 4 fails.

| Goal | ❌ Choreography | ✅ One-shot |
|---|---|---|
| Find a component by slug | `content_list_components({ limit: 50 })` + filter | `content_get_component_by_slug({ slug })` |
| Clone a form template AND get a usable form | `form_create_from_template({ slug })` → reads fields → `form_create({ fields })` | `form_create_from_template({ slug, auto_create: true })` |
| Update component AND repoint every consuming page | `content_update_component` + N × `content_update_page` | `component_update_and_propagate` (atomic; one confirm_token) |
| Roll back a component | Manually clone old version body → publish | `component_rollback({ slug, target_version })` |
| Apply a curated starter site | Iterate `content_list_site_templates` → read each `source_page_slugs[]` → manually clone | `content_apply_site_template({ slug })` |
| Compose a form embed snippet | String-template `<div data-spiderflow-flow="…">` by hand | `form_get_embed_snippet({ flow_id, mode })` |
| Get a form's public URL | Compose `https://<tenant>/f/<flow_id>` | `form_preview_url({ flow_id })` (returns the canonical URL — see [`booking-model.md`](booking-model.md)) |

The choreography path is the historical record — most one-shots were added in 2026 after agent reports surfaced the choreography pain. When you find yourself reasoning through "OK first call A, then B, then C…" — pause and grep for a higher-level tool first.

## Tool families (the 153-tool map at a glance)

Each row is a domain. Counts roughly reflect `packages/mcp-tools/src/publish/*.ts`.

| Family | Files | Tools | Purpose |
|---|---|---|---|
| Content (pages, posts, docs, settings, domains, navigation, components) | `content.ts` (1927 LOC) | ~60 | Core CMS surface |
| Forms (kind='form' booking_flows) | `forms.ts` (1848 LOC) | 27 | Conversational form authoring + templates + embed + validation |
| Templates + deploy | `templates.ts` (630 LOC) | ~22 | Liquid CRUD, themes, deploy pipeline, readiness probe |
| Section overrides | `section_overrides.ts` (360 LOC) | 3 | One-call sectional swaps (header, footer, layout presets) |
| Marketplace (browse + insert + agent_meta) | `marketplace.ts` (615 LOC) | ~12 | Section inserts, bg-videos, agent-meta authoring |
| Site templates | `site_templates.ts` (135 LOC) | 3 | Curated starter sites — `list_site_templates` + `get` + `apply` |
| Directory (SEO category/listing) | `directory.ts` (299 LOC) | 10 | Programmatic SEO |
| Duplicate (page/block/post/doc) | `duplicate.ts` (177 LOC) | 4 | Cheap deep-copies |
| Component propagation | `component_propagation.ts` (210 LOC) | 2 | The two one-shots: `update_and_propagate`, `rollback` |
| Audit + visual-check | `audit.ts` (47 LOC) + `content.ts` (visual-check) | 2 | Link audit + Playwright sidecar |
| Playbook | `playbook.ts` (56 LOC) | 1 | NL-intent → recipe lookup |
| Scroll sequence | `scroll_sequence.ts` (179 LOC) | 1 | Video → frame extraction + page block |
| Local upload | `local_upload.ts` (333 LOC) | 2 | `upload_local_file` / `upload_local_directory` to SpiderMedia R2 |
| Media (SpiderMedia URL ops) | `media.ts` (166 LOC) | 6 | Import + list + delete + video status |

Plus three more packages in the kitchen-sink `@spideriq/mcp` build: `mcp-mail` (~7), `mcp-gate` (~5), `mcp-leads` (~3), `mcp-admin` (~6).

## Discoverability rule — name your intent BEFORE you list

When you're not sure which tool covers your intent, **don't** list and grep. Use the playbook tool:

```
content_get_playbook({ intent: "add a contact form to the home page" })
# → { matches: [ { score: 3, goal: "...", recipe: "recipes/booking/build-form.md" }, ... ] }
```

Or the shipped script (~50 tokens, no MCP call):

```bash
./scripts/find-tool-for-intent.sh "add a contact form to the home page"
```

Both return top-3 candidate recipes by keyword overlap, each pointing at the tool sequence. Cheaper than loading `template_get_help` for a quick lookup.

## Anti-patterns

- **Loading the entire tool list to "find the right one."** Use `find-tool-for-intent.sh` or `content_get_playbook` — most lookups are 50 tokens, not 5000.
- **Mixing CLI + MCP in the same session without flushing tenant binding.** Both read `~/.spideriq/credentials.json` and walk-up `spideriq.json`. If you `spideriq use cli_A` then ask the MCP agent to do something, they're both on `cli_A` — confirm with `./scripts/verify-tenant-scope.sh`.
- **Calling `content_list_components` with `limit: 500` to "see everything."** Components list is paginated; large limits return slow + truncated. Use `content_get_component_by_slug({ slug })` if you know the slug; `category` + `status` filters if you don't.
- **Authoring a form via `form_create` + N × `form_add_field` when a template covers 80% of the shape.** Use `form_create_from_template({ slug, auto_create: true })` first; mutate from there.
- **Composing URLs by hand for forms (`/f/<id>` or `/book/<id>`).** Use `form_preview_url` and `form_get_embed_snippet` — they encode the right URL shape and update if the convention changes. The W13 incident (8 broken iframes in production) came from manual `/book/<id>` URL composition for a `kind='form'` flow.

## See also

- [`deploy-protocol.md`](deploy-protocol.md) — gate flavours per tool (opt-in vs safe-default)
- [`block-types.md`](block-types.md) — block_type + data.* map (referenced by every content tool)
- [`booking-model.md`](booking-model.md) — `form_*` tool semantics + URL surface
- [`../_shared/auth.md`](../_shared/auth.md) — PAT auth + tenant binding
- [`../../../scripts/README.md`](../../../scripts/README.md) — `find-tool-for-intent.sh` + the rationale
- catalog/CLAUDE.md → "Tool surface" — internal canonical
