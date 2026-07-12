# No idempotency key → `place_id` is the exactly-once key

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

Social Media Enrichment is a **paid** recovery — a successful recovery spends a
credit. And, like many async submit APIs (Postmark says the same of email sends),
it has **no idempotency key**. So this:

```bash
spideriq social enrich --facebook fb.com/acme   # recovers an email, spends 1 credit
spideriq social enrich --facebook fb.com/acme   # recovers the SAME email, spends ANOTHER credit
```

double-charges. Nothing dedupes the two submits on its own.

## The fix — pass `place_id`

The `place_id` (the business's Google place_id) is the **exactly-once recovery /
meter key**. When you pass it, the service recognises a business it has already
recovered and avoids spending a second credit:

```bash
spideriq social enrich --facebook fb.com/acme --place-id ChIJ0x1a2b3c4d5e6f
```

Pass it whenever you have one. Omit it only for a genuine one-off where the
business has no stable id.

## A credit is spent only on a real recovery

- `credits_spent > 0` **only** when the job returns `status: recovered` with new
  fields.
- Every self-skip — `has_email`, `no_social_handle`, `not_entitled`, `over_cap`,
  `sc_unavailable` — costs **nothing** (`credits_spent: 0`).

So the cost model is "pay only when we actually find something new," and the
`place_id` key is what keeps a retried business from being billed twice for the
same find.

## The rule

- Always pass `place_id` when you have one.
- Submit **once**; if you're unsure the first submit landed, check the job's
  result (or `list_jobs`) before resubmitting — don't fire a blind retry.
- Read `credits_spent` / `cost_usd` on the result to see what a recovery actually
  cost.
