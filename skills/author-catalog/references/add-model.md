# Add a model card + onboard a provider (`addModel`, owner-locked)

The `set_meta` methods only **edit** rows that already exist. `addModel`
(`gate_catalog_model_upsert` → `POST /admin/gate/models`) **INSERTs a new**
`gate_model_catalog` card and stamps it `is_curated=TRUE`, so the 6h discovery
sync never clobbers it — exactly like a hand-authored row.

## The owner-lock (why an add can come back "proposed")

Adding a model is gated by the **provider-onboarding taxonomy**
(`gate_provider_onboarding`). Whether the model is wired depends on the
provider's `approval_status`:

| Provider state | `addModel` result |
|---|---|
| **approved** (in the taxonomy as `approved`, OR already serving models in the catalog) | The card **inserts directly** — `created=true`, `status='added'`. |
| **brand-new** (not approved, not already serving) | **No model is wired.** A provider proposal is recorded (`status='proposed'`, `created=false`) and a **human** must approve the provider first. |

This is enforced **server-side**, not by convention: a curator PAT
(`gate:catalog:write`) can **propose** a provider but can **not** approve one.
Approval is `POST /providers/onboarding/{name}/approve`, which is
super_admin / `X-Admin-Key` only — there is no PAT path to it, and it is
deliberately not an MCP tool. *Kevin proposes; a human approves.*

## Steps

1. **Pick the TRUE provider name.** `provider` is the logical provider —
   `minimax`, `zhipu`, `qwen`, `openai` — **never** the litellm wire prefix
   (`openai` is the wire prefix for six providers; using it here mis-files the
   card, the exact root bug WS2 fixed).
2. **Check the provider is addable** (optional but wise): `listProviderOnboarding`
   → is your provider `approved`? If it's a first-time provider it will be
   `proposed` after your first `addModel`.
3. **Add the card:**
   ```
   addModel(provider="zhipu", model_id="glm-4.6",
            display_name="GLM-4.6", owned_by="Zhipu AI",
            context_window=200000, cost_type="paid",
            description="…OUR words, from facts…")
   ```
   → an approved provider returns `{created:true, status:"added", id:<n>}`.
4. **Enrich the facts** — a fresh card carries only what you passed. Run the
   `enrich-catalog` skill to fill context/pricing/benchmarks from
   OpenRouter/LLM-Stats, then author copy with `setModelMeta`.

### Onboarding a brand-new provider

```
# 1. Curator proposes (fills the transport taxonomy so the proposal is complete):
addModel(provider="acme", model_id="acme-large",
         provider_api_base="https://api.acme.ai/v1",
         provider_auth_style="bearer", provider_modality="chat")
#    → {created:false, status:"proposed", …}  (NO model wired)

# 2. A HUMAN approves the provider (super_admin / X-Admin-Key — not the curator):
#    POST /admin/gate/providers/onboarding/acme/approve

# 3. Re-run the SAME addModel → now the provider is approved → card inserts.
```

## Gotchas

- **Idempotent on (provider, model_id).** Re-adding an existing card is a no-op —
  `{created:false, status:"exists", id:<n>}`. To change its copy use `setModelMeta`
  (the int `id`), not `addModel`.
- **`provider` is TRUE, not wire.** See step 1 — the #1 mistake.
- **`cost_type` mirrors `api_integrations.cost_type`:** `free | subscription | paid
  | unknown` (NOT `usage`/`byok`). `tier` is `free | subscription | paid`.
- **A `proposed` result is not an error.** It means the owner-lock did its job —
  surface the message and hand off to a human for approval.
- **This adds a CARD + editorial, not FACTS.** context/pricing/benchmarks still
  come from `enrich-catalog`. A card with `context_window=0` is a stub until enriched.
- **Descriptions are OUR words from facts** — never vendor prose (the licensing
  HARD-GATE in the main SKILL applies to `addModel` too).

## Verify

- `listModels(search="<model_id>")` → confirm the row exists, `is_curated=true`,
  `curated_by="pat:<prefix>"`.
- `listProviderOnboarding(status="proposed")` → the human review queue; a newly
  proposed provider appears here until approved.
