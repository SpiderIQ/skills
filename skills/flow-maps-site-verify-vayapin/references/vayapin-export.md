# Reference: the VayaPin stage — what it publishes, and how to opt out

VayaPin is the **publish** stage of this chain. When it runs, every business with
a website becomes a **real, public profile on `cs.vayapin.com`** — a live SEO page
with structured data. This is the one stage with an irreversible side effect, so
treat its default with care.

## The irreversibility

- A published pin is a **permanent public page**. There is no API to unpublish it.
- **Deleting the campaign does NOT remove the pins** — `DELETE /campaigns/{id}`
  clears your campaign/location records but the `cs.vayapin.com` pages persist.
- So the decision to run VayaPin is effectively one-way. When the user only wants
  *data* (a lead list to export or do outreach with), VayaPin should be **off**.

## The default is path-dependent — so set it explicitly

| Path | If you omit `workflow.vayapin` | Action |
|---|---|---|
| `/lead-search` (single) | the request builds `vayapin.enabled=true` → **publishes** | set `false` to opt out |
| campaign submit | follows the `vayapin.enabled` you send | set the value you intend |

Don't reason about the default — **always send `workflow.vayapin.enabled`
explicitly** as the value you mean:

```json
// lead list only — NO published pins
{ "workflow": { "vayapin": { "enabled": false } } }

// publish a map profile per business (user explicitly asked for this)
{ "workflow": { "spidersite": { "enabled": true }, "vayapin": { "enabled": true } } }
```

## When to leave it on

Only when the user explicitly wants **published map profiles / local-SEO pages**
(the capability sometimes marketed as "localSeo"). "Build me a lead list",
"find me emails", "get prospects" are **data** requests — VayaPin off.

## Dependency

VayaPin requires SpiderSite (`spidersite.enabled=true`) — it needs website data to
build the profile. `vayapin` on with `spidersite` off → `422`.

## Confirming pins landed

Pins are read as a relation on businesses (there is no `/idap/pins` type):

```bash
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=camp_x&include=pins&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
# businesses[].pins[].vayapin_url   → the live page URL
# businesses[].pins[].pin_name
```

## Verify (the opt-out worked)

- For a single run, the `workflow_flow` in the submit response ends in
  `...maps_site_verify` (no `_vayapin`) when you disabled it.
- After the run, `include=pins` returns **no** pins for the campaign.
- If the user wanted pins: `include=pins` returns a `vayapin_url` per published
  business, and that URL serves a live page.
