---
name: consume-discovery-feed
description: >
  Consume the SpiderGate free-LLM discovery feed — poll the newly-discovered
  providers/models the daily monitor flagged, file a research + onboarding card
  for each, propose onboarding (a brand-new provider is propose-only), and stamp
  the row carded so it is processed exactly once.
version: 0.1.0
auth: pat (Authorization: Bearer) — gate:catalog:write
---

# Consume-Discovery-Feed

You are the **consumer** of the free-LLM discovery feed. The daily monitor
(the producer) finds newly-listed free LLM providers/models, records them, and
emails super-admins — but it cannot file board cards. **You** turn each flagged
row into a research + onboarding card, and stamp it consumed.

## The two rules that define this skill

> **1. Card once.** Every feed row is carded exactly once. Stamp `markCarded`
> **AFTER** you file the card — stamp-last means a crash re-cards (at-least-once),
> never silently drops a provider.
>
> **2. Propose, don't wire.** A brand-new provider's onboarding is a PROPOSAL
> (author-catalog.addModel → a `proposed` onboarding row, HTTP 202). A human
> approves the signup. You never bring a new provider online yourself.

## Decision tree (the consume tick)

```
1. listDiscoveryFeed  → the un-carded, already-notified rows (oldest first).
      Empty? → nothing new. Stop. (The common case.)

2. For each row:
      a. RESEARCH the provider — is it real, free, tool-capable, an API we can
         reach? (Never fabricate; a lead is not truth.)
      b. FILE a "research + onboard provider <slug>" card on the curation board
         (e4c11722), with what you found + a recommendation.
      c. If it looks worth onboarding → author-catalog.addModel(provider=<slug>, …).
         A brand-new provider → HTTP 202 'proposed' (human approves the signup).
         An already-approved provider's new model → 201 added directly.
      d. markCarded(item_id)  → stamp it consumed. LAST step.

3. Repeat until the feed is drained.
```

## What you must NEVER do

- ❌ `markCarded` before the card exists (a crash then drops the provider forever).
- ❌ Assume a proposed provider is live — it is `proposed` until a human approves.
- ❌ Card the cold-seed rows — they don't appear in `listDiscoveryFeed`
  (`notified_at IS NULL`), on purpose. Don't go around the feed to reach them.
- ❌ Onboard off the lead alone — research first (never-fabricate).

## Layers

- `references/consume-the-feed.md` — the full consume procedure (Steps/Verify).
- `learnings/` — why stamp-last + propose-only, and the producer/consumer split.

## Related skills

- `author-catalog` — where `addModel` (the onboarding proposal) lives. This skill
  hands off to it; it does not itself add a model.
- `enrich-catalog` — fills facts for a model AFTER it is onboarded.
- `gate-health-watch` — the OTHER autonomy loop (routing repair, not discovery).
