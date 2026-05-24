# recipes/marketplace-suggest-agent-meta

Suggest mood / palette / brand_fit_tags / scene_type / agent_meta for a freshly uploaded marketplace asset using the SpiderGate-powered inference engine, then apply via the gated `set_*_agent_meta` tools — agent-curation flow shipped 2026-05-06 (slice 6).

The Marketplace V2 catalog is searchable by intent (mood / palette / brand-fit / scene-type / agent_meta). When an agent uploads a NEW asset, that asset arrives with empty metadata — invisible to `marketplace_search`. This recipe is the auto-curate path: an LLM-driven suggester proposes values; the agent reviews; the apply path writes them with `agent_meta_source='llm_inferred'`.

## Quick ask: "I just uploaded a bg-video — suggest its metadata so other agents can find it"

```
marketplace_suggest_agent_meta(
  asset_type = "bg_video",
  slug = "raindrops-tokyo-street"
)
# → SuggestEnvelope:
# {
#   "asset_type": "bg_video",
#   "slug": "raindrops-tokyo-street",
#   "proposed_universal_axes": {
#     "mood": ["urban", "dreamy"],
#     "palette": ["neon-accent", "monochrome"],
#     "brand_fit_tags": ["fintech", "tech"],
#     "scene_type": "city-aerial"
#   },
#   "proposed_agent_meta": {
#     "pace": "medium",
#     "time_of_day": "night",
#     "weather": "rain",
#     "has_people": true,
#     "aspect_ratio": "16:9"
#   },
#   "confidence_per_key": [
#     { "key": "mood",        "value": ["urban","dreamy"],  "confidence": 0.91, "action": "auto_apply" },
#     { "key": "palette",     "value": ["neon-accent",...], "confidence": 0.85, "action": "auto_apply" },
#     { "key": "scene_type",  "value": "city-aerial",        "confidence": 0.78, "action": "auto_apply" },
#     { "key": "agent_meta.weather", "value": "rain",        "confidence": 0.65, "action": "review" }
#   ],
#   "dropped_keys": [],          // off-vocab values the engine refused (audit-only)
#   "reasoning": "Defocused nighttime cityscape with rainfall and warm window lights — urban, dreamy, fintech-fitting.",
#   "usage": { "model": "spideriq/vision", "input_tokens": 670, "output_tokens": 220, "cost_usd": 0.005 }
# }

# Step 2: review + apply (gated, dry_run=true default → confirm_token round-trip)
set_bg_video_agent_meta(
  slug = "raindrops-tokyo-street",
  mood = ["urban", "dreamy"],
  palette = ["neon-accent", "monochrome"],
  brand_fit_tags = ["fintech", "tech"],
  scene_type = "city-aerial",
  agent_meta = { pace: "medium", time_of_day: "night", has_people: true, aspect_ratio: "16:9" }
  # Skip "weather": "rain" — confidence was "review" tier
)
# → preview envelope with confirm_token

set_bg_video_agent_meta(
  slug = "raindrops-tokyo-street",
  ...same args...,
  confirm_token = "<from previous>"
)
# → applied; agent_meta_source = 'llm_inferred', agent_meta_filled_at = NOW()
```

## Why this exists

- New marketplace assets arrive bare — invisible to `marketplace_search`. Without metadata, no other agent finds them.
- Manual curation is slow + inconsistent. The inference engine sees the poster (or the component HTML / template description) and produces structured metadata in <2 seconds.
- Provenance tracking (`agent_meta_source` column, slice 2) means LLM suggestions never overwrite a human curator's edits — `human_curated` is sticky.

## When to call this vs the V2 search tools

| Situation | Call this |
|---|---|
| Just uploaded a bg-video / component / site-template | ✅ `marketplace_suggest_agent_meta` |
| Want to find an existing asset by intent | ❌ use `marketplace_search` instead |
| Have your own labels in mind | ❌ skip suggester, call `set_*_agent_meta` directly |
| Bulk-fill many assets at once | ❌ ask SpiderIQ admin to run the slice 4 bulk pipeline |

## Output decoded

| Field | What it means |
|---|---|
| `proposed_universal_axes` | mood / palette / brand_fit_tags / scene_type — already filtered for off-vocab |
| `proposed_agent_meta` | per-asset-type keys (BgVideoAgentMeta / ComponentAgentMeta / SiteTemplateAgentMeta) — already filtered |
| `confidence_per_key[].action` | `auto_apply` (≥0.75 + vocab match) / `review` (≥0.55) / `drop` (already excluded from proposals) |
| `dropped_keys` | Audit log: keys the LLM proposed but the validator refused. Read these to spot vocabulary drift. |
| `reasoning` | One sentence justification — useful when picking between proposals |
| `usage.cost_usd` | <$0.01 typical per call (Opus 4.7 via spideriq/vision or spideriq/lead-analysis routes) |

## Guardrails

- **Always validated against locked Pydantic enums BEFORE returning.** A hallucinated mood like `"stoic"` never reaches you — it's dropped + listed in `dropped_keys`.
- **Universal `palette` is open vocabulary** by design — semantic color tokens (`deep-blue`, `cinematic`, `neon-accent`) are accepted as-is.
- **`scene_type` is single-value** and OMITTED when no enum value fits. The engine returns `scene_type: null` rather than force-fitting.
- **`agent_meta` has `extra="forbid"`** — keys not in `BgVideoAgentMeta` / `ComponentAgentMeta` / `SiteTemplateAgentMeta` are dropped.

## Anti-patterns

- **Don't blindly apply low-confidence values.** The `action: "review"` tier is your queue — eyeball before passing to `set_*_agent_meta`.
- **Don't re-run on `human_curated` rows.** They're sticky by design; the apply tool will silently no-op those keys (good). But it wastes a call.
- **Don't expect this to fill `palette` for components.** Most components have placeholder thumbnails — the engine returns `palette: null` for them. Components inherit theme palette at render time.

## See also

- [recipes/marketplace-search-and-insert](../marketplace-search-and-insert/) — once metadata is filled, find assets by intent
- [skills/content-platform](../../content-platform/) — full tool catalog including the `set_*_agent_meta` apply tools
