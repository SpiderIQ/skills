# Reference: crawl options (the complete payload for a site crawl)

siteScraper is a **single-stage** flow — there are no sub-stages to toggle (that's
the lead and company-intel chains). You tune **one crawl** through the payload
fields below. This is the **complete** field reference — every option, its type,
default, bounds, and the enum values it accepts. **Read it before composing a
non-trivial crawl**; the wrong toggle silently produces an empty section instead of
an error.

Same payload on both submit surfaces: `POST /jobs/spiderSite/submit` wraps it in
`{ "payload": { … }, "priority": 0-10 }`; the Flows facade wraps it in
`{ "input": { … } }` (single) or `{ "inputs": [ {…}, … ] }` (batch).

## Two ways to express a crawl

1. **Mode + flat fields (recommended, simplest).** Pick a `mode`, set the flat
   knobs you need (`max_pages`, `extract_team`, `compendium`, …). This is the whole
   table below.
2. **v3.0 composable blocks (advanced).** Pass structured `extraction` / `analyze`
   / `compendium` / `persist` objects for fine control. Documented in
   [§ v3.0 composable config](#v30-composable-config-advanced) at the end. You can
   mix — explicit flat fields still apply.

> For a guaranteed outcome, set the specific knob explicitly rather than relying
> only on a `mode` preset to imply it — the explicit fields are always read. (See
> the [mode-sets-the-budget learning](../learnings/2026-05-26-mode-sets-the-budget/artifacts/what-we-learned.md).)

## `mode` — the preset that sets pages + strategies + AI

`mode`: `string`, default `contacts`. Enum + exactly what each preset turns on:

| mode | max_pages | strategies | compendium | AI team | AI company | AI pain pts | lead scoring | LLM validation |
|---|---|---|---|---|---|---|---|---|
| `contacts` | 5 | css, jsonld, regex | off | — | — | — | — | off |
| `compendium` | 10 | css | on (`fit`, 100k) | — | — | — | — | off |
| `leads` | 50 | css, jsonld, regex, microformat | on (`fit`, 100k) | yes (≤10 pages) | yes | yes | — | off |
| `full` | 100 | css, jsonld, regex, microformat | on (`raw`, 200k) | yes (≤15 pages) | yes | yes | **yes** | on |

## Top-level fields

| Field | Type | Default | Bounds / enum | Notes |
|---|---|---|---|---|
| `url` | string | — (**required**) | 1–2048 chars | website to crawl; include `https://` |
| `mode` | string | `contacts` | `contacts` \| `compendium` \| `leads` \| `full` | the preset above |
| `overrides` | object | none | — | override mode defaults, e.g. `{"max_pages": 20, "strategies": ["css","regex"]}` |
| `max_pages` | integer | `10` | **1–50** | hard cap 50 on API + flow schema; `full`'s ~100 comes from the preset, **not** this field |
| `crawl_strategy` | string | `bestfirst` | `bestfirst` \| `bfs` \| `dfs` | `bestfirst` = smart prioritization; sitemap-first is used automatically when a sitemap is found |
| `target_pages` | string[] | `["contact","about","team","news","blog"]` | — | page types to prioritize; works in 36+ languages (`kontakt`, `contacto`, `über-uns`, …) |
| `timeout` | integer | `30` | 10–120 (s) | HTTP timeout per page |
| `enable_spa` | boolean | `true` | — | auto-detect + render JS-heavy sites (React/Vue/Angular/Next/Nuxt/Svelte/Shopify/Wix/Squarespace/…) with a headless browser |
| `spa_timeout` | integer | `30` | 10–120 (s) | page-load timeout, used only when an SPA is detected |
| `extract_team` | boolean | `false` | — | AI team-member extraction (~500 tokens); runs on contact/about/team pages only |
| `extract_company_info` | boolean | `false` | — | AI company vitals: summary, industry, services, audience (~500 tokens) |
| `extract_pain_points` | boolean | `false` | — | AI business-challenge inference from news/blog/jobs (~500 tokens) |
| `product_description` | string | none | ≤1024 chars | CHAMP lead scoring — **requires `icp_description`** too (~1,500 tokens) |
| `icp_description` | string | none | ≤1024 chars | CHAMP lead scoring — **requires `product_description`** too |
| `compendium` | object | see below | — | markdown-compendium config |
| `custom_ai_prompt` | object | none (off) | — | run your own prompt over the compendium |
| `fuzziq_enabled` | boolean | client setting | — | FuzzIQ dedup of extracted contacts (off by default since v3.1.0) |
| `fuzziq_unique_only` | boolean | client setting | — | return only unique records (filter duplicates) |
| `priority` | integer | `0` | 0–10 | higher runs first (top-level on the submit body, not inside `payload`) |
| `test` | boolean | `false` | — | route to the test queue (dev only) |
| `extraction` / `analyze` / `persist` | object | none | — | v3.0 composable blocks — see [below](#v30-composable-config-advanced) |

> **CHAMP is both-or-nothing.** `product_description` **and** `icp_description` must
> be sent together — one alone is a `422`. (`validate_champ_requirements`.)

## `compendium` object (markdown for LLMs)

| Sub-field | Type | Default | Bounds / enum | Notes |
|---|---|---|---|---|
| `enabled` | boolean | `true` | — | generate cleaned markdown of the crawl |
| `cleanup_level` | string | `fit` | `raw` \| `fit` \| `citations` \| `minimal` | `raw` 100% · `fit` ~60% (strips nav/ads) · `citations` ~70% (academic) · `minimal` ~30% (biggest token savings) |
| `max_chars` | integer | `100000` | 1,000–1,000,000 | truncates beyond |
| `include_in_response` | boolean | `true` | — | set `false` on big crawls to get a download URL instead of inline text |
| `remove_duplicates` | boolean | `true` | — | dedupe repeated headers/footers across pages (~20–40% smaller) |
| `separator` | string | `"\n\n---\n\n"` | — | page separator in the assembled markdown |
| `priority_sections` | string[] | `["main","article","content"]` | — | HTML tags/regions to prioritize when extracting content (esp. `minimal` mode) |

> Compendiums >10 MB come back as a presigned **download URL (24h TTL)**, not inline
> — see the [large-compendium learning](../learnings/2026-05-26-large-compendium-returns-a-url/artifacts/what-we-learned.md).

## `custom_ai_prompt` object (your own prompt over the compendium)

Requires `compendium.enabled=true`. If `enabled`, at least one of `system_prompt` /
`user_prompt` is required (else `422`). Output lands under the
`output_field_name` key in the results (default `custom_analysis`).

| Sub-field | Type | Default | Bounds / enum | Notes |
|---|---|---|---|---|
| `enabled` | boolean | `false` | — | turn on custom analysis |
| `system_prompt` | string | `""` | ≤2000 chars | the AI's role, e.g. "You are a security analyst." |
| `user_prompt` | string | `""` | ≤4000 chars | the task, e.g. "List security certifications and compliance frameworks." |
| `json_schema` | object | none | — | expected output shape; the AI tries to match it (structured JSON out) |
| `output_field_name` | string | `custom_analysis` | — | results key under which the output is stored |
| `model` | string | `spideriq/research` | `spideriq/research` \| `spideriq/lead-analysis` \| `spideriq/extraction` \| `spideriq/classification` \| `spideriq/summarization` \| `spideriq/fast` \| `spideriq/coding` \| `spideriq/chat` \| `spideriq/creative` | a SpiderGate task alias — the gateway resolves the provider + tracks per-brand usage |
| `temperature` | number | `0.1` | 0.0–2.0 | lower = deterministic |
| `max_tokens` | integer | `4000` | 100–16000 | max tokens in the AI response |

## Extraction strategies (what `strategies` means)

The crawl runs one or more extraction strategies (set by `mode`, or explicitly via
`overrides.strategies` / `extraction.strategies`):

| Strategy | Finds |
|---|---|
| `css` | emails/phones/socials from CSS selectors + `mailto:` / `tel:` links |
| `jsonld` | contacts from JSON-LD / Schema.org blocks |
| `regex` | plain-text emails/phones in page text (catches addresses not in `mailto:`) |
| `microformat` | hCard / microformat-marked contact data |

> `regex` can produce **false positives** (product codes that look like phones,
> tracking emails). The `leads`/`full` modes (and `extraction.validate_with_llm:true`)
> run an LLM validation pass to filter them — prefer that when accuracy matters.

## v3.0 composable config (advanced)

Instead of (or alongside) the flat fields, you can pass structured blocks. The
worker normalizes these; sub-keys:

```json
{
  "url": "https://example.com",
  "extraction": {
    "enabled": true,
    "strategies": ["css", "jsonld", "regex", "microformat"],
    "validate_with_llm": true,
    "max_pages": 25
  },
  "compendium": { "enabled": true, "cleanup_level": "fit", "max_chars": 100000, "remove_duplicates": true },
  "analyze": {
    "enabled": true,
    "extract_team": true,
    "extract_company_info": true,
    "extract_pain_points": false,
    "lead_scoring": { "enabled": true, "product_description": "…", "icp_description": "…" },
    "custom_ai_prompt": { "enabled": false },
    "model": "spideriq/extraction"
  },
  "persist": { "to_normalized": true, "to_fuzziq": false }
}
```

| Block | Sub-keys | Notes |
|---|---|---|
| `extraction` | `enabled`, `strategies[]` (css/jsonld/regex/microformat), `validate_with_llm` (bool), `max_pages` | controls crawl + which extractors run |
| `analyze` | `enabled`, `extract_team`, `extract_company_info`, `extract_pain_points`, `lead_scoring{enabled,product_description,icp_description}`, `custom_ai_prompt`, `model` | the AI layer (structured form of the flat `extract_*` + CHAMP fields) |
| `compendium` | same sub-fields as the `compendium` object above (+ `max_pages`) | |
| `persist` | `to_normalized` (bool, default `false`), `to_fuzziq` (bool, default `false`) | legacy persistence toggles — **note:** a site crawl's contacts already auto-sync to your normalized CRM (IDAP) regardless of `to_normalized`; see [read-results.md](read-results.md) |

## One stage, independently fallible

The crawl returns what it found. A missing AI section almost always means the
feature wasn't enabled (AI is opt-in — see the
[ai-is-opt-in learning](../learnings/2026-05-26-ai-is-opt-in/artifacts/what-we-learned.md));
an empty `emails[]` means the site exposed none; `crawl_status: partial` means some
pages failed but the rest succeeded. None of these is a hard failure — read
per-field presence, not just the top-line status. See [results-shape.md](results-shape.md).
