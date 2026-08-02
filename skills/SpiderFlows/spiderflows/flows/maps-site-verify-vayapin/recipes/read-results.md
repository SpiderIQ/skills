# Recipe: read what a run produced

Two paths: a quick one-shot dump, or queryable IDAP reads. Prefer IDAP for
anything you'll page through or filter.

## Single run → `/jobs/{job_id}/results`

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Returns the aggregated pipeline output for that one query. Good enough when you
ran a single `/lead-search` and just want everything once.

## Campaign → IDAP, by `campaign_id`

This is the read surface you want for campaigns — paged, projectable, flaggable:

```bash
# businesses + their emails, phones, domains, and any published pins
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=camp_x&include=emails,phones,domains,pins&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

| You want | Call |
|---|---|
| businesses for a campaign | `GET /idap/businesses?campaign_id=<id>` |
| just verified emails | `GET /idap/emails?campaign_id=<id>` |
| contacts (people) | `GET /idap/contacts?campaign_id=<id>` |
| phones | `GET /idap/phones?campaign_id=<id>` |
| the full aggregate in one shot | `GET /jobs/spiderMaps/campaigns/<id>/workflow-results` |

### Paging

`limit` is 1–500 (default 100). Follow the `cursor` from each response until it's
empty. For incremental re-pulls, use `since`/`until` timestamps instead of
re-reading the whole set.

### Project fewer fields

`?fields=name,domain,phone_e164` returns only those columns — fewer tokens when
you don't need the full record.

## Reading published pins

`pins` is **not** a standalone IDAP type — read pins as a relation on businesses:

```bash
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=camp_x&include=pins&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
# businesses[].pins[].vayapin_url   → the live page
# businesses[].pins[].pin_name
```

## Gotchas

- **Don't parse progress endpoints for data.** `status`/`stage-progress` report
  *how far*, not *what was found*. IDAP and `/results` are the data surfaces.
- **`GET /idap/pins` 422s** — there is no `pins` resource type; use `include=pins`.
- **Unknown `include` values are silently dropped** — if an expansion is missing,
  re-check the spelling against the valid set
  (`emails,phones,domains,contacts,pins` for businesses).
- **Tenant isolation**: you only ever see your own `client_id`'s records.

## Verify

- `GET /idap/businesses?campaign_id=<id>` returns rows with the expected count
  (compare to `total_businesses` from `workflow-results`).
- Verified emails carry a `status` of `valid`/`risky`/etc. and a `score` (0–100).
- If you ran VayaPin, `include=pins` yields a `vayapin_url` per published business.

For the exact field list of a business record, see
[campaign-results-shape.md](campaign-results-shape.md).
