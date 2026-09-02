# A create that succeeds is not an alias that serves

## What happened

The client-alias surface has two independent gates, and they run at two
different times:

```
  createClientAlias   →  validates the SHAPE of the request   (201)
  a real completion   →  validates that a slot CAN SERVE      (refusal)
```

A `201` says the body was well-formed: the name matched the pattern, there were
between 1 and 16 slots, and each carried `integration_id`, `provider` and
`model`. It says nothing about whether key `102` exists, is active, belongs to
this tenant, or is allowed to fund a slot at all.

So the natural report is *"I created it and it does not work"* — and the natural
next move, re-sending the completion, changes nothing.

## Why the gap is deliberate

Resolution enforces that a client alias reaches **only** keys the tenant owns.
When a slot's key cannot serve, the slot is **refused** — it is never silently
re-routed to another key, and never to the SpiderIQ pool.

That refusal is the safety property, not a defect. A fallback that "worked"
would answer from a model the tenant did not choose and did not pay for, and
nothing in a 200 response would say so. An error you can read beats an answer you
cannot trust.

Which means the create-time gate *could* not do this work: at create time we
know which key id was named, but the question "can this key serve this model
right now" is a runtime question with a runtime answer.

## What to do instead

**Read the slot key state before diagnosing routing.** `getClientAlias` reports,
per slot: `provider`, `model`, `key_label`, `cost_type`, `key_is_active`. The
answer is almost always visible there.

The refusal classes worth knowing:

| Cause | What you see |
|---|---|
| key not owned by this tenant | the ownership filter returns nothing for it |
| key deactivated | `key_is_active: false` |
| key row deleted | the slot references an id that no longer resolves |
| Anthropic / Gemini-CLI key | inject-only — never usable to fund a slot, even when owned |

## The general shape

**An intermediate success is not the outcome.** "The row was created", "the
symbol is in the bundle", "the key is active" — each is a precondition, and none
of them is "a request came back with content in it". Verify at the layer the
user actually cares about, which here means one real completion naming the
alias.

> Learnings are starting points, not ground truth. Verify against current
> behaviour before relying on any specific refusal string.
