---
name: client-aliases
description: >
  Create and manage YOUR OWN routing aliases on the SpiderGate LLM gateway — a
  named, ordered fallback chain of models you can call as one stable model name.
  Trigger on: "create my own alias", "make a routing alias", "my own model
  chain", "route my calls through my own key", "set up a fallback chain",
  "use my OpenAI key through the gateway", "BYOK alias", "bring my own key",
  "rename a model for my team", "list my aliases", "why is my alias failing",
  "disable my alias", "delete my alias", "add a fallback model", "reorder my
  fallback chain". These are CLIENT aliases ("client:<brand>/<leaf>") — the ones
  you create, funded by YOUR OWN provider keys. They are NOT the SpiderIQ task
  aliases (spideriq/coding, spideriq/fast, agent/*), which you read with
  model-catalog and call with use-the-gateway. This skill MANAGES aliases; it
  does not send completions.
version: "0.1.0"
category: ai-gateway
---

# client-aliases

Your own named model chain on the gateway, funded by your own provider keys.

```
  client:<your-brand>/<leaf>          ← the name you call
        │
        ├── slot 0   your key #102 → openai/gpt-4o-mini      ← tried first
        ├── slot 1   your key #103 → mistral/mistral-small
        └── slot 2   your key #104 → groq/llama-3.3-70b       ← last resort
```

## Approach

| You want to… | Do this |
|---|---|
| see what you already have | `listClientAliases` |
| diagnose one that is failing | `getClientAlias` — it reports each slot's key state |
| make a new one | `createClientAlias` with an ordered `slots` chain |
| change the chain, or park it | `updateClientAlias` (`enabled: false` parks it reversibly) |
| remove it for good | `deleteClientAlias` |

Then **call it** with the `use-the-gateway` skill, passing `client:<brand>/<leaf>`
as the `model`. Managing an alias never sends a completion.

<HARD-GATE name="every-slot-names-a-key-you-own">
`integration_id` is REQUIRED on every slot and has NO DEFAULT.

It is the id of **one of your own provider keys**, and it is what FUNDS that
slot. There is deliberately no fallback, because the convenient wrong answer to
*"who pays for this?"* is the SpiderIQ pool — and a client alias may never
reach it.

Before you create an alias, get the caller's real key ids from their brand
integrations surface. **Do not invent one, do not reuse an id from an example,
and do not guess from a provider name.** A wrong id is not a routing bug you
can debug later; it is a slot that can never serve.
</HARD-GATE>

## Rules (Non-Negotiable)

**NO TENANT ARGUMENT EXISTS:** no method here takes a brand or tenant id. The
server derives it from the credential, so there is no field in which one tenant
could name another. **NEVER** add one, and never read a `404` as "this name is
free" — another tenant's alias returns the same `404` by design.

**CREATING PUBLISHES IT:** a new alias is live for your tenant the moment the
call returns. Pass `enabled: false` to author one without arming it. This
matters because there is no draft state to fall back to.

**`slots` REPLACES, NEVER MERGES:** on update, `slots` overwrites the whole
ordered chain. **ALWAYS** read the alias first and send back the full list you
want — sending one slot to "add" one silently deletes the rest.

**NAME IS THE LEAF ONLY:** pass `cheap`, never `client:7/cheap`. The
`client:<brand>/` prefix is generated server-side and cannot be supplied — which
is exactly why your alias can never collide with `spideriq/*`, `agent/*` or
`opvs/*`.

**A CREATE THAT SUCCEEDS IS NOT AN ALIAS THAT SERVES:** creation validates the
shape, not the key's ability to serve that model. See
`references/diagnose-an-unservable-alias.md` — this is the single most common
support question on this surface.

**WRITES NEED ADMIN:** reads are `member`, every write is `admin`. A `403` on
create/update/delete is a role answer, not a broken credential — report it,
do not retry.

## Decision tree — pick a reference

| The user wants to… | Read |
|---|---|
| build their first alias end to end | `references/create-an-alias.md` |
| work out why an alias returns nothing useful | `references/diagnose-an-unservable-alias.md` |
| change or retire one safely | `references/change-or-retire-an-alias.md` |

## Why an alias can be refused

A client alias routes **only** to models backed by keys this tenant owns. It can
never borrow the SpiderIQ pool. So a slot is refused — not silently re-routed —
when its key is missing, inactive, not owned by this tenant, or is an
inject-only subscription key (Anthropic and Gemini-CLI keys are inject-only and
can never fund a slot, even when you own them). Fail-closed is the deliberate
design: an invented answer from a fallback model is worse than an error.

## See also

- `use-the-gateway` — SEND a completion, including one naming your client alias
- `model-catalog` — compare models before you put one in a slot
- `spidergate-manager` — read usage, capacity and traces after it is live
- `learnings/` — starting points, not ground truth; verify against current behaviour
