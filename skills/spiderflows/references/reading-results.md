# Reading results — IDAP is the read surface

Progress endpoints tell you *how far along* a run is. **IDAP** is where you read
the *data* — businesses, contacts, emails, phones, domains, and published pins —
filtered by `campaign_id`, paginated, and flaggable.

## The read surfaces, fastest first

| You want | Call |
|---|---|
| a single run's full output | `GET /jobs/{job_id}/results` |
| a campaign's one-shot aggregate dump | `GET /jobs/spiderMaps/campaigns/{id}/workflow-results` |
| queryable / paged / incremental reads of a campaign's records | `GET /api/v1/idap/<type>?campaign_id=<id>` |

For anything beyond "give me everything once", use IDAP — it pages, projects
fields, expands relations, and filters by flag and timestamp.

## IDAP resource types

`GET /api/v1/idap/<type>` lists records of one type within your tenant. Valid
`<type>` values:

```
businesses · domains · contacts · emails · phones ·
company_registry · linkedin_profiles · staff · media · bookings
```

> **`pins` is not a standalone type.** Published VayaPin pins are read as a
> relation **on** businesses — `?include=pins` — not as `GET /idap/pins`
> (that 422s). See "Expanding relations" below.

### List parameters (all optional)

| Param | Default | What |
|---|---|---|
| `campaign_id` | — | scope to one run (the one you almost always want) |
| `include` | — | comma-separated relations to expand (see below) |
| `fields` | — | comma-separated projection — fewer columns, fewer tokens |
| `format` | `json` | `yaml` / `md` for token savings |
| `limit` | `100` | 1–500 per page |
| `cursor` | — | opaque next-page token from the previous response |
| `since` / `until` | — | timestamp window for incremental sync |
| `flags` | — | filter by data-quality flag |
| `sort` / `order` | `created_at` / `desc` | ordering |

```bash
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=camp_x&include=emails,phones,domains,pins&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

## Expanding relations — `include`

`include` hydrates child records in one round-trip. For `businesses` the valid
expansions are:

| `include` value | Gives you |
|---|---|
| `emails` | emails matched to the business domain |
| `phones` | phones linked to the business |
| `domains` | the business's domain record(s) |
| `contacts` | people found for the business |
| `pins` | published VayaPin pins — each carries `pin_name` and `vayapin_url` |

Unknown `include` values are **silently ignored** (no error) — so a typo gives you
fewer fields, not a failure. Spell them as above.

## Confirming published pins

If a run published VayaPin pins and you need to confirm they landed:

```bash
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=camp_x&include=pins&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
# → businesses[].pins[].vayapin_url  (the live cs.vayapin.com page)
#   businesses[].pins[].pin_name
```

## Other IDAP verbs

- `GET /idap/<type>/{id}` — one record by id, also supports `include` + `format`.
- `GET /idap/<type>/search?q=...` — full-text search within a type.
- `GET /idap/<type>/stats` — aggregate counts.
- `GET /idap/<type>/resolve?...` — resolve a record by an external identifier.
- `GET /idap/<type>/duplicates?...` — find records sharing a common external key.

The per-flow skill's `references/campaign-results-shape.md` documents the exact
fields a finished business record carries (Maps + Site + Verify), so you know what
you can read back before you ask for it.
