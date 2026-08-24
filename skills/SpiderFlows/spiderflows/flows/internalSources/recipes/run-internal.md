# Running an internal enrichment run

Five calls, in order. The first four spend nothing.

```
fields    → count → select → (confirm with the human) → submit-internal
```

`past-runs` replaces the first two when the user is pointing at a past campaign
rather than describing a filter.

---

## A. "Re-run the Berlin campaign, with verify this time" — `unenriched_run`

No filter. The provenance IS the selection.

```bash
# What could be re-enriched, and how much of it would gain
spideriq bulk-source past-runs --stages spiderverify
```
MCP: `list_bulk_past_runs`.

`--stages` is required and deliberately has no default: every `eligible_leads` in
the response is scoped to it. A defaulted stage set would answer a question the
user did not ask, about a number they are about to size a purchase against.

```bash
spideriq bulk-source select \
  --source-kind unenriched_run \
  --campaign camp_abc123 \
  --stages spiderverify
# → selection_id sel_…, eligible_leads 1,204
```

**Too big?** A campaign over the record ceiling splits by location:

```bash
spideriq bulk-source past-runs --stages spiderverify --kind job --campaign camp_abc123
spideriq bulk-source select --source-kind unenriched_run --job job_xyz --stages spiderverify
```

That is the sanctioned escape hatch, not a workaround — run the pieces.

---

## B. "Everyone with a website but no email" — `corpus_query`

Author the AST first ([build-a-filter.md](build-a-filter.md)), then:

```bash
spideriq bulk-source count  --stages spidersite --filter-file ./f.json
spideriq bulk-source select --source-kind corpus_query --stages spidersite --filter-file ./f.json
```
MCP: `count_bulk_corpus_leads` → `create_bulk_selection`.

Show the human a sample if the count is surprising — `browse_bulk_corpus_leads`
(CLI: not exposed; use MCP or HTTP) returns a keyset-paginated page. Ten rows
settle "does this filter mean what you think" in a way a count never does.

---

## C. Submit — this is the call that spends

```bash
spideriq bulk-source submit-internal \
  --selection sel_abc123 \
  --source-kind corpus_query \
  --no-verify
```
MCP: `submit_bulk_internal_sourcing`.

HTTP:

```jsonc
POST /api/v1/bulk-lead-sourcing/submit
{
  "source": {
    "provider": "internal",
    "source_kind": "corpus_query",
    "selection": { "selection_id": "sel_abc123" }
  },
  "settings": { "workflow": {
    "spidersite":   { "enabled": true },
    "spiderverify": { "enabled": true },
    "vayapin":      { "enabled": false }
  }}
}
```

Returns **202** with a `job_id`. There is no bulk-specific status route — poll
`getJobStatus` with that `job_id`, and read leads with `getJobResults` / IDAP.
The envelope is byte-identical to a campaign's.

### 🔴 The filter is not accepted here, and there is no field for it

The submit carries the **id alone**. That is the entire cross-tenant safety
argument: a body that could carry a predicate is a body that could carry another
tenant's predicate, and the only thing standing between it and their rows would
be application code remembering to check. An id resolved inside a
`WHERE client_id = <caller>` has no such seam.

An id naming no selection this account owns is **404** — never 403, which would
confirm the id exists.

### ⚠️ Enable only the stages you sized against

The selection was counted against a stage set. Enabling a stage you did not count
changes the bill without changing the number you quoted.

### ⚠️ `vayapin` mints PERMANENT public pages

Off unless explicitly set, and it stays that way. Turning it on for a 4,000-lead
selection publishes 4,000 public profile pages that do not come back.

---

## What a selection is, and how long it lasts

A selection is a **validated, sized, persisted handle** — not a list of ids and
not a snapshot of rows. Creating one queues nothing and spends nothing, so
creating several and submitting one is a perfectly good way to work.

The corpus keeps moving underneath it, so the count at submit can differ slightly
from the count at create. That is expected: the run is materialised against the
corpus as it is when it runs.

---

## Verifying it actually worked

```bash
bash flows/internalSources/scripts/verify-internal-complete.sh <job_id>
```

Do not read a `completed` status as success on its own — see the script's own
comments for why the status code is the weakest available evidence here.
