# Quote `eligible_leads`, not `matched_leads`

## The two numbers

Every sizing call on the internal surface returns both:

```
matched_leads    what your FILTER selects
eligible_leads   how many of those would actually GAIN from the requested stages
```

`eligible_leads` is **Gate 2**: leads still missing at least one stage you asked
for.

## Why the gap is the normal case

On a mature corpus most rows have already been crawled and verified, so

```
"select 5,000, enrich 200"
```

is the ordinary reading — not a bug, not an anomaly, and not a sign the filter is
wrong. The design says so in as many words (§6.5).

## It is also the only number the system acts on

`eligible_leads` decides the per-job **record ceiling** check, the **cost**
(`eligible × stages`), and the **runtime**. So quoting `matched_leads` is not
merely optimistic — it quotes a figure no part of the system will use.

And it fails in both directions. A user told "5,000" and billed for 200 is
confused; a user told "5,000" and billed for 5,000 because the corpus happened to
be cold is *shocked*. Only `eligible_leads` is right in both cases.

## 🔴 A count is only valid for the stages it was measured with

Eligibility is scoped to the stage set:

```
stages=[spiderverify]              → a lead with a crawl but no verified email IS eligible
stages=[spidersite, spiderverify]  → same lead, different count
```

Change the stages and both numbers change. **A count carried from one stage set
to another is simply a wrong answer**, delivered confidently. That is why
`stages` is REQUIRED — and deliberately un-defaulted — on `past-runs`, `count`,
`leads` and `selections`: a default would silently answer a question the user did
not ask, about a number they are about to size a purchase against.

## A spread of zero is worth mentioning

If `eligible_leads == matched_leads` on a large, established account, the stage
list is probably not what the user meant. Say so before submitting.

## See also

- `recipes/eligible-not-matched.md`
- `scripts/verify-internal-complete.sh` — the post-run check is a DELTA on this
  same number, for the same reason.
