# Free-tier aliases may train on your data

## What happened

SpiderGate's task aliases are split by cost-bias. The cheap ones —
`spideriq/fast`, `spideriq/free`, `spideriq/extraction`, `spideriq/classification`,
`spideriq/summarization` — route to **free-tier** providers (Groq, Mistral-free,
OpenRouter `:free`). Free tiers commonly reserve the right to use your request data for
**model training**, particularly for traffic processed outside the EU.

## Why it's dangerous

The failure is **silent**. Send a customer's name + email through `spideriq/extraction`
and the call returns `200 OK` with a perfectly good answer. Nothing in the response, the
logs, or the metadata says "that PII just entered a training corpus." You only find out at
audit time — or never.

## The rule (the skill's HARD-GATE)

- Treat `spideriq/fast`, `spideriq/free`, `spideriq/extraction`,
  `spideriq/classification`, `spideriq/summarization` as **NOT safe for PII**.
- PII = anything a data-subject could be identified by: names, emails, phone numbers,
  postal addresses, account ids, free text that quotes those.
- For a task that must handle PII, use **`spideriq/lead-analysis`** (premium, the
  designated PII-safe lane) or a BYOK-backed alias — or strip the PII before the call.
- When unsure whether a payload carries PII, assume it does.

## How to apply

Before composing the request body, ask: "does `messages` contain PII?" If yes and the
intended `model` is a free-tier alias, switch the alias (don't just hope). This is a
routing decision, not a prompt tweak — the provider, not the model, is the risk.

> Starting point, not ground truth — the alias→provider mapping changes as providers
> add/remove models. Verify the current chain with `GET /api/gate/v1/aliases` and check
> `app/services/gate/routing/task_config.py` if you need certainty about a specific alias.
