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

### Rolling back / un-curating (a data op, not an edit)

There is no "un-author" verb — `is_curated` is not cleared by any set-meta call.
Reverting authored copy (e.g. to hand a row back to the discovery sync, or to undo
a bad fill) is a **data operation**, not an editorial one. The mechanics:

- **Blank a specific authored field** — send an explicit empty value
  (`{"description": ""}`), not an omission (omitting preserves).
- **Return a row to sync-managed** — clear the flag directly:
  `UPDATE gate_model_catalog SET is_curated = FALSE, curated_by = NULL, curated_at = NULL WHERE id = <id>;`
  The next sync tick then resumes managing `display_name`.
- **Remove enrichment side-rows** (benchmarks / perf / links written by a fill) —
  delete by the served `model_ref`:
  `DELETE FROM gate_catalog_benchmarks WHERE model_ref = '<served-ref>';` (same for
  `gate_catalog_provider_perf`, `gate_catalog_links`). The `model_ref` for a
  configured row is its `spidergate_id` (e.g. `gpt-4o-openai`), NOT
  `provider/model_id` — resolve it from the row before deleting.

These are super_admin DB operations; do them deliberately and only when reverting.

## Descriptions are OUR words (licensing — read before you write copy)

`description` / `long_description` must be **composed by you from structured
facts**, never copied from a vendor's marketing page, a model card, or Wikipedia.
Third-party prose is copyrighted; Wikipedia prose is CC-BY-SA (share-alike, a
copyleft trap for our DB). A sentence you build from facts —

> "GPT-4o is a multimodal model developed by OpenAI, released 2024-08-06, with a
> 128K-token context window, priced at $2.50 / $10.00 per million tokens."

— is provably not a copy. The facts (developer, modality, release, license,
context, price, lineage) come from the **enrichment** layer, which writes them to
the model row + `gate_catalog_benchmarks` / `gate_catalog_provider_perf` *before*
you author. If those facts aren't there yet, the model isn't ready — author copy
**after** the enrichment pass, not instead of it. If all you have is a source's
prose and no facts, write **less**, not a paraphrase-of-prose.

**This skill writes COPY, not FACTS.** It never sets `context_window`,
`max_output`, pricing, `capabilities`, `supports_tools`, benchmarks, or
provider-perf — those are the enrichment path's job. A description on a stub row
(context 0, no benchmarks) is not a "filled" model.

## Badge vocabulary (calibration, NOT a formula)

Badges are `{label, tone}`. The tones below keep the leaderboard reading as one
system — reuse a tone for its meaning, don't invent a new colour per model:

| Tone | Meaning | Example labels |
|---|---|---|
| `gold` | best-in-class / top of a category | Flagship · Frontier · Fastest |
| `green` | a positive economic/safety property | Budget · PII-safe · Open-license |
| `blue` | a capability | Multimodal · Long-context · Tool-use |
| `purple` | a distinct model archetype | Reasoning |
| `gray` | a caveat / de-emphasis | Legacy · Deprecated |

**This is calibration, not a lookup table to paste.** A badge is EARNED from the
model's facts, not assigned by rote — do NOT stamp the same one or two badges on
every model in a provider, or the leaderboard becomes noise (the whole point of a
badge is that most models don't have it). One provider has exactly one `Flagship`.
Prefer **1–2** badges per model; a model with no standout property gets **none**.
`badges` is a wholesale replace — send the complete list you want.

## Steps

1. **Find the model_id / alias / media_id.** Model rows are keyed by the numeric
   `gate_model_catalog.id`; aliases by their string (`spideriq/coding`,
   `opvs/creative`); media models by `provider/model`. **Resolve name → int id via
   the admin read** — `GET /admin/gate/catalog/models` (super_admin, X-Admin-Key)
   returns each row's integer `id`, which is what every `setModelMeta` / `setLink`
   is addressed by. (The *client* READ surface returns the string id, not the int —
   don't use it to resolve a write target.)

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
