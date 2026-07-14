## consume-discovery-feed

The **consume** half of the SpiderGate free-LLM discovery loop. The daily monitor
(the producer) finds newly-listed free LLM providers/models, records them, and
emails super-admins — but it can't file board cards. This skill lets the curator
agent drain that feed: poll the flagged rows, file a research + onboarding card
for each, propose onboarding, and stamp the row consumed.

### What this skill does

- **`listDiscoveryFeed`** — the un-carded, already-notified rows (oldest first).
  Excludes the monitor's silent cold-seed on purpose. An empty list is the normal
  steady state.
- **`markCarded`** — stamp a row consumed, exactly once. Idempotent; call it LAST,
  after the card exists.

The actual onboarding **proposal** lives in `author-catalog.addModel` — this skill
hands off to it and never adds a model itself.

### The two rules that keep it safe

- **Card once, stamp last.** File the card, then `markCarded`. Stamp-last means a
  crash re-cards (at-least-once) instead of silently dropping a provider.
- **Propose, don't wire.** A brand-new provider's onboarding is a proposal
  (HTTP 202) a human approves before it goes live. You never bring a new provider
  online yourself. And a feed row is a lead, not truth — research before proposing.
