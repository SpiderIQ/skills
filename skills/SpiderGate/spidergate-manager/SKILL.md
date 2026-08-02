---
name: spidergate-manager
version: 1.0.0
description: Manage SpiderGate API key pools — add providers, sync billing, check health, configure limits.
triggers:
  - /spidergate
  - /gate
  - spidergate status
  - manage api keys
  - check key health
  - sync billing
  - add provider key
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "🔑"
---

# SpiderGate Manager — API Key Pool Administration

Manage SpiderIQ's unified API key pool: add keys, sync billing, monitor health, configure spend limits.

## Authentication

Your admin credentials are stored in your workspace:

```bash
exec cat /home/node/.openclaw/workspace/personas/{YOUR_PERSONA}/.spidergate.json
```

Returns:
```json
{
  "api_url": "http://spideriq-api-gateway:3000",
  "admin_token": "your_admin_token"
}
```

**Use the token in all API calls below.**

---

## Quick Commands

### Gateway Overview

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/stats"
```

### List All Keys

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys"
```

### List Keys by Provider

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys?provider_name=openrouter"
```

### List Unhealthy Keys

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys?health_status=unhealthy"
```

---

## Key Management

### Add New Key

```bash
exec curl -s -X POST -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys" \
  -d '{
    "provider_name": "openrouter",
    "api_key": "sk-or-v1-xxxxxxxxxxxx",
    "key_label": "OpenRouter Pool Key",
    "share_with_pool": true,
    "is_active": true,
    "daily_limit": 500,
    "spend_limit_amount": 100.00,
    "spend_limit_period": "monthly",
    "spend_limit_action": "warn"
  }'
```

**Required:** `provider_name`, `api_key`

**Optional:** `key_label`, `share_with_pool`, `is_active`, `daily_limit`, `minute_limit`, `spend_limit_amount`, `spend_limit_period`, `spend_limit_action`, `brands_id`

### Update Key

```bash
exec curl -s -X PATCH -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys/{KEY_ID}" \
  -d '{"is_active": false, "daily_limit": 1000}'
```

### Delete Key

```bash
exec curl -s -X DELETE -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys/{KEY_ID}"
```

---

## Health Management

### Reset Unhealthy Key

```bash
exec curl -s -X POST -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys/{KEY_ID}/reset-health"
```

### Health Status Flow

```
healthy (0 failures) → degraded (1-2 failures) → unhealthy (3+ failures, excluded)
```

---

## Billing & Costs

### Sync Single Key Billing

```bash
exec curl -s -X POST -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys/{KEY_ID}/sync-billing"
```

### Sync All Keys

```bash
exec curl -s -X POST -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/sync-all-billing"
```

### Get Cost Stats

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/stats/cost"
```

### Get Spend History

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/keys/{KEY_ID}/spend-history?days=30"
```

---

## Provider Information

### List Active Providers

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/providers"
```

### Get Provider Registry (All Supported)

```bash
exec curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  "http://spideriq-api-gateway:3000/api/v1/admin/gate/providers/registry"
```

### Supported Providers (18)

| Provider | Billing Sync | Free Tier |
|----------|:------------:|:---------:|
| OpenRouter | Yes | $5 credit |
| fal.ai | Yes | $5 credit |
| Kie.ai | Yes | Limited |
| WaveSpeed | Yes | Limited |
| Groq | No | 14K TPM |
| Cerebras | No | 30 RPM |
| Mistral | No | Limited |
| Google AI | No | 60 QPM |
| Together | No | $5 credit |
| Fireworks | No | $1 credit |

---

## Key Configuration Templates

### Production Pool Key

```json
{
  "share_with_pool": true,
  "is_active": true,
  "priority": 10,
  "daily_limit": 1000,
  "minute_limit": 100,
  "spend_limit_amount": 500.00,
  "spend_limit_period": "monthly",
  "spend_limit_action": "warn"
}
```

### Free Tier Key

```json
{
  "share_with_pool": true,
  "is_active": true,
  "priority": 5,
  "daily_limit": 100,
  "minute_limit": 20,
  "spend_limit_amount": 5.00,
  "spend_limit_period": "daily",
  "spend_limit_action": "block"
}
```

### Brand-Specific Key

```json
{
  "brands_id": 123,
  "share_with_pool": false,
  "is_active": true,
  "priority": 20
}
```

---

## API Reference

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/admin/gate/stats` | Gateway overview |
| GET | `/admin/gate/stats/cost` | Cost breakdown |
| GET | `/admin/gate/providers` | List providers with stats |
| GET | `/admin/gate/providers/registry` | All supported providers |
| GET | `/admin/gate/keys` | List keys |
| GET | `/admin/gate/keys/{id}` | Get key details |
| POST | `/admin/gate/keys` | Create key |
| PATCH | `/admin/gate/keys/{id}` | Update key |
| DELETE | `/admin/gate/keys/{id}` | Delete key |
| POST | `/admin/gate/keys/{id}/sync-billing` | Sync billing |
| POST | `/admin/gate/keys/{id}/reset-health` | Reset health |
| GET | `/admin/gate/keys/{id}/spend-history` | Spend history |
| POST | `/admin/gate/sync-all-billing` | Bulk billing sync |
| POST | `/admin/gate/reset-daily-counters` | Reset counters |
| POST | `/admin/gate/providers/health-check` | Model discovery & health check |

All paths prefixed with `/api/v1/`.

---

## Provider Health Check (Phase 7.1)

Check all providers for dead/new models by querying their live `/v1/models` API.

```bash
curl -s -X POST "$BASE_URL/api/v1/admin/gate/providers/health-check" \
  -H "X-Admin-Key: $ADMIN_TOKEN" | python3 -m json.tool
```

**Returns per provider:**
- `status`: `healthy` (all configured models live), `degraded` (some missing), `error`, `no_keys`
- `models_available`: total models on provider's API
- `models_configured`: how many we use in task aliases + DIRECT_MODEL_MAP
- `models_missing`: configured models that the provider no longer serves (action needed!)
- `models_new_sample`: new models not yet configured (evaluate for routing)
- `free_models`: (OpenRouter only) all models with $0 pricing

**Daily workflow:**
1. Run health check
2. If `models_missing` is non-empty → model was removed by provider, update task aliases
3. If `models_new_sample` has interesting models → evaluate with model test scripts
4. If `free_models` changed → update `spideriq/free` alias

**Providers checked:** Groq, Cerebras, NVIDIA NIM, Mistral, OpenRouter (any provider with keys in `api_integrations`)

---

## Notes

- All API calls require admin token via `X-Admin-Key` header
- Use internal Docker URL: `http://spideriq-api-gateway:3000`
- Pool keys (`share_with_pool=true`) are available to all clients
- Brand keys (`share_with_pool=false`) are private to specific brand
- Health auto-degrades: healthy → degraded (1-2 failures) → unhealthy (3+)
- Unhealthy keys are excluded from selection until reset
