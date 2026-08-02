# Model Catalog — pick a model, under a budget

Stop guessing which model to use. The `model-catalog` skill reads SpiderGate's
enriched model catalog — spec, authored profile, benchmarks, **live per-provider
pricing**, reference links, and an **evals aggregate** with provenance on every
sourced field — plus a **public model×task leaderboard** and a per-model **#7 eval
prior**.

- **"Best model for coding under $2/1M?"** — rank on the public leaderboard, filter
  the rows by blended price, pin the winner.
- **Compare a shortlist** — pull the catalog with `fields=` to get exactly the
  capabilities / pricing / per-provider / eval sections you need.
- **Trust but verify** — read the shared eval prior for a model×task before you
  rely on it; a null score means "no prior yet", not zero.

Reads are list-only (not billable); the leaderboard needs no auth. Once you've
picked, pin the concrete model straight into a completion (D7 direct-model).
