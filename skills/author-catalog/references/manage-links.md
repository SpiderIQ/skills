# Manage per-model reference links

Attach (or remove) reference links — review videos, articles, studies, papers —
to a model. Links render on the model's catalog / leaderboard card and carry
licensing **provenance**.

## The two things that matter

1. **Idempotent per (model, url).** Adding a URL that already exists on the model
   UPDATES that link row (title/note/provenance) rather than creating a
   duplicate. So re-running an `add` to fix a typo in the title is safe.
2. **Provenance is mandatory for third-party content.** A link to content **we
   did not write** must set `is_authored_by_us=false` and fill `source` +
   `attribution` (and `source_url` where the license wants a link-back). The
   catalog renders that attribution. Only set `is_authored_by_us=true` for content
   SpiderIQ authored.

## Steps

1. **Add a link** (kind ∈ `youtube` | `article` | `study` | `paper`):

   ```bash
   # a third-party review video — provenance filled, is_authored_by_us stays false
   spideriq gate catalog links add 42 \
     --kind youtube \
     --url "https://youtube.com/watch?v=abc123" \
     --title "GPT-OSS-120B hands-on review" \
     --publisher "Some Reviewer" \
     --source "YouTube" \
     --attribution "© Some Reviewer, used under fair use" \
     --source-url "https://youtube.com/watch?v=abc123"

   # our own explainer — mark is_authored_by_us
   spideriq gate catalog links add 42 \
     --kind article --url "https://spideriq.ai/blog/extraction-models" \
     --title "How we pick extraction models" --authored
   ```

   MCP: `gate_catalog_links_set({ action: "add", model_id: 42, kind: "youtube", url: "…", source: "YouTube", attribution: "…", is_authored_by_us: false })`.

2. **Remove a link** by `link_id` (the id returned when it was added / listed on
   the catalog read):

   ```bash
   spideriq gate catalog links rm 42 8813
   ```

   MCP: `gate_catalog_links_set({ action: "remove", model_id: 42, link_id: 8813 })`.

## WRONG → RIGHT

- **WRONG:** add a competitor's benchmark link with no `source`/`attribution` and
  `is_authored_by_us` left unset. → **RIGHT:** `is_authored_by_us=false` +
  `source` + `attribution` (HARD-GATE) — the catalog must show where it came from.
- **WRONG:** delete a link by guessing the model from a bare `link_id`. →
  **RIGHT:** removal is scoped to the model — pass BOTH `model_id` and `link_id`;
  a `link_id` that doesn't belong to that model 404s.
- **WRONG:** add the same URL twice to "pin" it. → **RIGHT:** it's idempotent per
  (model, url); the second add just updates the first row.

## Gotchas

- **`kind` is a closed set** — `youtube` | `article` | `study` | `paper`. Anything
  else 422s.
- **Links key on the model's served-ref**, resolved from the numeric `model_id`
  server-side. You pass the numeric id; the endpoint maps it to the ref.
- **Delete returns 204** (no body). The CLI prints a success line; the MCP tool
  returns `{ success: true, removed: true }`.

## Verify

- `add` returns the created/updated link row (with its `link_id`) — note the id
  for a future `rm`.
- Reload the model on the catalog read surface and confirm the link renders with
  its attribution.
- `rm` on a non-existent (model, link_id) pair returns 404 — a clean signal the
  link was already gone or belongs to another model.
