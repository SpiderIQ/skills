# Author a provider's editorial (`provider_metadata`)

A provider (openai, anthropic, groq, …) has its own client-facing editorial —
separate from any single model. This is the caption/description, the free-tier
blurb, and the docs/signup links a client sees for the provider itself. It lives
in `provider_metadata`, keyed by `provider_name`, and is a **different path from
model enrichment**.

## Surface

| Do | HTTP | MCP tool | CLI |
|---|---|---|---|
| Author provider editorial | `PATCH /providers/{name}/metadata` | `gate_catalog_provider_set_meta` | `spideriq gate catalog providers set-meta <name> …` |

All under `/api/v1/admin/gate`, `X-Admin-Key` (`SPIDERIQ_ADMIN_API_KEY`), super_admin.

## Endpoint

```
PATCH /api/v1/admin/gate/providers/{provider_name}/metadata
X-Admin-Key: <platform admin key>     # super_admin, from SPIDERIQ_ADMIN_API_KEY
Content-Type: application/json
```

Upsert + COALESCE-preserve: only the fields you send change. An empty body (no
editable fields) is a `400`. Unknown `provider_name` (not in the provider
registry) is a `404`.

## Editable fields (exactly four)

| Field | What clients see |
|---|---|
| `description` | short provider description — OUR words, never copied prose |
| `free_tier_description` | free-tier / trial-credit blurb (empty string if none) |
| `docs_url` | provider docs URL (or an internal `/docs/providers/{name}` route) |
| `signup_url` | where a client gets an API key |

**`logo_url` is NOT editable here** — it's managed by the provider-logo surface,
not this endpoint. Sending it is ignored.

## Example

```bash
curl -X PATCH "https://spideriq.ai/api/v1/admin/gate/providers/openai/metadata" \
  -H "X-Admin-Key: $SPIDERIQ_ADMIN_API_KEY" -H "Content-Type: application/json" \
  -d '{
    "description": "OpenAI provides the GPT-4o multimodal family and the o1 reasoning models through a usage-billed API.",
    "free_tier_description": "OpenAI is a paid, usage-billed API with no ongoing free tier; new accounts may receive limited trial credits."
  }'
# → {"success": true, "updated": ["description", "free_tier_description"]}
```

## Rules

- **Description is OUR words.** Same licensing rule as model descriptions — compose
  from facts, never copy the provider's marketing page (HARD-GATE in SKILL.md).
- **Provider editorial ≠ model enrichment.** Filling a provider's models' specs and
  benchmarks is the enrichment path; this only writes the provider's own copy.
- **Provider API keys are a different skill entirely.** Adding/rotating the
  provider's credentials is the integrations / vault surface
  (`spidergate-manager`), not this.

## Verify

- The response returns `{"success": true, "updated": [<fields you sent>]}`.
- Reload the provider in the client catalog / gate dashboard and confirm the copy
  renders.
