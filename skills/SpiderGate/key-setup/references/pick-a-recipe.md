# Reference — pick a recipe the workspace's keys can run

A **recipe** is a ready-made model name such as `spideriq/chat` or
`spideriq/coding`. Each one lists candidate slots (provider + model). The gateway
fills a recipe from the workspace's OWN keys first, then a connected company's
keys, then the shared free pool. `getRecipes` says, for THIS workspace, which
recipes work, which slot each would use, and which key would unlock the rest.

Use it when the owner asks "which model should my agent use?", "what can I do
with my keys?" or "what key should I add next?".

## Steps

1. `getMyBrand` → `brand_id`.
2. `getRecipes`.
3. If `recommended` is set, give it to the owner as the model name for their
   agent. It is the same answer as `recommended_model` in the setup status.
4. If the owner wants more, read `unlock` (top level): providers ranked by how
   many recipes one key would open. Name the first one or two, with `add_url`.
   For a free provider, follow [add-a-key.md](add-a-key.md).
5. After a key is added, call `getRecipes` again: the recipe's slot now reads
   `usable`.

## Slot states

| State | Means | Say |
|---|---|---|
| usable | A key serves it. `filled_by`: own (your key), group (a connected company's key) or pool (the shared free pool) | "Works now, on your key" (or the company's / the pool's) |
| locked | No key you can use serves it. `unlock` names the provider and `add_url` | "Add a <provider> key to use this slot" + the link |
| lease_only | A sign-in leased to its own CLI. It never serves chat | Nothing to add here |
| not_routed | A Codex slot that is not first. The gateway never tries it | Nothing to add here |

A recipe is `usable` when any slot is. `filled_by` on the recipe is the nearest
tier among its usable slots: the one that takes the traffic.

## An example

```json
{
  "brand_id": 2,
  "recipes_active": true,
  "pool_entitled": false,
  "recommended": "spideriq/chat",
  "usable": 1,
  "total": 2,
  "recipes": [
    {
      "name": "spideriq/chat",
      "usable": true,
      "filled_by": "own",
      "recommended": true,
      "slots": [
        {"slot": 0, "rank": 0, "provider": "minimax", "model": "MiniMax-M2.5", "state": "usable",
         "filled_by": "own", "integration_id": 701, "unlock": null}
      ],
      "unlock_providers": []
    },
    {
      "name": "spideriq/planning",
      "usable": false,
      "filled_by": null,
      "recommended": false,
      "slots": [
        {"slot": 0, "rank": 0, "provider": "mistral", "model": "codestral-latest", "state": "locked",
         "filled_by": null, "integration_id": null,
         "unlock": {"provider": "mistral", "title": "Mistral AI", "kind": "free", "add_method": "paste",
                    "guide_url": "https://gate.spideriq.ai/docs/providers/mistral",
                    "add_url": "https://app.spideriq.ai/dashboard/gate/setup?step=5&provider=mistral"}}
      ],
      "unlock_providers": ["mistral"]
    }
  ],
  "unlock": [
    {"provider": "mistral", "title": "Mistral AI", "kind": "free", "add_method": "paste",
     "guide_url": "https://gate.spideriq.ai/docs/providers/mistral",
     "add_url": "https://app.spideriq.ai/dashboard/gate/setup?step=5&provider=mistral",
     "opens_recipes": 1}
  ]
}
```

## Gotchas

- **Never recommend an `agent/*` name.** They are live-agent chains. `recommended`
  never is one, even when it reads `usable`.
- **`integration_id` shows only for the workspace's own keys.** A connected
  company's or the pool's key is never named.
- **Usable is not "healthy".** A slot reads usable on a key the gateway may have
  cooled for a minute. If a call fails, the gateway tries the next tier.
- **`recipes_active: false`** means recipes are switched off on the server: own
  and group keys are not used through these names, and only the pool serves them.
- **Nothing here sends a request to a model.** It is a read; call it as often as
  you like.

## Verify

`getRecipes` again after a key is added: the slot that named that provider in
`unlock` now reads `usable`, and `usable` (top level) went up.
