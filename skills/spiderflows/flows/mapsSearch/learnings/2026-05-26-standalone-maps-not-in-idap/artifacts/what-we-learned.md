# Standalone Maps Search results don't land in IDAP

**Starting point, not ground truth — verify against current code.**

## The surprise

The rest of the `spiderflows` skill teaches you to read results through **IDAP**
(`GET /idap/businesses?campaign_id=…`). That's correct for the **lead chain**.
It is **wrong for a standalone Maps Search run** — those businesses are not in
IDAP, and an IDAP query for a Maps Search `job_id` comes back empty.

## Why

- IDAP's normalized `businesses` table is populated by the **campaign /
  workflow** path — `campaign_service` and `workflow_orchestrator` write rows as
  a campaign's locations complete. Those are the only writers of IDAP
  `businesses`.
- A **standalone** `spiderMaps` job (what Maps Search submits) never goes through
  that path. On completion the worker callback:
  - stores the raw result on the job (`jobs.results`), readable via
    `GET /jobs/{job_id}/results`; and
  - dual-writes to the `results` table with **`campaign_id = NULL`** (there's no
    campaign).
  It does **not** insert into the IDAP `businesses` table.

So there's no `campaign_id` to query IDAP by, and no IDAP row to find.

## The rule

For Maps Search, **read `GET /jobs/{job_id}/results`** — full stop. The businesses
are at `data.businesses[]`. (See [`recipes/read-results.md`](../../../recipes/read-results.md)
and [`recipes/results-shape.md`](../../../recipes/results-shape.md).)

Reach for IDAP only when you ran the **lead chain** (`searchLeads` /
`createCampaign`), which normalizes businesses + emails + phones + domains into
IDAP keyed by `campaign_id`.

## Mental model

- **Maps Search (this flow):** one Maps stage → results live on the job →
  `/jobs/{id}/results`.
- **Lead chain (`maps-site-verify-vayapin`):** Maps → Site → Verify → (VayaPin),
  normalized into IDAP by `campaign_id` → `/idap/...`.

Same businesses-shaped data, different read surface, because only the campaign
path does the IDAP ingest.
