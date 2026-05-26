# Reference: the search payload — every Maps option

`mapsSearch` is a **single-stage** flow (just the Maps listing), so there is no
multi-stage `config` block like the chained flows have — there's one payload of
search options. **This is the authoritative payload reference: every field the
route accepts, what the worker actually does with it, and the four fields that
behave differently than they look.** Read it before composing a non-trivial
submission.

The body of `POST /jobs/spiderMaps/submit` is `{ "payload": {…}, "priority": N }`.
Everything below lives **inside `payload`** unless the row says "top-level".

Validated by `SpiderMapsJobPayload` (`app/schemas/spidermaps.py:13`). The worker
that consumes it is the `googlemaps/search` skill
(`workers/SpiderBrowser/skills/googlemaps/search.py:108-117`).

```json
{
  "payload": {
    "search_query": "dentists in Lisbon",
    "max_results": 20,
    "extract_reviews": false,
    "extract_photos": false,
    "lang": "en",
    "validate_phones": true,
    "store_images": true,
    "test": false
  },
  "priority": 0
}
```

**Cost & speed:** Maps Search is **~1 credit per run and uses ZERO AI tokens** —
it's pure browser scraping (no LLM). Typically 30–90s for ~20 results. It is the
cheapest, fastest flow in the skill.

## 1. What to search — provide exactly ONE of these

| Field | Default | What the worker does |
|---|---|---|
| `search_query` | — | The query string: **`"{what} in {where}"`** — `"plumbers in Berlin"`. The place goes **here**; there is no `location` field (see below). |
| `query` | — | **Accepted alias** for `search_query` (backwards-compat). Prefer `search_query`; if you send both, `search_query` wins. |
| `url` | — | A direct Google Maps URL instead of a text query — a place URL (`…/maps/place/…`) or a Maps search-results URL. The worker navigates to it and extracts from there. Use when you already have the exact Maps link. |

A 422 is returned if **both** `search_query`/`query` and `url` are empty. Provide one.

### ⚠️ There is NO `location` or `country_code` field on a single job
The flow's marketing `input_schema` (`app/flows/mapsSearch.yaml`) lists `location`
and `country_code`. **The single Maps worker reads neither** — it reads `country`
(not `country_code`) and never reads `location`; the route's payload model doesn't
even define them, so they're dropped at validation. **Put the place inside
`search_query`.** `country_code` + `filter` are *campaign-only* concepts (the lead
chain's multi-location fan-out), not single-job fields. Full detail:
[learnings/2026-05-26-location-goes-in-the-query](../learnings/2026-05-26-location-goes-in-the-query/artifacts/what-we-learned.md).
The worker also auto-disambiguates 26 EU city names by appending the country —
[learnings/2026-05-26-geo-disambiguation-eu-cities](../learnings/2026-05-26-geo-disambiguation-eu-cities/artifacts/what-we-learned.md).

## 2. How much

| Field | Default | Range / notes |
|---|---|---|
| `max_results` | `20` | **1–100.** The single-job ceiling is **100** — the 500 you may see in the flow's marketing schema is the *campaign* ceiling, enforced only on the campaign path. Higher = slower + more Google rate-limit exposure. |

## 3. Output enrichment

| Field | Default | What it does |
|---|---|---|
| `validate_phones` | `true` | Runs libphonenumber on each phone → adds `phone_e164`, `phone_national`, `phone_type`, `phone_valid`. Leave on; E.164 is what downstream tools want. Covers 20+ countries. |
| `store_images` | `true` | Stores the first image to SpiderMedia (SeaweedFS) → permanent `image_url` on each business. |
| `extract_reviews` | `false` | Asks the worker to extract review snippets per business. **Caveat — see below.** Adds real time (visits more of each listing). |
| `extract_photos` | `false` | Asks the worker to collect the listing's photo URLs. **Caveat — see below.** |
| `lang` | `en` | Google Maps UI language (en, es, fr, de, it, pt, …). Affects category labels + some text. |

### ⚠️ `extract_reviews` / `extract_photos` don't surface through the typed results
The worker honors both flags — it adds `reviews: [...]` and `photos: [...]` to the
**raw** job output. But the typed `GET /jobs/{job_id}/results` response runs each
business through `SpiderMapsBusiness`, which has **no `reviews` / `photos` field**,
so those arrays are **dropped from the business records you read back**. What you
*reliably* get is `reviews_count` (the number) and `image_url` (the first photo).
Don't promise the user review *text* or a photo gallery from the standard results
endpoint. Detail:
[learnings/2026-05-26-extract-reviews-photos-not-in-typed-results](../learnings/2026-05-26-extract-reviews-photos-not-in-typed-results/artifacts/what-we-learned.md).

## 4. Plumbing (leave at defaults unless you have a reason)

| Field | Default | Notes |
|---|---|---|
| `priority` | `0` | **Top-level**, sibling of `payload`. 0–10; higher is processed sooner. |
| `test` | `false` | Route to the test queue (local workers). Dev only. Also useful to **force a fresh run past the 24h cache** (see §6). |
| `headless` | `true` | Browser headless mode — leave on for production. |
| `skip_proxy` | `false` | Skip the mobile-proxy pool, use a datacenter IP. Debug / A-B only; **raises ban risk** — don't set it for normal runs. |

## 5. Deprecated — do not use

| Field | Status |
|---|---|
| `fuzziq_enabled` | **Deprecated.** FuzzIQ deduplication was removed from the pipeline. Setting it does nothing useful and returns an `X-Deprecated-Fields` response header. For client-side dedup use `POST /api/v1/fuzziq/check-batch`. |
| `fuzziq_unique_only` | **Deprecated.** Same. (A `fuzziq_unique` field may still appear on a business — ignore it; it's meaningless now.) |

## 6. Operational limits the agent must respect

- **Rate limit: ~10 jobs/min per VPS.** A tight loop of submissions will hit it
  (429). Pace batch loops. See
  [learnings/2026-05-26-rate-limit-and-queue](../learnings/2026-05-26-rate-limit-and-queue/artifacts/what-we-learned.md).
- **Queue cap: 10,000 Maps jobs.**
- **24-hour dedup cache.** Re-submitting an *identical* payload within 24h returns
  the **same** `job_id` with `from_cache: true` — a cached result, not a fresh
  scrape. Vary the query or set `test: true` to force a new run. See
  [learnings/2026-05-26-job-dedup-24h-cache](../learnings/2026-05-26-job-dedup-24h-cache/artifacts/what-we-learned.md).
- **Google ban-detection cooldowns (0–300s)** can stretch a run; partial results
  are saved incrementally. See
  [learnings/2026-05-26-ban-cooldowns-and-timing](../learnings/2026-05-26-ban-cooldowns-and-timing/artifacts/what-we-learned.md).

## 7. The `workflow` escape hatch — this is the lead chain, not Maps Search

`payload.workflow` (a `WorkflowConfig`) exists on this route. **If you set it with
`spidersite.enabled: true`, you are no longer running Maps Search** — the API
auto-creates a campaign and chains SpiderMaps → SpiderSite → SpiderVerify →
(VayaPin). That is the **lead chain** (`flow:maps-site-verify-vayapin`). Its
config carries `spidersite` / `spiderverify` / `vayapin` blocks plus domain
filters (`filter_social_media`, `filter_review_sites`, `filter_directories`,
`filter_maps`), and it has its own cost gate and the **VayaPin publishing
HARD-GATE** (published pins are public and permanent). **Do not reach for
`workflow` from this flow.** If the user wants crawled sites + verified emails,
use [maps-site-verify-vayapin/recipes/run-single.md](../../maps-site-verify-vayapin/recipes/run-single.md)
(`searchLeads`) so the cost and vayapin gates apply.

## What Maps Search does NOT do

No website crawl, no email extraction (the listing's `website` is the only contact
field — **there are no emails**), no lead scoring, no publishing, no AI. The output
is the Google Maps listing only — see [results-shape.md](results-shape.md) for the
exact fields and [read-results.md](read-results.md) for how to read them.
