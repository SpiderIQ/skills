# Operate a gateway key — config, health, billing

The non-policy side of the vault: a key's config, its health, and its billing
snapshot. (Its usage POLICY is a separate, human-gated flow —
[policy-propose-decide.md](policy-propose-decide.md).)

## Steps

- **Edit config** — `updateKey(key_id=<id>, …)` sets any of: `key_label`,
  `is_active`, `is_primary`, `priority` (0–100), `share_with_pool`, `daily_limit`,
  `minute_limit`, `spend_limit_amount` / `spend_limit_period` / `spend_limit_action`.
  Applies immediately. At least one field besides `key_id` is required.
- **Reset health** — `resetKeyHealth(key_id=<id>)` clears `consecutive_failures` and
  returns the key to the healthy pool. Use *after* you've fixed why it was failing
  (e.g. rotated a revoked credential).
- **Check billing support** — `listBillingCapabilities()` lists every provider with
  `has_billing_api` (whether a live billing adapter exists). Filter with
  `has_billing_api=true`.
- **Sync billing** — `syncKeyBilling(key_id=<id>)` refreshes the cached balance +
  usage (today/month) from the provider adapter. Only meaningful for providers whose
  `has_billing_api=true`.

## Gotchas

- **`updateKey` is non-policy only.** It cannot set `usage_policy` /
  `allowed_activities` / `allowed_consumers` — those are propose→approve
  ([policy-propose-decide.md](policy-propose-decide.md)). It also cannot change the
  API key itself or the provider.
- **`syncKeyBilling` on an unsupported provider returns an `error` field**, not a
  balance. Check `listBillingCapabilities` first so you know what to expect.
- **`resetKeyHealth` only resets the counter.** If the root cause (revoked key,
  provider outage) persists, the key trips back to unhealthy on the next failure.
- **Deactivating vs deleting.** `updateKey(is_active=false)` takes a key out of
  selection without losing it; there is no delete method in this skill (a delete
  endpoint exists but is intentionally not surfaced as an agent tool).

## Verify

- After `updateKey`: the response `updated` array lists exactly the fields written.
- After `resetKeyHealth`: the key's health returns to healthy; re-read via the
  admin keys list / dashboard.
- After `syncKeyBilling`: `billing_synced_at` advances and `cached_balance` /
  `cached_usage_*` reflect the provider's current numbers (or an `error` string if
  the provider has no adapter).
