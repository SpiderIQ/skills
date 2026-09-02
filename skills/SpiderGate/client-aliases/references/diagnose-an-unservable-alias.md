# Diagnose an alias that exists but will not serve

The most common report on this surface: *"I created it and it does not work."*
Creation validates the SHAPE of the request. It does not validate that the key
behind each slot can serve that model. Those are different questions.

## Steps

1. **`getClientAlias(<leaf>)`.** It reports each slot with the state of the key
   behind it — `provider`, `model`, `key_label`, `cost_type`, `key_is_active`.
   Read that before touching routing.

2. **Walk the slots in order** and check each against the table below.

3. **Fix with `updateClientAlias`**, sending back the FULL slot list.

## WRONG / RIGHT

**WRONG** — reading a refusal as a routing bug and re-sending the request.

```
call client:7/cheap  → refused
call client:7/cheap  → refused        ← nothing changed; the key is the problem
```

**RIGHT** — read the slot key state, then act on what it says.

```
getClientAlias("cheap")
  slot 0  openai/gpt-4o-mini   key_is_active: false   ← this is the answer
```

**WRONG** — "adding" a slot by sending just the new one.

```json
{ "slots": [ { "integration_id": 104, "provider": "groq", "model": "llama-3.3-70b" } ] }
```

That REPLACED the chain. The other slots are gone.

**RIGHT** — read first, send the full list including the new entry.

```json
{ "slots": [
    { "integration_id": 102, "provider": "openai", "model": "gpt-4o-mini" },
    { "integration_id": 103, "provider": "mistral", "model": "mistral-small-latest" },
    { "integration_id": 104, "provider": "groq",   "model": "llama-3.3-70b" }
] }
```

## What a refusal means

| Slot state | Why it is refused | Fix |
|---|---|---|
| the key is not owned by this tenant | a client alias may reach ONLY this tenant's own keys | use one of the tenant's own key ids |
| `key_is_active: false` | the key is deactivated | reactivate it, or point the slot at another key |
| the key row is gone | the integration was deleted | repoint the slot |
| an Anthropic or Gemini-CLI key | inject-only — never usable to fund a slot, even when owned | choose another provider key |
| `enabled: false` on the slot | you disabled it | re-enable it in a full `slots` replacement |
| `enabled: false` on the alias | the whole alias is parked | `updateClientAlias { "enabled": true }` |

## The refusals are deliberate

A slot that cannot serve is **refused, never silently re-routed**. It does not
borrow another tenant's key and it does not fall through to the SpiderIQ pool. A
fallback that "works" would answer from a model the tenant never chose and never
paid for — which is worse than an error, because nothing in the response says so.

So: treat a refusal as information, not as an outage.

## Verify

After the fix, `getClientAlias` shows every intended slot with
`key_is_active: true`, **and** one real call through `use-the-gateway` returns
content. Stop at the read and you have only proved the configuration, not the
routing.
