# Recipe: scrape Google Maps for one query (single)

One search in → a list of businesses out. Use this whenever the user wants the
businesses on Google Maps for a single query ("plumbers in Berlin", "coffee
shops near Shoreditch", "dentists in Lisbon") and **does not** need their
websites crawled or emails verified.

The flow is `flow:mapsSearch` (marketed as **Maps Search**) — a **Maps-only**
flow:

```
SpiderMaps (Google Maps via anti-detect browser)
find businesses → name, address, phone (E.164), website, rating, categories, coords
```

> **Maps-only.** This flow stops at the Maps listing. It does **not** crawl each
> website or verify emails — there are no emails in the output. If the user wants
> verified contact emails or site data (team, company info), that's the lead
> chain — use [maps-site-verify-vayapin/recipes/run-single.md](../../maps-site-verify-vayapin/recipes/run-single.md)
> (`searchLeads`) instead.

> **Cheap & fast.** ~**1 credit per run, ZERO AI tokens** (pure browser scraping,
> no LLM), typically 30–90s for ~20 results. The cheapest flow in the skill.

## Steps

1. **Build the query — put the place INSIDE it.** A single Maps job has **no
   separate `location` or `country_code` field**. The location goes *in*
   `search_query`: `"plumbers in Berlin"`, not `search_query: "plumbers"` +
   `location: "Berlin"`. (See [learnings/2026-05-26-location-goes-in-the-query](../learnings/2026-05-26-location-goes-in-the-query/artifacts/what-we-learned.md).)
   The worker auto-disambiguates 26 ambiguous European city names (Hamburg,
   Munich, Paris…) by appending the country, so `"cafes in Hamburg"` resolves to
   Germany, not the US namesake.

2. **Pick `max_results`.** 1–100, default 20. This is the single-job ceiling —
   **100, not 500** (the 500 you may see in the flow's marketing schema is the
   campaign ceiling, not this path). Higher = slower and more exposure to
   Google's rate limiting.

3. **Decide the extras.** All off/default unless the user needs them:
   - `extract_reviews` (default `false`) — pull review snippets per business (slower).
   - `extract_photos` (default `false`) — pull photo URLs.
   - `validate_phones` (default `true`) — adds `phone_e164` / `phone_type` / `phone_valid`.
   - `store_images` (default `true`) — stores the first image and returns `image_url`.
   - `lang` (default `en`) — Google Maps UI language.
   See [per-stage-settings.md](per-stage-settings.md) for the full list.

4. **Submit** `POST /api/v1/jobs/spiderMaps/submit` — note the **nested
   `payload`** wrapper (this route is `{ "payload": {…}, "priority": N }`):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderMaps/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "payload": {
         "search_query": "plumbers in Berlin",
         "max_results": 20,
         "extract_reviews": false,
         "lang": "en"
       }
     }'
   ```

   Response (`201`): `{ "job_id": "...", "type": "spiderMaps", "status": "queued", "from_cache": false, "message": "..." }`.

   **Watch `from_cache`.** If you re-submit an *identical* payload within 24h you
   get `from_cache: true` and the **same** `job_id` — a cached result, not a fresh
   scrape. To force a new run, change the query or add `"test": true`. See
   [learnings/2026-05-26-job-dedup-24h-cache](../learnings/2026-05-26-job-dedup-24h-cache/artifacts/what-we-learned.md).

   **By a Maps URL instead of a query:** swap `search_query` for `url` with a
   direct `https://www.google.com/maps/place/…` (or a Maps search-results URL) —
   the worker navigates straight to it. Provide exactly one of `search_query` /
   `url`. (`query` is also accepted as a backwards-compat alias for `search_query`.)

5. **Watch** — poll `GET /jobs/{job_id}/status` no faster than every 3–5s, or use
   the SSE stream. Maps is the quick stage (typically 30–90s for ~20 results),
   but Google's tiered ban-detection cooldowns (0 / 30 / 120 / 300s) can stretch a
   run, and partial results are saved incrementally — so a slow or short run is
   usually throttling, not failure. Set the user's expectation and **never
   tight-loop**. See [learnings/2026-05-26-ban-cooldowns-and-timing](../learnings/2026-05-26-ban-cooldowns-and-timing/artifacts/what-we-learned.md)
   and the foundation's [run-modes-and-progress.md](../../../references/run-modes-and-progress.md).

6. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   The businesses come back under `data.businesses[]`. See [read-results.md](read-results.md).
   **Standalone Maps results are read here, NOT through IDAP** — `GET /idap/businesses`
   is the campaign lead-chain surface, not this one.

## Key fields (`SpiderMapsJobPayload`, inside `payload`)

| Field | Default | Notes |
|---|---|---|
| `search_query` | — (required*) | What to find + WHERE, e.g. `"dentists in Lisbon"`. 1+ chars. |
| `url` | — (required*) | Alternative to `search_query`: a direct `google.com/maps/place/…` URL. |
| `max_results` | `20` | 1–100. Businesses to return. (Single-job cap is 100.) |
| `extract_reviews` | `false` | Pull review snippets (slower). |
| `extract_photos` | `false` | Pull photo URLs. |
| `lang` | `en` | Google Maps UI language (en, es, fr, de, it, pt, …). |
| `validate_phones` | `true` | libphonenumber → `phone_e164` / `phone_national` / `phone_type` / `phone_valid`. |
| `store_images` | `true` | Store the first image to SpiderMedia → `image_url`. |
| `test` | `false` | Route to the test queue (dev only). |
| `priority` | `0` | Top-level (sibling of `payload`), 0–10 — higher runs sooner. |

\* Exactly one of `search_query` / `url` is required (422 if both are empty).

## Gotchas

- **No `location` / `country_code` on a single job.** They are not fields the
  Maps worker reads — embed the place in `search_query`. (The flow's marketing
  `input_schema` lists them, but the single Maps worker silently ignores them.)
  See [learnings/2026-05-26-location-goes-in-the-query](../learnings/2026-05-26-location-goes-in-the-query/artifacts/what-we-learned.md).
- **`max_results` caps at 100 here.** A request for 500 is the *campaign* path,
  not a single job. The single route enforces `≤ 100`.
- **No emails.** Maps listings carry a `website`, not an email. If the user
  needs emails, that's the lead chain (`searchLeads`), not this flow.
- **Don't trust `rating: 4.0` / `reviews_count: 1024` blindly.** When Google
  serves its compact anti-bot format, those are placeholder values. See
  [results-shape.md](results-shape.md) and
  [learnings/2026-05-26-compact-format-dummy-values](../learnings/2026-05-26-compact-format-dummy-values/artifacts/what-we-learned.md).
- **`extract_reviews` / `extract_photos` don't come back through the typed
  results.** The worker honors them (raw `reviews[]`/`photos[]`), but the
  `/jobs/{id}/results` business records expose only `reviews_count` + `image_url`
  — the arrays are dropped by the response transform. Don't promise review *text*
  or a photo gallery from the standard endpoint. See
  [results-shape.md](results-shape.md).
- **`fuzziq_enabled` / `fuzziq_unique_only` are deprecated** (FuzzIQ was removed
  from the pipeline) — don't set them; the API returns an `X-Deprecated-Fields`
  header if you do.
- **Rate limit ~10 jobs/min per VPS** and a **24h dedup cache** — relevant when
  you fire several runs; see [run-batch.md](run-batch.md).

## Verify

- Got a `job_id` and `status: queued` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- `data.results_count` and `len(data.businesses)` match what you expected (and
  see [scripts/verify-maps-complete.sh](../scripts/verify-maps-complete.sh) for a
  one-shot audit of field coverage).
