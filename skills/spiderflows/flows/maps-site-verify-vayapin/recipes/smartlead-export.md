# Recipe: auto-export a campaign's verified leads to SmartLead

Enable `workflow.smartlead` on a campaign (or a single `/lead-search`) and its
**verified** leads are pushed into a **SmartLead outreach campaign automatically
when the run reaches a terminal state** — no separate push step. This is a
FINALIZE step, not a pipeline stage (it rides on `workflow_config.smartlead`; the
outreach auto-push worker runs it at close).

## STOP — this sends real email

The target is a **live** SmartLead campaign; the leads you export get **emailed** by
its sequence. Before enabling:
- **NEVER guess the target.** Discover `connection_id` + `remote_campaign_id` and
  confirm the campaign name with the user (see Step 1).
- Keep **`spiderverify.enabled: true`** — only verified emails export. With verify
  off there is nothing to push.
- If the user only wants a lead *list* (to review, not send yet), do **not** enable
  smartlead — read results via [read-results.md](read-results.md) instead.

## Step 1 — discover the two ids (SpiderMail skill)

`connection_id` and `remote_campaign_id` come from the **SpiderMail** skill's outreach
methods (this flow skill doesn't own them). You need the numeric `brand_id` for the
workspace.

```
# List the outreach connections for the brand → pick the SmartLead one's id.
listOutreachConnections(brand_id)          # → connection_id (e.g. 7)

# List the SmartLead campaigns that connection can see → pick the target.
listOutreachCampaigns(brand_id, connection_id)   # → remote_campaign_id + name + lead_count
```

CLI equivalent: `spideriq mail outreach <brand-id>` then
`spideriq mail outreach-campaigns <brand-id> <connection-id>`.

Confirm the chosen campaign's **name** with the user before continuing.

## Step 2 — enable smartlead on the run

Add the `smartlead` block to `workflow`. Campaign:

```bash
curl -X POST "https://spideriq.ai/api/v1/jobs/spiderMaps/campaigns/submit" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "search_query": "plumbers",
    "country_code": "BB",
    "filter": { "mode": "all" },
    "max_results": 100,
    "workflow": {
      "spidersite":  { "enabled": true, "mode": "leads" },
      "spiderverify": { "enabled": true },
      "vayapin":     { "enabled": true },
      "smartlead": {
        "enabled": true,
        "connection_id": 7,
        "remote_campaign_id": "3534935",
        "only_with_vayapin_seo": false
      }
    }
  }'
```

Single search: the same `workflow.smartlead` block works on `POST /lead-search`.

## `workflow.smartlead` fields

| Field | Required | Notes |
|---|---|---|
| `enabled` | yes | `true` to auto-export at completion (default `false`) |
| `connection_id` | yes | `mail_outreach_connections.id` — from `listOutreachConnections` |
| `remote_campaign_id` | yes | target SmartLead campaign id — from `listOutreachCampaigns` |
| `remote_campaign_name` | no | display snapshot for notifications only |
| `limit` | no | push at most N new leads (trims to the account cap instead of failing) |
| `only_with_vayapin_seo` | no | export only businesses that got a VayaPin SEO pin |
| `field_map` | no | omit — backend defaults already map company, location, and the VayaPin pin_name |

## What exports (and what doesn't)

- **Only leads with a VERIFIED email** are eligible. Businesses with no email — or a
  found-but-unverifiable email — are skipped. Expect the exported count to be well
  below the businesses-found count (many SMBs have no reachable email).
- Idempotent: a lead already pushed to that SmartLead campaign is not re-added.
- Per-account lead cap applies; `limit` trims instead of failing the close.

## Verify

- Campaign reaches a terminal state (`completed`/`degraded`).
- Push outcome: `getOutreachPushStatus(brand_id, connection_id)` (SpiderMail) shows
  the per-campaign pushed count, or check the SmartLead campaign's lead count.

## Known caveat (fields)

Exported leads currently carry `location` as the **country code** and **omit the
VayaPin pin_name** custom field, because the source `leads` table isn't fully
populated by the pipeline write-back (tracked separately). The export wiring is
correct; the field completeness fix is a backend follow-up. If rich fields
(pin_name, city) matter for the outreach copy, flag it before relying on them.
