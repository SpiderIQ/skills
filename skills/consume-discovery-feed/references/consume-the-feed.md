# Reference — Consume the discovery feed

The procedure to drain the free-LLM discovery feed on a schedule.

## Steps

1. **Pull the queue.** `listDiscoveryFeed(limit=100)`. It returns only rows the
   monitor has already notified super-admins about (`notified_at` set) and NOT yet
   carded (`kevin_carded_at IS NULL`), oldest-discovered first. An empty list is
   the normal, common outcome — nothing new since the last tick. Stop if empty.

2. **For each row, research the provider.** The row is a LEAD (from a public
   free-LLM index), not verified truth. Before proposing anything, confirm:
   - Is the provider real and currently offering this model for free?
   - Auth style + API base (is it an OpenAI-compatible endpoint we can reach)?
   - Tool-calling support (matters for tool aliases)?
   - Any signup / rate-limit requirements (the `requirements` / `limits` fields)?
   Never fabricate a fact you could not confirm — the same rule as catalog
   authoring. A row you cannot verify gets a card that says "unverified, needs a
   human look", not a fabricated onboarding.

3. **File the card.** On the curation board `e4c11722` (SpiderGate Model Catalog
   Curation), create a "research + onboard provider `<provider_slug>`" card with
   your findings + a recommendation (onboard / skip / needs-human). This is the
   durable, human-visible artifact.

4. **Propose onboarding (if warranted).** Hand off to `author-catalog.addModel`:
   - Brand-NEW provider → `addModel` records a `proposed` onboarding row and
     returns HTTP 202. A human approves the signup
     (`POST /providers/onboarding/{name}/approve`) before it is wired. You are
     done proposing; do not expect it live.
   - Already-approved provider, new model → `addModel` inserts the card directly
     (201). Then `enrich-catalog` can fill its facts.

5. **Stamp it carded — LAST.** `markCarded(item_id)`. `stamped=true` = you stamped
   it; `stamped=false` (HTTP 200) = it was already carded (idempotent no-op).
   Stamping last means if you crash between the card and the stamp, the row
   re-appears next tick (at-least-once) instead of being silently lost.

6. **Repeat** until `listDiscoveryFeed` is empty.

## Verify

- After a tick: every processed row has a card on e4c11722 and is stamped
  (re-running `listDiscoveryFeed` no longer returns it).
- A proposed brand-new provider shows up in `GET /providers/onboarding` as
  `proposed` (pending a human) — NOT as an approved/live provider.

## Gotchas

- **Stamp order is load-bearing.** Card first, stamp last. Never the reverse.
- **Cold-seed rows are hidden on purpose.** They have `notified_at IS NULL` and
  won't appear here — don't try to reach them; they were the initial 80-row seed
  and carding them would spam the board.
- **A lead is not truth.** Research before proposing; leave a visible gap rather
  than invent a capability.
