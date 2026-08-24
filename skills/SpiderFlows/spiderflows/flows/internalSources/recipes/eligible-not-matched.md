# `eligible_leads`, never `matched_leads` — the one number that matters

Every sizing call on this surface returns **two** counts. Quoting the wrong one
is the most likely way to mislead a user on this whole flow.

```
matched_leads    how many leads your FILTER selects
eligible_leads   how many of those would actually GAIN from the stages you named
```

**Report `eligible_leads`.** Always.

## Why the gap is normal, not a bug

Gate 2 asks a different question from the filter. A lead is *eligible* only if it
is still missing at least one of the stages the new run would enable. In a mature
corpus most leads have already been crawled and verified, so:

```
"select 5,000, enrich 200"
```

is the **ordinary** reading, not an anomaly. A user told "5,000" and then billed
for 200 is confused; a user told "5,000" and then billed for 5,000 because the
corpus happened to be cold is *shocked*. Only one number is right in both cases.

## It is also the number the system itself uses

`eligible_leads` — not `matched_leads` — decides:

- whether the run passes the **per-job record ceiling** (default 25,000),
- the **cost**, which is `eligible_leads × stages`,
- how long it runs.

So quoting `matched_leads` does not merely inflate the answer; it quotes a figure
no part of the system will act on.

## Eligibility is scoped to the stages you name

This is why `stages` is required everywhere and never defaults.

```
stages=[spiderverify]              → a lead with a crawl but no verified email is ELIGIBLE
stages=[spidersite, spiderverify]  → the same lead is eligible for the verify half
```

A lead missing only VayaPin is still eligible for a VayaPin-only run. Change the
stage set and both counts change — so a count is only meaningful **paired with
the stages it was measured against**. Never carry a count from one stage set to
another.

## A spread of zero is a signal

If `eligible_leads == matched_leads` on a large selection, either the corpus is
genuinely cold for those stages, or the stage set is one nothing has ever run.
Worth saying out loud to the user rather than quietly submitting: on an
established account it usually means the stage list is not what they meant.

## Practical sequence

```bash
# 1. size it — free, writes nothing, iterate here
spideriq bulk-source count --stages spidersite,spiderverify --filter-file ./f.json
#    → "812 eligible of 9,904 matched"

# 2. show the human WHICH leads, if the number is surprising
spideriq bulk-source select --source-kind corpus_query \
  --stages spidersite,spiderverify --filter-file ./f.json
#    → selection_id + the same eligible count, now persisted. Still spends nothing.

# 3. confirm 812 x 2 stages with the user, THEN submit.
```

Steps 1 and 2 spend nothing. Only `submit-internal` does.
