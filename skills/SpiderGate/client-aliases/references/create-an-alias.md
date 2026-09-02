# Create a client alias end to end

Build a named fallback chain the tenant can then call as one model name.

## Steps

1. **Get the tenant's real provider key ids first.** Every slot needs an
   `integration_id`, and it must be a key this tenant owns. Read them from the
   brand integrations surface. Do not proceed on a guess — see Gotchas.

2. **Decide the order.** Slots are a fallback chain, slot 0 first. Put the model
   you actually want at 0 and the cheaper/more-available ones after it.

3. **Create it, unarmed if you are not sure:**

   ```json
   {
     "name": "cheap",
     "description": "cost-first chain for bulk summarisation",
     "enabled": false,
     "slots": [
       { "integration_id": 102, "provider": "openai",  "model": "gpt-4o-mini" },
       { "integration_id": 103, "provider": "mistral", "model": "mistral-small-latest" }
     ]
   }
   ```

   `enabled: false` is the only way to author without publishing. The default is
   `true`, and `true` means live.

4. **Read it back with `getClientAlias`** and check each slot's `key_is_active`
   and `cost_type` before arming it.

5. **Arm it** with `updateClientAlias { "enabled": true }`.

6. **Call it** through `use-the-gateway`, with `model: "client:<brand>/cheap"`.
   The brand number is in the alias's full name as returned by the read.

## Gotchas

- **`integration_id` has no default, deliberately.** A slot with no owned key is
  refused, never funded from the SpiderIQ pool. If you invent an id, the alias
  creates cleanly and can never serve.
- **`name` is the leaf.** `cheap`, not `client:7/cheap`. The prefix is generated
  server-side; supplying it is what makes people think aliases collide with
  `spideriq/*`. They cannot.
- **Anthropic and Gemini-CLI keys cannot fund a slot**, even when the tenant owns
  them — they are inject-only. Choose a different provider key.
- **Creating requires the `admin` role.** A `403` here is a role answer. Reading
  is `member`.
- **1–16 slots.** An empty chain is refused at create.

## Verify

```
getClientAlias("cheap")
  → slots in the order you sent
  → every slot has key_is_active: true
  → enabled reflects what you intended
```

Then one real call through `use-the-gateway` naming
`client:<brand>/cheap`. **A successful create is not a serving alias** — only the
call proves it.
