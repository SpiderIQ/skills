# Recipe: run one location (single)

One city, one search, one pipeline. Fastest path; always safe on cost. Use this
whenever the user named **one** place.

## Steps

1. **Compose the query.** Either put the location *inside* `search_query`, or pass
   it as `location` — **not both** (the server builds `"{search_query} in {location}"`
   from `location`, so doing both double-targets the search).

2. **Decide the stages.** The default pipeline is Maps → Site → Verify → VayaPin.
   If the user wants a *lead list* (not published pins), turn VayaPin off
   explicitly — see the HARD-GATE and [vayapin-export.md](vayapin-export.md).

3. **Submit** `POST /api/v1/lead-search`:

   ```bash
   curl -X POST "https://spideriq.ai/api/v1/lead-search" \
     -H "Authorization: Bearer $SPIDERIQ_PAT" \
     -H "Content-Type: application/json" \
     -d '{
       "search_query": "plumbers in Berlin",
       "country_code": "DE",
       "max_results": 20,
       "workflow": { "vayapin": { "enabled": false } }
     }'
   ```

   Response (`201`): `{ "job_id": "...", "status": "processing", "workflow_flow": "...", ... }`.

4. **Watch** — poll `GET /jobs/{job_id}/status` no faster than every 3–5s, or use
   the SSE stream. See the foundation's run-modes-and-progress reference.

5. **Read** when complete:
   ```bash
   curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   Or query the records through IDAP — see [read-results.md](read-results.md).

## Key fields (`LeadSearchRequest`)

| Field | Default | Notes |
|---|---|---|
| `search_query` | — (required) | 1–255 chars; include the location here *or* use `location` |
| `location` | none | optional; server appends it as `"{query} in {location}"` |
| `country_code` | `US` | ISO 2-letter; used by Maps and VayaPin |
| `max_results` | `20` | 1–500 businesses from Maps |
| `lang` | `en` | Maps result language |
| `workflow` | full pipeline | see [per-stage-settings.md](per-stage-settings.md) |
| `test` | `false` | routes to the test queue (dev only) |

## Gotchas

- **VayaPin defaults ON for `/lead-search`** when you omit `workflow` (the request
  builds `vayapin.enabled=true`). If the user did not ask to publish pins, set
  `workflow.vayapin.enabled=false` — published pins are permanent. (HARD-GATE.)
- **Location in both places** wastes the run — pick one.
- **Stage dependencies**: Verify needs Site; VayaPin needs Site. The API rejects
  `verify`-without-`site` with a 422.
- **Auto-export to SmartLead**: add a `workflow.smartlead` block to push the verified
  leads into a SmartLead campaign at completion — see
  [smartlead-export.md](smartlead-export.md) (discover the ids first; it sends real email).

## Verify

- Got a `job_id` and `status: processing` → submitted.
- `GET /jobs/{job_id}/status` reaches `completed` → read results.
- If you disabled VayaPin, `workflow_flow` in the response is a `...maps_site_verify`
  flow (no `_vayapin` suffix) — a cheap confirmation you opted out correctly.
