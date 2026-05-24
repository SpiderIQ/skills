# recipes/audit-driven-edit

Edit a page section with **rules-on-the-way-in** (`_rules` envelope on dry_run) and **audit-on-the-way-out** (`_audit` envelope on the success response). Replaces "insert blindly and hope it renders" with a single-roundtrip authoring loop where the agent learns the canonical tool path BEFORE inserting, and sees broken state IMMEDIATELY on the response — not three roundtrips later when the dashboard preview loads.

## When to use

- You're inserting any component for the first time and want to know its canonical authoring path (component author wrote `preferred_path` into `authoring_hints`).
- You're inserting a complex component (scroll-sequence, multistep form, dynamic block) and want the server to flag missing required props before the page goes live.
- You're auditing an existing page for issues — call `GET /pages/{id}?audit_level=warnings` and read the `_page_audit` block.
- You authored a global component and want to write the rules other agents will see when they insert it (the `authoring_hints` write surface).

## The one-shot calls

```bash
# Read a page WITH audit decoration
GET /api/v1/dashboard/projects/{pid}/content/pages/{page_id}?audit_level=warnings
# → page response + _page_audit: {site_level, page_level, block_level, component_level, summary}

# Insert section — dry_run first, get _rules
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/insert-section?dry_run=true
Body: { "component_slug": "sys-scroll-sequence", "props": {} }
# → {
#     "preview": {...},
#     "confirm_token": "cft_xxx",
#     "expires_at": "...",
#     "_rules": {
#       "component_slug": "sys-scroll-sequence",
#       "kind": "interactive",
#       "intrinsic":     [...],          // derived from kind/dependencies/props_schema
#       "authored":      {               // raw passthrough from authoring_hints JSONB
#         "preferred_path": "Use the video_to_scroll_sequence MCP tool — it extracts frames from a video file and creates this block in one call.",
#         "must_set":       ["frames"]
#       },
#       "cross_cutting": [...]           // PageAuditor.audit_page() findings BEFORE the mutation
#     }
#   }

# Confirm — get _audit on the response
POST /api/v1/dashboard/projects/{pid}/content/pages/{page_id}/insert-section?confirm_token=cft_xxx&audit_level=all
Body: { "component_slug": "sys-scroll-sequence", "props": {"frames": ["a.jpg","b.jpg",...]} }
# → {
#     "success": true,
#     "page_id": "...",
#     "new_block_id": "...",
#     "_audit": {
#       "site_level":      [],
#       "page_level":      [],
#       "block_level":     [],          // empty when frames are populated; would carry insertion.scroll_sequence_empty_frames if not
#       "component_level": [],
#       "summary": { "errors": 0, "warnings": 0, "info": 1 }
#     }
#   }
```

**MCP tools** — ship in `@spideriq/mcp-publish@1.12.0+` and kitchen-sink `@spideriq/mcp@1.12.0+`:

- `content_get_page({page_id, audit_level?})` — `audit_level` ∈ `off | errors | warnings | all`, default `warnings`
- `page_insert_section({page_id, component_slug, ..., audit_level?, dry_run?, confirm_token?})` — `audit_level` default `all` for mutations
- `content_create_component({...., authoring_hints?})` — write surface for component authors
- `content_update_component({...., authoring_hints?})` — replace stored hints (pass `{}` to clear)

## The `_rules` envelope (dry_run)

Three independent rule sources composed:

| Source | Where | When present |
|---|---|---|
| **A — intrinsic** | derived from the component's `kind` / `dependencies` / `props_schema` at request time | always |
| **B — authored** | raw passthrough from `content_components.authoring_hints` JSONB (the `preferred_path`, `common_mistakes`, `must_set`, `must_not_set` fields) | when the component author populated the column |
| **C — cross_cutting** | caller-supplied `PageAuditor.audit_page` findings on the target page BEFORE the mutation lands | only on dry_run of `insert_section` |

**Intrinsic rule examples** (the auditor adds these without any author write):

- `intrinsic.scroll_sequence_frames_required` — `kind=interactive` with GSAP/ScrollTrigger dep + `frames` in props_schema → `error`
- `intrinsic.dynamic_requires_data_binding` — `kind=dynamic` → top-level `data_binding` is required → `error`
- `intrinsic.interactive_root_props_contract` — `kind=interactive` → JS body runs as `(root, props) => ...` where `root` is the SHADOW root → `info`
- `intrinsic.props_schema_required` — `props_schema.required[]` is non-empty → `warn` listing the keys

## The `_audit` envelope (mutation success)

Same shape as `PageAuditResult` from `content_export_page` — bucketed by scope:

```json
{
  "site_level":      [],
  "page_level":      [],
  "block_level":     [{ "rule_id": "insertion.scroll_sequence_empty_frames", "severity": "error", "scope": "block", "target": "<block_id>", "message": "...", "suggested_fix": "..." }],
  "component_level": [],
  "summary": { "errors": 1, "warnings": 0, "info": 0 }
}
```

**Mutation rules** (P5 — see [PageAuditor.audit_block_insertion](https://docs.spideriq.ai/api-reference/content/insert-section)):

| Severity | Rule | Catches |
|---|---|---|
| error | `insertion.scroll_sequence_empty_frames` | scroll-sequence inserted with 0 frames bound — section renders blank |
| error | `insertion.unknown_component` | `component_slug` doesn't resolve for this client (not in library, not global) |
| warn | `insertion.missing_required_prop` | `authoring_hints.must_set` lists a prop that's empty/absent |
| warn | `insertion.forbidden_prop` | `authoring_hints.must_not_set` lists a prop that's present |
| info | `insertion.preferred_path_hint` | surfaces `authoring_hints.preferred_path` so you learn the canonical tool |

## The `audit_level` toggle

| Value | Reads (`GET /pages/{id}`) | Mutations (`/insert-section`) |
|---|---|---|
| `off` | omits `_page_audit` entirely (cheapest — skips the auditor walk) | omits `_audit` |
| `errors` | only error-severity findings | only errors |
| `warnings` (default for reads) | errors + warnings | errors + warnings |
| `all` (default for mutations) | every finding incl. info | every finding incl. info |

Default behaviour is agent-friendly. Use `audit_level=off` only inside tight-loop scripts that bulk-insert and audit later via `content_export_page`.

## Component-author write surface — `authoring_hints`

When you author a global component, populate `authoring_hints` so downstream agents inserting it get tailored guidance:

```js
content_create_component({
  slug: "my-component",
  name: "...",
  html_template: "...",
  // ... other args ...
  authoring_hints: {
    preferred_path: "Use my_helper_tool, not manual insert.",      // info-level nudge surfaced on dry_run
    common_mistakes: ["Forgetting props.thank_you_url"],            // visible to all inserting agents
    must_set:        ["headline", "submit_endpoint"],               // missing → warn `insertion.missing_required_prop`
    must_not_set:    ["_internalKey"]                               // present → warn `insertion.forbidden_prop`
  }
})
```

Empty `{}` (the column default) = no hints; the component degrades cleanly to intrinsic-only rules.

## End-to-end recipe

```bash
PROJECT_ID="<your-project-id>"
PAGE_ID="<page-uuid>"
PAT="<your-pat>"

# 1. Read the page first to see current state + page-level audit
curl -H "Authorization: Bearer $PAT" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PROJECT_ID/content/pages/$PAGE_ID?audit_level=warnings" \
  | jq '{slug, blocks_count: (.blocks | length), audit: ._page_audit.summary}'

# 2. dry_run insert — read _rules to learn the canonical path
curl -X POST -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PROJECT_ID/content/pages/$PAGE_ID/insert-section?dry_run=true" \
  -d '{"component_slug": "sys-scroll-sequence", "props": {}}' \
  | tee /tmp/dry_run.json
PREFERRED=$(jq -r '._rules.authored.preferred_path' /tmp/dry_run.json)
echo "Author guidance: $PREFERRED"
TOKEN=$(jq -r '.confirm_token' /tmp/dry_run.json)

# 3. If preferred_path nudges you elsewhere (e.g. video_to_scroll_sequence), STOP and use that tool instead.
#    Otherwise, add the required props and confirm:
curl -X POST -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" \
  "https://spideriq.ai/api/v1/dashboard/projects/$PROJECT_ID/content/pages/$PAGE_ID/insert-section?confirm_token=$TOKEN&audit_level=all" \
  -d '{"component_slug": "sys-scroll-sequence", "props": {"frames": ["..."]}}' \
  | jq '._audit'
```

## Anti-patterns

- **Don't** ignore `_rules.authored.preferred_path`. The component author wrote it because the manual-insert path is error-prone for that component. Read it BEFORE confirming the dry_run.
- **Don't** skip the dry_run because "you know the shape". Static knowledge of the props_schema doesn't catch dynamic constraints (the page already has 4 scroll-sequences, the site is missing a primary domain, etc.) — those only surface in `_rules.cross_cutting`.
- **Don't** retry on `_audit.errors > 0` without addressing the finding. Each error has a `suggested_fix` field — apply it before the next attempt.
- **Don't** set `audit_level=off` on every call to "save tokens". The audit walk is single-digit milliseconds; the savings come from skipping it inside genuinely tight loops, not on regular agent traffic.
- **Don't** write `authoring_hints` on a tenant-scoped component you didn't author. The hints column is for component authors signalling to downstream inserting agents.

## Backwards compatibility

The envelope fields are **purely additive** — agents that ignore `_rules` / `_audit` / `_page_audit` aren't broken. Components that have empty `authoring_hints` (the column default `{}`) degrade cleanly to intrinsic-only rules. No existing recipe needs to change to keep working.

## See also

- `recipes/scroll-sequence/SKILL.md` — the deeper how-to for the scroll-sequence-specific traps the audit catches
- `recipes/lock-during-review/SKILL.md` — the P4 lock that pairs with this recipe (lock the page, audit, unlock)
- `recipes/audit-and-fix/SKILL.md` — sibling recipe that walks an EXISTING page through the auditor and fixes findings inline (P2)
