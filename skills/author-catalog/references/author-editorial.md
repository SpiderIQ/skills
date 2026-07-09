# Author catalog editorial (models · aliases · media)

The write flow for the copy a client reads about a gateway model. One rule
governs all three surfaces: **every edit is partial and COALESCE-preserve — send
only the fields you want to change.**

## The COALESCE-preserve model (read this first)

Each `set-meta` call writes **only the fields present in the request** and leaves
everything else exactly as it was. This has three consequences you must hold:

- **To change one field, send that one field.** Adding a badge? Send `badges`
  alone. You do NOT re-send `description` — omitting it preserves it.
- **`badges` and `tags` are wholesale replaces of that one field**, not merges.
  Send the COMPLETE list you want for that field. Sending `tags: ["fast"]`
  replaces all existing tags with just `fast`.
- **An empty edit is a `422`** ("No editorial fields supplied."). Supply at least
  one field.

## is_curated — authoring is sticky (and that's the point)

`gate_catalog_model_set_meta` stamps the row `is_curated=TRUE` (+ `curated_by` +
`curated_at`). From then on the 6h discovery sync **stops overwriting the row's
`display_name`** — your authored copy survives every sync tick. That is the A.1
"G4" guard. You do not fight the sync; authoring flips the row to human-owned.
(See `learnings/`.)

## Steps

1. **Find the model_id / alias / media_id.** Model rows are keyed by the numeric
   `gate_model_catalog.id`; aliases by their string (`spideriq/coding`,
   `opvs/creative`); media models by `provider/model`. The catalog read surface
   lists them.

2. **Write only what changes.**

   ```bash
   # a model's description + two tags (leaves badges/sort/hidden untouched)
   spideriq gate catalog models set-meta 42 \
     --description "Fast 8B extractor, tool-capable, PII-safe on the extraction alias." \
     --tags "fast,extraction,pii-safe"

   # add ONE badge later — send badges alone; description is preserved
   spideriq gate catalog models set-meta 42 \
     --badges '[{"label":"Fastest","tone":"gold"},{"label":"PII-safe","tone":"green"}]'

   # an alias's display copy (upsert — creates the row if absent)
   spideriq gate catalog aliases set-meta spideriq/coding \
     --display-name "Coding" --use-case "Multi-file refactors, tool-use, long context."

   # a media model's editorial (media_id is provider/model)
   spideriq gate catalog media set-meta openai/gpt-image-1 \
     --display-name "GPT Image 1" --description "High-fidelity image generation."

   # hide / un-hide from the client catalog
   spideriq gate catalog models set-meta 42 --hidden
   spideriq gate catalog models set-meta 42 --show
   ```

   MCP equivalents:
   `gate_catalog_model_set_meta({ model_id: 42, description: "…", tags: ["fast","extraction"] })`,
   `gate_catalog_alias_set_meta({ alias: "spideriq/coding", display_name: "Coding" })`,
   `gate_catalog_media_set_meta({ media_id: "openai/gpt-image-1", display_name: "GPT Image 1" })`.

3. **Verify** — the write returns the resulting row (the merged, post-write
   state). Confirm the field you set is present and the ones you omitted are
   unchanged. For a model, confirm `is_curated: true`.

## WRONG → RIGHT

- **WRONG:** to add a badge, re-send the whole row (`--description … --tags … --badges …`)
  copied from a stale read. → **RIGHT:** send `--badges '[…]'` alone; every other
  field is preserved server-side.
- **WRONG:** `--tags "fast"` to *add* a tag to a model that already has three. →
  **RIGHT:** `tags` replaces the list — send all four (`--tags "a,b,c,fast"`), or
  leave `--tags` off if you're not changing tags.
- **WRONG:** author an alias's routing here. → **RIGHT:** this is COPY only;
  changing which model the alias serves is `manage-routing` (`gate_routing_*`).

## Gotchas

- **Partial-blank trap.** Because omitted fields are preserved, you cannot "clear"
  a field by omitting it. Send an explicit empty value (e.g. `--meta '{"description":""}'`)
  to blank one.
- **`alias` / `media_id` slashes** — pass them plain (`opvs/coding`,
  `openai/gpt-image-1`); the tools URL-encode the slash. A bare single-segment
  path would 404 server-side, which is why the endpoints are `:path` params.
- **Media editorial lands in JSONB.** For `setMediaMeta`, only `display_name` is a
  real column; the rest merges into `metadata.editorial`. That's expected — media
  rows have no dedicated authored columns.

## Verify

- The response echoes the post-write row — assert your changed field and confirm
  omitted fields are intact.
- Model rows: `is_curated: true` after any author.
- Reload the catalog read surface and confirm the copy renders.
