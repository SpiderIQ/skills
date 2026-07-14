# The discovery feed is a producer/consumer split

WS2.3 built only the **producer**: a daily monitor that scrapes a public free-LLM
index, writes newly-listed providers/models into `gate_discovered_providers`, and
emails super-admins. It cannot file board cards — the production api-gateway holds
no AgentBoard write credential. So a **consumer** that *does* hold board-write is
required. WS3b is that consumer: the curator agent ("Kevin") polls the feed and
turns each flagged row into a research + onboarding card.

## The two-timestamp seam

The producer and consumer meet on two columns of the same row:

- `notified_at` — the monitor stamps it when it emails super-admins.
- `kevin_carded_at` — the consumer stamps it when it has carded the row.

The consumer's poll predicate is exactly the migration-432 partial index
`idx_gdp_kevin_pending`:

```
notified_at IS NOT NULL AND kevin_carded_at IS NULL
```

This deliberately **excludes the monitor's silent cold-seed** (the initial ~80
rows written with `notified_at IS NULL`), so seeding never spams the board.

## The two invariants that keep it correct

1. **Stamp-last (at-least-once).** File the card, *then* `markCarded`. Stamping
   first and then crashing would drop a provider forever. Stamp-last makes a crash
   re-card next tick; `markCarded` is idempotent (`stamped=false`, HTTP 200, on a
   re-stamp), so at-least-once is safe.
2. **Propose-only for a brand-new provider.** Onboarding hands off to
   `author-catalog.addModel`. For an un-approved provider it records a `proposed`
   `gate_provider_onboarding` row (HTTP 202) that a human approves
   (`POST /providers/onboarding/{name}/approve`, `require_super_admin_or_admin_key`
   — **no PAT path**) before the provider is wired. An already-approved provider's
   new model is added directly (201).

The consumer surface only lists + stamps; it never itself adds a model — the
discovery loop and the authoring surface stay cleanly separated.

## Take-away

When a privileged-but-credential-less service discovers work, hand it to a scoped
agent through a **two-timestamp seam** on the row, poll the `notified AND
un-carded` slice, **stamp last**, and keep the risky action (new-provider
onboarding) **propose-only**.
