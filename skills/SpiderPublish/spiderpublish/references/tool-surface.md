# reference/tool-surface

> **REQUIRES — read before you plan.**
> **Package:** n/a — no MCP tools of its own.
> **Tools:** — meta: CLI vs MCP vs HTTP, the four MCP configurations, discovery endpoints
> Read this if Step 0 in SKILL.md left you unsure which universe you are in.
> **Not sure which universe you are in?** SKILL.md → *Step 0*.


CLI vs MCP map, which MCP package to install, the 128-tool ceiling story, the three discovery endpoints, and the "prefer one-shot tools over multi-step choreography" rule.

## TL;DR

- **Use facade mode.** `@spideriq/mcp` with `SPIDERIQ_MCP_MODE=facade` lists **9** tools and makes all **431** reachable through `tool_search` → `tool_help` → `tool_call`. It is the only configuration that puts the full surface in front of a size-limited client.
- **Everything else trades away capability.** See the picker below — and note that the unfiltered kitchen sink does not merely truncate, it makes some clients **silently abort the ingest**.
- **Three discovery endpoints** for live capability scan. Call once per session, cache.
- **Prefer one-shot tools** (`content_get_component_by_slug` over paginating `list_components`; `form_create_from_template({ auto_create: true })` over `form_create` + N×`form_add_field`) — saves tokens AND avoids partial-state bugs.

## The MCP package picker

| Configuration | Listed | Reaches | Verdict |
|---|---|---|---|
| `@spideriq/mcp` + `SPIDERIQ_MCP_MODE=facade` | **9** | **all 431** via `tool_search` | ✅ **use this** |
| `@spideriq/mcp` (unfiltered) | 431 | all 431 — **if the client accepts the list** | ⚠️ Antigravity **silently aborts** at this size |
| `@spideriq/mcp-publish` | 163 | content · templates · deploy · marketplace. **No** forms/booking/press/funnels/section-overrides | loads everywhere; incomplete |
| `@spideriq/mcp-publish` + `SPIDERIQ_MCP_SLICE=mac-128` | 95 | the above **minus the reuse path** | ⛔ never |

```json
"spideriq": {
  "command": "npx",
  "args": ["-y", "@spideriq/mcp@latest"],
  "lazy": true,
  "env": { "SPIDERIQ_MCP_MODE": "facade", "SPIDERIQ_FORMAT": "yaml" }
}
```

> ### The size limit, as MEASURED (2026-08-12) — not as guessed
>
> Every doc in this repo said "~128 tools", a figure from a May 2026 code comment
> nobody re-measured. Two live Antigravity runs:
>
> ```
>   163 tools  →  ingests cleanly, 163 schema files written to the client cache
>   431 tools  →  SILENTLY ABORTS. no error, no warning. the client keeps the
>                 PREVIOUS package's cached tools, so the session believes it
>                 switched and has not.
> ```
>
> So the real bound is somewhere between 163 and 431 and **nobody has bisected it**.
> Re-measure before quoting a number — a third-party client's limit expires like any
> other external fact.
>
> The silent abort is the dangerous half: it fails by *succeeding wrongly*. If your
> tool list looks like a package you did not configure, that is what happened.

> ### ⛔ Never set `SPIDERIQ_MCP_SLICE=mac-128`
>
> Its keep-list declares 130 names but **35 are ghosts** — renamed or never present
> (`content_get_help` vs the real `template_get_help`; `content_insert_section` vs
> `page_insert_section`; `content_marketplace_search` vs `marketplace_search`; six
> `form_*` names not in mcp-publish at all). The filter is a plain name intersection,
> so every ghost is a silent no-op: it serves **95**, not 130.
>
> **Its entire "Shared (auth + system) — 8 tools" block is ghosts.** Every one is
> written with a prefix the real tool does not carry:
>
> | keep-list name | real name |
> |---|---|
> | `auth_request_access` | `request_access` |
> | `auth_check_access_status` | `check_access_status` |
> | `auth_get_workspaces` | `list_workspaces` |
> | `auth_logout` | `logout` |
> | `auth_whoami` | `get_auth_status` |
> | `system_health_check` | `health_check` |
> | `system_get_queue_stats` | `get_queue_stats` |
> | `system_get_api_info` | `get_api_info` |
>
> So a `mac-128` session cannot check which tenant it is on, cannot enrol, and
> cannot health-check — the block that was supposed to guarantee those is the one
> block where nothing matched. **A tool list with no `get_auth_status` and no
> `health_check` in it is how you recognise this slice.**
>
> Worse still, it drops six
> tools that ARE present by default — `page_insert_section`, `marketplace_search`,
> `content_list_marketplace_components`, `content_apply_site_template`,
> `content_get_playbook`, `content_list_marketplace_bg_videos` — the entire
> adapt-don't-generate path, plus the intent→recipe lookup.

If you're not sure: `@spideriq/mcp` **with facade mode**. It is smaller than every alternative *and* reaches more.

### Installation

```bash
# facade mode — 9 listed, 431 reachable (recommended)
SPIDERIQ_MCP_MODE=facade npx @spideriq/mcp@latest

# unfiltered kitchen sink — 431 listed (only if your client accepts that size)
npx @spideriq/mcp@latest
```

Both pull from `https://npm.spideriq.ai` (Verdaccio mirror). Auth: configure `.mcp.json` with the standard MCP-server entry:

```json
{
  "mcpServers": {
    "spideriq": {
      "command": "npx",
      "args": ["-y", "@spideriq/mcp@latest"],
      "lazy": true,
      "env": { "SPIDERIQ_MCP_MODE": "facade", "SPIDERIQ_FORMAT": "yaml" }
    }
  }
}
```

> **Do not add `--registry=…` to `args` for an `@spideriq/*` package.** A scoped
> rule in `.npmrc` (`@spideriq:registry=https://npm.spideriq.ai`) **beats the
> `--registry` flag**, so a wrong registry in `args` is silently ignored on a
> machine that already has the scope configured — and resolves nothing on a clean
> one. Put the registry in `.npmrc`, not in the server entry.

> **`"lazy": true` is Antigravity-specific.** Antigravity sessions report
> (2026-08-13) that it avoids an IDE bug where natively-injected (eager) tools
> throw `unknown tool` when called, and that lazily-loaded tools are invokable
> through their `call_mcp_tool` abstraction. **We have not verified this** — we
> cannot run that IDE, and the facade's own protocol test there was done with a
> standalone JSON-RPC client that bypasses the IDE's tool-calling entirely.
> Every other client ignores the key, so it is safe to carry.

After install, run `request_access` → `check_access_status` (PAT flow), then
`get_auth_status({ topic: "tenancy" })` to confirm **which** tenant resolved,
before any tenant-scoped write. See [`SKILL.md` → *Auth + two URL surfaces*](../SKILL.md).

## The 128-tool ceiling story (why the split exists)

The full SpiderIQ surface is **431** tools (publish + forms + booking + press + funnels + mail + gate + leads + admin). Size-limited clients cannot take that list — Antigravity silently aborts on it (see the measurement above).

Two historical answers, both now superseded by facade mode: `@spideriq/mcp-publish` (**163**) carves out the families a content-authoring agent needs least often — `form_*` (28), `booking_*`/`service_*` (15), `press_*` (27), `flow_*` (12), `funnel_template_*` (4), the 3 section-override tools, docs-query (4) — and the `mac-128` slice (**95**) narrows it further and breaks doing so.

**Calling a carved-out tool gives you a useful error, not a bare 404** — mcp-publish returns a hint naming the kitchen-sink package for `form_*`. Treat that as configuration guidance to relay to the user, never as a platform bug.

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

## Tool families — and which universe each reaches

**`publish` = in mcp-publish (default). `sink` = kitchen sink only. `-mac128` = also dropped by the mac-128 slice.**

Each row is a domain. Counts roughly reflect `packages/mcp-tools/src/publish/*.ts`.

| Family | Files | Tools | Purpose |
|---|---|---|---|
| Content (pages, posts, docs, settings, domains, navigation, components) | `content.ts` (1927 LOC) | ~60 | Core CMS surface |
| Forms (kind='form' booking_flows) | `forms.ts` (1848 LOC) | 27 | Conversational form authoring + templates + embed + validation |
| Templates + deploy | `templates.ts` (630 LOC) | ~22 | Liquid CRUD, themes, deploy pipeline, readiness probe |
| Section overrides ⚠️ **sink** | `section_overrides.ts` | 3 | One-call sectional swaps (header, footer, layout presets). On mcp-publish use `template_upsert('sections/header.liquid')` instead — same effect. |
| Forms ⚠️ **sink** | `forms.ts` | 28 | `kind='form'` authoring + templates + embed + logic + validation |
| Booking ⚠️ **sink** | `booking/*.ts` | 15 | booking flows, services, bookings, templates |
| Press / Newsroom ⚠️ **sink** | `press.ts` | 27 | releases, contacts, boilerplates, kits, embargo |
| Funnels (Flow graph) ⚠️ **sink** | `flows.ts` + `funnel_templates.ts` | 16 | multi-step journeys, splits, embeds, starters |
| Docs query ⚠️ **sink** | `docs_query.ts` | 4 | `search_docs` / `semantic_search_docs` / `ask_docs` / `get_doc` |
| Marketplace (browse + insert + agent_meta) ⚠️ **-mac128** | `marketplace.ts` | ~12 | Section inserts, bg-videos, agent-meta authoring. **The reuse path** — present by default, dropped by the mac-128 slice. |
| Site templates ⚠️ **-mac128** (`apply` only) | `site_templates.ts` | 3 | Curated starter sites — `list` + `get` + `apply`. `content_apply_site_template` is dropped by the mac-128 slice. |
| Directory (SEO category/listing) | `directory.ts` (299 LOC) | 10 | Programmatic SEO |
| Duplicate (page/block/post/doc) | `duplicate.ts` (177 LOC) | 4 | Cheap deep-copies |
| Component propagation | `component_propagation.ts` (210 LOC) | 2 | The two one-shots: `update_and_propagate`, `rollback` |
| Audit + visual-check | `audit.ts` (47 LOC) + `content.ts` (visual-check) | 2 | Link audit + Playwright sidecar |
| Playbook | `playbook.ts` (56 LOC) | 1 | NL-intent → recipe lookup |
| Scroll sequence | `scroll_sequence.ts` (179 LOC) | 1 | Video → frame extraction + page block |
| Local upload | `local_upload.ts` (333 LOC) | 2 | `upload_local_file` / `upload_local_directory` to SpiderMedia R2 |
| Media (SpiderMedia URL ops) | `media.ts` (166 LOC) | 6 | Import + list + delete + video status |

Plus the non-publish domains in the kitchen-sink `@spideriq/mcp` build: mail, gate, leads, admin, jobs, campaigns, IDAP, commerce.

> Counts here track `packages/mcp-tools/src/`. If a count disagrees with your own tool list, **your tool list wins** — re-run Step 0.

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
- [`SKILL.md` → *Auth + two URL surfaces*](../SKILL.md) — PAT auth + tenant binding
- `scripts/` in the SpiderIQ repo (internal) — `find-tool-for-intent.sh` + the rationale
- catalog/CLAUDE.md → "Tool surface" — internal canonical
