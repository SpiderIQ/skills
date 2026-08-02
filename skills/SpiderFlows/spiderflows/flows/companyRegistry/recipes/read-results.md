# Recipe: read what a registry lookup produced

Two surfaces: the raw job output (always available, every mode) and the normalized
IDAP `company_registry` type (search + lookup only). The job output is the
guaranteed read; IDAP is for stable columns, paging, and querying many lookups.

## Poll, then read → `/jobs/{job_id}/results`

```bash
curl "https://spideriq.ai/api/v1/jobs/{job_id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
```

The endpoint is also the poll endpoint — its HTTP status is the job state:

| HTTP | Meaning | Do |
|---|---|---|
| `202` | queued / processing | poll again (≥3–5s); `data` is null |
| `200` | job completed | read `data` — **then check `data.success`** |
| `410` | job failed / cancelled | give up; read `error_message` |

## ⚠️ HTTP 200 does not mean "found it" — check `data.success`

The worker posts **every** outcome (including not-found and unsupported-country) to
the completion callback, so a missed lookup is still `status: completed` / HTTP
`200`. The real verdict is the **worker's own** `data.success`:

```
HTTP 200 + data.success: true   → it worked, read the records
HTTP 200 + data.success: false  → the job ran but the lookup didn't land
                                   (data.error tells you why: "Company not found",
                                    "Unsupported country: XX")
```

`vat` is the exception: it's `data.success: true` even for an invalid number — the
verdict there is `data.data.valid`. See
[../learnings/2026-05-26-success-flag-not-http-status/](../learnings/2026-05-26-success-flag-not-http-status/artifacts/what-we-learned.md).

## Where the records live, by mode

The worker response is returned **raw** under the envelope's `data`:

| Mode | Records at | Shape |
|---|---|---|
| `search` | `data.results` | a **list** of candidates (`data.total_results`, `data.sources_queried` alongside) |
| `lookup` | `data.data` | a **single** company record (absent when `data.success:false`) |
| `vat` | `data.data` | a **single** validation result (`valid`, `company_name`, …) |

(Full field-by-field detail: [results-shape.md](results-shape.md).)

```bash
# search: read the candidate list
curl -s "https://spideriq.ai/api/v1/jobs/{id}/results?format=yaml" -H "Authorization: Bearer $SPIDERIQ_PAT"
# → data.results[].{name, registration_number, source, country_code, status}

# lookup: one record (check data.success first)
# → data.data.{name, registration_number, status, address{...}, financials?}

# vat: validity
# → data.data.{valid, company_name, country_code, error?}
```

## Normalized read → IDAP `company_registry` (search + lookup only)

`search` and `lookup` records are normalized (async, shortly after completion) into
the `company_registry` IDAP type — stable columns, paged, projectable, and the
right surface when you ran many lookups:

```bash
# all your registry records, newest first
curl "https://spideriq.ai/api/v1/idap/company_registry?format=yaml&limit=100" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"

# project only what you need (fewer tokens)
curl "https://spideriq.ai/api/v1/idap/company_registry?fields=name,registration_number,vat_number,status&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"
```

Paging/projection/`?format=yaml` work as for any IDAP type; follow `cursor` to the
end. Full IDAP parameter set: the foundation's
[reading-results.md](../../../references/reading-results.md).

## Gotchas

- **`vat` results are NOT in IDAP `company_registry`.** The validation dict has no
  `name`/`source_id`, so the normalizer skips it. Read VAT only via
  `/jobs/{id}/results`. Only `search`/`lookup` land in `company_registry`.
- **`company_registry` is a standalone IDAP type, NOT an `include=` on businesses.**
  `GET /idap/businesses?include=company_registry` silently drops the unknown include
  and returns no registry data. Query `GET /idap/company_registry` directly.
- **Normalization is async** — there can be a short lag between `status: completed`
  and the row appearing in IDAP. `/jobs/{id}/results` is immediate; IDAP catches up.
- **Mode changes the key.** `search` → `data.results` (list); `lookup`/`vat` →
  `data.data` (object). Parse for the right one; don't assume a single shape.
- **An empty `search` result is ambiguous** — "no match" and "the upstream registry
  API failed" both yield `data.success:true, total_results:0` (the worker swallows
  upstream errors). Re-run or narrow the name; don't report a hard failure.
- **The result doesn't echo your input.** For a batch, track `job_id → company`
  yourself, or re-associate via the normalized `name`/`registration_number`.
- **Don't parse `/jobs/{id}/status` for data** — `/results` and IDAP are the data
  surfaces. **Tenant isolation**: you only see your own `client_id`'s records.

## Verify

- `GET /jobs/{job_id}/results` is `200` with `data.success: true` and records in the
  mode-appropriate key (`data.results` for search, `data.data` for lookup/vat).
- For search/lookup, `GET /idap/company_registry` returns rows carrying
  `registration_number` / `status` (after the async normalization).
- `scripts/verify-companydata-complete.sh <job_id>` confirms a record landed,
  reads `data.success`, and flags an out-of-coverage empty as a note, not a failure.
