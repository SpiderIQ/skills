# Whose key pays — BYOK + `billed_usd: 0`

Media generation uses the **brand's OWN provider key** (BYOK — bring your own key),
not a shared pool. This has two consequences agents misread.

## `billed_usd: 0` is EXPECTED, not "free"

The response's `est_cost` shows a `billed_usd` of **0** for a BYOK generation. That is
correct: SpiderGate does not charge per request for media on your own key — BYOK is
monetized **monthly, by how many keys we manage for you**, not per generation. The
`provider_cost_usd` field still shows the raw provider cost basis (what your own key
was charged upstream). Don't report "0 cost" as "this was free" — it means "billed on
the monthly key-count plan, not this request."

(On an OUR-key/pooled generation, `billed_usd` is `provider_cost × (1 + markup)` and a
media meter fires. Most media providers are paid-key-only, so BYOK is the common path.)

## `503 no_<provider>_key` — register a key

Paid media providers (`fal_ai`, `kie_ai`, `google_ai`, `x_ai`) are never pooled, so a
generation needs a key registered for **that provider on this brand**. If none exists:

```
503  { "error": { "code": "no_fal_ai_key",
                   "message": "No fal_ai key available in the SpiderGate pool for this brand…" } }
```

Fix: register the provider key in the vault (`/dashboard/gate/vault`, Invite Contributor
flow) — one key per provider you want to generate with. `openai` image/TTS can also use
a pooled OpenAI key if the brand has one.

## Gotchas

- A `503 no_<provider>_key` is a **setup** problem, not a transient error — retrying
  won't help until a key is registered. Surface it to the user as "register a `<provider>`
  key," not "try again."
- The key never leaves the server — you pass no key material in the request; identity +
  key resolution happen from your Bearer PAT server-side.
