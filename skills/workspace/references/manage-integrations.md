# Reference — Per-brand API-key integrations (provider keys)

Manage the LLM-provider API keys attached to a brand (OpenRouter, Mistral, etc.).
These are **the brand's own keys** used when its jobs/agents call providers
directly. Owner/admin only for writes. Migrated here from the former
`publish-skills/manage-brands` skill.

> Sibling: `@spideriq/admin-skills` → `integrations` is a **richer** surface
> (spend tracking, billing sync, more providers like Smartlead/SpiderMail,
> reset-usage). Use that when the user needs spend/health analytics; use these
> four methods for straightforward add/test/remove of a brand provider key.

## Steps

1. **Resolve brand_id + role** (`listBrands` → integer id + `membership_role`).
2. **List what's there:** `GET /brands/42/integrations`.
3. **Add a key (owner/admin):** `POST /brands/42/integrations` with
   `{provider, api_key, label?, daily_limit?, billing_mode?, subscription_tier?}`.
4. **Always test after adding:** `POST /brands/42/integrations/{id}/test`.
5. **Remove when rotated/leaked:** `DELETE /brands/42/integrations/{id}`.

To register a key as a **flat-fee subscription plan**, first list the curated
packages (`GET /brands/42/gate/subscription-tiers?provider=minimax`) and pass the
chosen `tier_key` as `subscription_tier` with `billing_mode=subscription`. A
subscription (or `paid`) key is **private to the brand** — it is force-de-pooled
and never joins the shared litellm pool.

## WRONG → RIGHT

**WRONG — echoing the key back to the user / logging it**
```
"I've added your OpenRouter key sk-or-v1-abc123…"   # NEVER repeat the secret
```
**RIGHT — confirm by reference, not by value, and test it**
```bash
curl -X POST https://spideriq.ai/api/v1/brands/42/integrations \
  -H "Authorization: Bearer $OPVS_PAT" -H "Content-Type: application/json" \
  -d '{"provider":"openrouter","api_key":"<secret>","label":"prod","daily_limit":50000}'
# then:
curl -X POST https://spideriq.ai/api/v1/brands/42/integrations/itg_9a/test \
  -H "Authorization: Bearer $OPVS_PAT"
# → "Added OpenRouter key 'prod' and verified it — it's live."
```

**WRONG — deleting a key without warning**
A `DELETE` is immediate; active campaigns/agents using that key lose it.
**RIGHT** — confirm intent first, and prefer adding the replacement key before
removing the old one (no provider gap).

## Verify

- After create: `listIntegrations` shows the new key; `testIntegration` returns OK.
- After delete: the integration id is gone from `listIntegrations`.

## Gotchas

- **403** on create/delete = caller is `client_user`. Check `membership_role` first.
- `api_key` is a **secret** — never echo, never put it in a board comment or log.
- `daily_limit` guards against runaway provider spend — set one on shared keys.
- `subscription_tier` takes a **tier_key** (e.g. `minimax_max`) from
  `listSubscriptionTiers`, NOT the human label; setting it seeds the metering window.
- For spend/health analytics, hand off to `@spideriq/admin-skills` → `integrations`.
