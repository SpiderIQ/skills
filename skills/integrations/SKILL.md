---
name: integrations
version: 1.0.0
description: Manage API integrations (SpiderIQ, Smartlead, etc.)
client: integrations
client_version: "1.0.0"
category: integration
triggers:
  - /integrations
  - /integrate
  - connect spideriq
  - connect smartlead
  - integration status
requires_auth: true
requires_brand: true
---

# API Integrations Management

Manage third-party API integrations (SpiderIQ, Smartlead, SpiderMail, etc.) for brands -- create keys, monitor health, track spend, and control usage limits.

## Decision Guidance

### Integration Lifecycle

```
listProviders -> createIntegration -> getIntegration (verify) -> active use
                                                              -> updateIntegration (rotate key, adjust limits)
                                                              -> deleteIntegration (decommission)
```

### Available Providers

| Provider | Powers | Setup Needs |
|----------|--------|-------------|
| **SpiderIQ** | Google Maps scraping, website crawling, email verification | API key + workspace name |
| **Smartlead** | Email campaign delivery, warmup, tracking | API key + verified email accounts |
| **SpiderMail** | Direct email sending | API key (deleting integration deregisters mailboxes) |

### Spend & Usage Monitoring

- Use `getSpend` for per-key spend details (balance, daily/monthly usage, currency)
- Use `getProviderSpend` for aggregated view across all keys of a provider
- Use `syncBilling` to fetch fresh balance from the provider API
- Use `resetUsage` to clear daily/minute counters (admin recovery action)

### Key Management Best Practices

- Label keys descriptively (`key_label`) so they are identifiable later
- Set `daily_limit` and `minute_limit` to prevent runaway usage
- Use `spend_limit_amount` + `spend_limit_period` + `spend_limit_action` for budget guardrails
- Set one key as `is_primary` per provider -- this is used by default for API calls
- Use `priority` to control round-robin selection across multiple keys
- Set `billing_mode` to control a key's billing treatment: `auto` (default, defer to the provider's cost_type), `subscription` (flat-fee coding plan -- force-de-pooled, private to the brand), or `paid` (force per-token billing). When marking a key `subscription`, first call `listSubscriptionTiers` and pass the chosen `tier_key` as `subscription_tier` to seed its metering window.

### Permissions

Only brand admins can create, update, or delete integration keys. Client users can view integration status but cannot modify keys.

### Disconnecting Integrations

Before deleting an integration, warn the user about active dependencies:
- Active campaigns using the key will stop
- SpiderMail mailboxes associated with the key will be deregistered
- Existing data (leads, results) is preserved

## Anti-Patterns

- Do not create duplicate keys for the same provider without a clear purpose (e.g., regional keys, load balancing)
- Do not delete a primary key without first setting another key as primary
- Do not skip validation -- always test a new key by checking its integration detail after creation
- Do not reset usage counters as a workaround for hitting limits -- adjust the limits instead

## Error Handling

| Scenario | Action |
|----------|--------|
| Invalid API key (health check fails) | Show error, suggest re-entering credentials |
| Low credits / approaching spend limit | Warn user with current balance and top-up link |
| Integration already exists for provider | Offer to update existing key or create additional key with label |
| Permission denied (non-admin) | Explain that only brand admins can manage integrations |

## Available Methods

| Method | Description |
|--------|-------------|
| `getOverview` | Get aggregated overview of all configured providers for the brand |
| `listProviders` | List available provider templates with required credential fields |
| `listSubscriptionTiers` | List the curated subscription-package catalog (pick a `tier_key` before setting `subscription_tier`) |
| `listIntegrations` | List all integration keys, optionally filtered by provider |
| `getIntegration` | Get details for a single integration key |
| `createIntegration` | Create a new API integration key (incl. `billing_mode` / `subscription_tier`) |
| `updateIntegration` | Update an existing integration key (label, credentials, limits, status, billing treatment) |
| `deleteIntegration` | Delete an integration key permanently |
| `resetUsage` | Reset daily and minute usage counters for a key |
| `getSpend` | Get spend details for a single integration key |
| `getProviderSpend` | Get aggregated spend overview for all keys of a provider |
| `syncBilling` | Trigger a billing sync to fetch current balance from the provider |
