# recipes/marketplace-search-and-insert

Find marketplace assets by intent (mood / palette / brand-fit / scene), then insert one into a page — agent-discovery flow shipped 2026-05-05.

The classic flow `content_list_marketplace_components` filters by `category` (hero, features, pricing, …). The new `marketplace_search` filters by **what an agent actually wants** — "calm cinematic for a luxury hotel," "energetic conversion-focused for ecommerce" — across all 3 marketplace tables (bg-videos / components / site-templates) in one query.

## Quick ask: "find a calm bg-video and use it as hero on the homepage"

```
marketplace_search(
  mood = ["calm"],
  asset_types = ["bg_video"],
  limit = 5
)
# → results: [{ slug: "alpine-wildflowers", asset_type: "bg_video",
#               video_url: "https://media.cdn.spideriq.ai/bg-videos/alpine-wildflowers.mp4",
#               mood: ["calm","dreamy"], scene_type: "nature-landscape", ... }, ...]

content_insert_section(
  page_id = "<homepage uuid>",
  component_slug = "sys-bg-video",
  props = { video_slug: "alpine-wildflowers" },
  position = "start"
)
# → preview envelope with confirm_token

content_insert_section(
  page_id = "<homepage uuid>",
  component_slug = "sys-bg-video",
  props = { video_slug: "alpine-wildflowers" },
  position = "start",
  confirm_token = "<from previous>"
)
# → block inserted; page persists in draft until you publish + deploy
```

Runnable end-to-end (with auth + page lookup): [`examples/marketplace-search-and-insert.sh`](../../../examples/marketplace-search-and-insert.sh).

## Why search by intent?

Categories tell you the **shape** ("it's a hero"); they don't tell you whether the hero matches a luxury hotel brief or a fintech dashboard brief. The 4 universal axes do:

| Axis | Vocabulary (subset) | Picks |
|---|---|---|
| `mood` | calm, energetic, bold, dreamy, futuristic, urban, minimal, warm, editorial, professional, friendly, clear, technical, credible | The emotional register |
| `palette` | monochrome, deep-blue, cream, neutral-warm, nature-green, neon-accent, cinematic | The visual signature |
| `brand_fit_tags` | saas, agency, ecommerce, fintech, hospitality, restaurant, wellness, blog, publication, real-estate, … | The industry vertical |
| `scene_type` | hero-bold, conversion-cta, social-proof (components); city-aerial, nature-landscape (bg-videos); marketing-site, docs-site (site-templates) | The semantic shape |

`marketplace_search` matches **any-of** within an axis ("mood includes calm OR editorial") and **and-of** across axes ("calm-mood AND saas-brand-fit"). For tighter narrowing, pass single values per axis.

## Per-asset agent_meta

Beyond the 4 universal axes, each table has its own JSONB `agent_meta` with extra filters:

```
# Calm bg-video, slow pace, night scene, no people
marketplace_search(
  mood = ["calm"],
  asset_types = ["bg_video"],
  agent_meta = { pace: "slow", time_of_day: "night", has_people: false }
)
```

The full vocabulary lives in `template_get_help` (or `GET /content/help`) — search for `BgVideoAgentMeta` / `ComponentAgentMeta` / `SiteTemplateAgentMeta`.

## Anti-patterns

- **Don't bind `idap.lead` to a List block** — it's a singleton (`is_collection=false`); only Item Details accepts it.
- **Don't pass `mood` as a comma-string in the JSON body** — it's `string[]`. The CLI accepts `--mood calm,editorial`, the API expects `["calm","editorial"]`.
- **`agent_meta` is `extra="forbid"`** — typos return 422. Use `template_get_help` if a key isn't in the table above.
- **Universal axes are NOT inside `agent_meta`** — `mood` / `palette` / `brand_fit_tags` / `scene_type` are sibling top-level fields. Putting them inside `agent_meta` silently no-ops.

## See also

- [recipes/component-update-and-propagate](../component-update-and-propagate/) — when you want to edit one component everywhere it's used
- [skills/content-platform](../../content-platform/) — full tool catalog including `content_insert_section`
