# CLI / MCP / skill gaps — and the verified verdict on the 2026-06-10 agent report

> This skill (the marketplace Tier-3 client) generates its methods directly from
> `client/schema.yaml`, so it covers the full SpiderPublish PAT surface. This file
> records (a) the verified verdict on the agent bug report that triggered the
> 0.4.0 rebuild, and (b) the CLI/MCP delta for agents on those surfaces.

## Part A — verdict on the 2026-06-10 agent test report

A paying client's agent tested the OLD `@spideriq/publish-skills` (the 3-sub-skill
version) and reported a list of failures. Each was verified against the live API +
the real tool source on **2026-06-11**. Verdict:

| Reported | Verdict | Root cause |
|---|---|---|
| `createPost` ignores cover_image_url / author_id / category_id | ✅ **REAL — FIXED** | old schema used `cover_image` (needs `cover_image_url`), omitted `author_id`, used singular `category_id` (needs `category_ids`, a LIST). Fixed: `createPost`/`updatePost` now mirror the MCP tool's field set. |
| `updatePost` ignores cover_image_url / category_id / featured / body | ✅ **REAL — FIXED** | same wrong names + `featured` (needs `is_featured`); whole write also 404'd on the bad base. `body` was present but the write failed on path. Fixed. |
| `skill_call` ambiguity ("specify one of: content-platform, templates-engine, manage-brands, upload-host-media") | ✅ **REAL — FIXED** | the package shipped **4 sub-skills**, so `skill_call(@spideriq/publish-skills → method)` couldn't resolve. Fixed: collapsed to **ONE** skill `spiderpublish`. (manage-brands had already moved to `@spideriq/workspace-skills`.) |
| Schema path `/api/v1/spideriq/content` vs real `/api/v1/content` | ✅ **REAL — FIXED** | `/spideriq/` was the dead opvsHUB proxy prefix → 404. Fixed: `base_url: /api/v1`; reads on `/content/*`, writes on `/dashboard/content/*`. See `learnings/2026-06-11-dead-spideriq-content-prefix/`. |
| `/content/categories` → 404 "MISSING" | ❌ **FALSE** | the route exists (`app/api/v1/content.py` `GET /categories`); live probe returns `{categories:[],total:0}`. The 404 was the dead `/spideriq/` prefix. |
| `/content/settings` → 404; `/content/navigation` → 404 | ❌ **FALSE** | both return **200** live. Same dead-prefix cause. |
| Write ops → 403 "Not authenticated" (even with a valid PAT) | ⚠️ **MISLEADING** | auth is fine: `GET /api/v1/dashboard/content/posts` + Bearer → **200**. The failures were wrong-path: `/spideriq/content` → 404, and POST to the public `/content/*` → **405** (read-only). NOT an auth-scope or write-disabled problem. |

**Net:** the backend was never missing endpoints and auth was never disabled. The
real defects were all in the **skill schema** (wrong base path, wrong post field
names, 4-sub-skill split) — now fixed in `publish-skills@0.4.0`. The MCP tool
`content_create_post` already used the correct field names.

## Part B — CLI / MCP surface delta (for agents NOT on this marketplace client)

This skill covers the full PAT surface. The CLI/MCP wrappers cover most of it; the
known deltas:

| Capability | HTTP route (exists, used by this skill) | CLI / MCP status |
|---|---|---|
| Post writes with full field set | `POST/PATCH /dashboard/content/posts` | ✅ MCP `content_create_post` / `content_update_post` correct (the bug was skill-only) |
| Marketplace catalog-row CRUD (site-templates, bg-videos) | `POST /dashboard/projects/{pid}/content/{site-templates,bg-videos}` | ⚠️ **REST-only** — no registered MCP `content_create_site_template` / `…_bg_video` tool despite some `next_step` hints implying one. Author via REST/dashboard for now. (Surfaced by the references consolidation; super_admin / marketplace-authoring scope.) |
| Categories / settings / navigation / domains | `/dashboard/content/*` | ✅ reachable; covered by this skill's methods |

**No `needs-replan` was raised:** every method this skill declares maps to a
real, PAT-reachable HTTP route (verified 2026-06-11). The marketplace catalog-row
MCP-wrapper gap is a minor follow-up for the SpiderCLI/mcp-publish surface, not a
blocker for this skill.

## Verification basis (2026-06-11)

- API mounts: `app/main.py` (`/api/v1/content`, `/api/v1/dashboard/content`,
  `/api/v1/dashboard/templates`, `/api/v1/dashboard/content/components`).
- Routes: `app/api/v1/content.py`, `dashboard_content.py`,
  `dashboard_content_components.py`, `dashboard_templates.py`.
- MCP: `packages/mcp-tools/src/publish/content.ts` (`content_create_post` field set).
- Live probes against `https://spideriq.ai` (reads 200, dead prefix 404, public
  POST 405, dashboard read+Bearer 200).
