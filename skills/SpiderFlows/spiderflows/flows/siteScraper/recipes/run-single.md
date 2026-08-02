# Recipe: scrape one website (single)

One URL in → a complete contact + intelligence profile out. Use this whenever the
user names **one** website ("scrape acme.com", "pull the emails off this site",
"get the team page for stripe.com", "build a company snapshot from their site").

This is `flow:siteScraper` (marketed as **Site Scraper**) — a **single-worker**
flow: SpiderSite crawls the site and returns everything in one job. There is no
campaign fan-out and no email-verification stage (the emails it returns are
**extracted, not SMTP-verified** — see [the unverified-emails learning](../learnings/2026-05-26-emails-are-unverified/artifacts/what-we-learned.md)).

```
SpiderSite
crawl up to N pages → emails, phones, socials, logo, team, company info,
                      markdown compendium, optional CHAMP lead score
```

## Steps

1. **Give it the URL and pick a `mode`.** `url` is the only required field. `mode`
   sets the page budget *and* which AI features run — pick it to match the job:

   | mode | pages | AI | use it for |
   |---|---|---|---|
   | `contacts` (default) | ~5 | none | quick emails/phones, zero AI cost |
   | `compendium` | ~10 | none | a clean markdown dump for your own LLM |
   | `leads` | ~50 | team + company info | full lead research |
   | `full` | ~100 | everything + lead scoring | maximum extraction |

   See [crawl-options.md](crawl-options.md) for every knob.

2. **Add only the knobs you need.** AI is **opt-in** — `contacts`/`compendium` use
   **zero** AI tokens. To force a specific feature regardless of mode, set it
   explicitly: `extract_team`, `extract_company_info`, `extract_pain_points`,
   `compendium.*`, or `custom_ai_prompt`. CHAMP lead scoring needs **both**
   `product_description` **and** `icp_description` (one without the other is a
   `422`). See [the AI-is-opt-in learning](../learnings/2026-05-26-ai-is-opt-in/artifacts/what-we-learned.md).

3. **Submit** `POST /api/v1/jobs/spiderSite/submit` — the dedicated single-URL
   endpoint (richest validation):

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/jobs/spiderSite/submit" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "payload": {
         "url": "https://example.com",
         "mode": "leads",
         "extract_team": true,
         "extract_company_info": true
       },
       "priority": 5
     }'
   ```

   Response (`201`): `{ "job_id": "...", "status": "queued", ... }`.

   The flow facade `POST /api/v1/flows/siteScraper/run` with `{"input": {...}}` is
   the equivalent single-mode call when you're driving everything through the
   Flows surface — it returns `{ "run_id": "..." }` instead (and `run_id` is the
   `job_id` you read back below). Both reach the same SpiderSite worker.

4. **Watch** — poll `GET /jobs/{job_id}/status` no faster than every 3–5s, or use
   the SSE stream. A small `contacts` crawl is ~5–15s; a `full` AI run on a large
   or JavaScript-heavy (SPA) site can be a minute or two. See the foundation's
   [run-modes-and-progress.md](../../../references/run-modes-and-progress.md).

5. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   The crawl's contacts also auto-land in your normalized CRM (queryable via
   IDAP). See [read-results.md](read-results.md).

## Key fields (`SpiderSiteJobPayload`)

| Field | Default | Notes |
|---|---|---|
| `url` | — (required) | website to crawl; include `https://` (1–2048 chars) |
| `mode` | `contacts` | `contacts` / `compendium` / `leads` / `full` — sets pages + AI |
| `max_pages` | `10` | 1–**50** cap on pages. `full`'s ~100-page budget comes from the mode, not this field — you can't set `max_pages` above 50. |
| `overrides` | none | override mode defaults, e.g. `{"max_pages": 20}` |
| `enable_spa` | `true` | render JS-heavy sites with a headless browser (slower) |
| `extract_team` / `extract_company_info` / `extract_pain_points` | `false` | AI features, ~500 tokens each |
| `product_description` + `icp_description` | none | CHAMP lead scoring — **both required together** (+~1,500 tokens) |
| `compendium` | enabled (`fit`) | markdown dump config — see [crawl-options.md](crawl-options.md) |
| `custom_ai_prompt` | off | run your own prompt over the compendium → `custom_analysis` |
| `priority` | `0` | 0–10, higher runs first |
| `test` | `false` | route to the test queue (dev only) |

## Gotchas

- **Emails are extracted, not verified.** This flow has no SMTP-verify stage — the
  `emails[]` it returns are scraped off the page. If the user needs *deliverable*
  emails, run the [maps-site-verify-vayapin](../../maps-site-verify-vayapin/recipes/run-single.md)
  lead chain (which adds SpiderVerify) instead.
- **AI is opt-in.** `contacts`/`compendium` spend zero AI tokens. Don't promise
  team members or company vitals unless you enabled `leads`/`full` or the explicit
  `extract_*` flags.
- **CHAMP needs both halves.** `product_description` alone (or `icp_description`
  alone) is a `422`. Supply both or neither.
- **SPA sites are slower.** `enable_spa` is on by default; a React/Vue/Angular site
  rendered with Playwright takes ~25–35s per page vs ~8–12s — set the user's
  expectation, and don't crank `max_pages` on a heavy SPA.
- **Big crawls don't come back inline.** A large `compendium` (>10 MB) is returned
  as a download URL, not inline — see [the compendium-storage learning](../learnings/2026-05-26-large-compendium-returns-a-url/artifacts/what-we-learned.md).

## Verify

- Got a `job_id`/`run_id` and `status: queued` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- `crawl_status` in the results is `success`/`partial` and `pages_crawled` > 0 —
  see [results-shape.md](results-shape.md). Run
  [scripts/verify-site-complete.sh](../scripts/verify-site-complete.sh) for a
  one-shot audit.
