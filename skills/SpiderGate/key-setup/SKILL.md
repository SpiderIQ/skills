---
name: key-setup
description: >
  Set up the SpiderGate LLM gateway with its owner, from chat: where setup
  stands and the one next step, the owner's answers, how to get a key for a
  provider, saving a FREE key they paste, proposing a teammate who holds an
  account, and connecting their agent afterwards.
  Trigger on: "set up SpiderGate", "I have no key yet", "how do I get a Groq
  key", "add my free key", "add my Mistral key", "connect my ChatGPT
  subscription", "what's the next step", "invite Anna to add her OpenAI key",
  "connect OpenClaw / Hermes / n8n / Cursor to the gateway", "which model
  should my agent use", "which recipes work with my keys", "which key should
  I add next". This skill SETS UP the gateway. It does not send
  completions (use-the-gateway), pick models in depth (model-catalog) or build
  routing chains (client-aliases).
version: "0.2.0"
category: ai-gateway
---

# key-setup

Get a workspace from "no key" to "my agent is calling models", the way the
dashboard's setup wizard does, but in chat.

```
  getMyBrand ─▶ getOnboardingStatus ─▶ say next.action + its link
                        ▲                        │
                        │        ┌───────────────┼──────────────────┬─────────────────┐
                        │   answer_questions  add_free_key     add_key /          send_invites
                        │        │               │            connect_subscription    │
                        │  updateOnboarding   addKey  (pasted)   give add_url    give step-4 link
                        └────────┴───────────────┴──────────────────┴─────────────────┘
```

<HARD-GATE name="a-key-is-never-repeated-and-paid-keys-get-a-link">
**Never repeat a key back.** Not in a reply, a summary, a file, a log or a board
comment — not even its first or last characters. The vault is the only place a
key goes, and addKey returns no key.

**Only a FREE key is taken in chat** (`kind: free`, `add_method: paste`). For a
paid key (`payg`, `enterprise`, `media`), a subscription, or any
`add_method: login_link` provider, give the owner the dashboard link and stop.
Never ask for a password, and never ask for a provider's phone-check code.

If the owner pastes a paid key anyway: do not send it, say it should be added
at the link, and tell them to delete the message that carried it.
</HARD-GATE>

## Approach

1. **`getMyBrand`** — the `brand_id` of this credential. One brand only; with
   more than one, ask which (never guess).
2. **`getOnboardingStatus`** — read `next.action`, say it in one sentence, and
   give its link (`next.add_url`, else `next.dashboard_url`).
3. Do what `next.action` names:

| `next.action` | You do |
|---|---|
| `answer_questions` | Ask how they will use it, what they pay for, which free keys they want → `updateOnboarding` · [run-setup.md](references/run-setup.md) |
| `connect_subscription` | Give `next.add_url`. It is a browser sign-in |
| `add_free_key` | `getProviderGuide`, send them to `signup_url`, take the pasted key → `addKey` · [add-a-key.md](references/add-a-key.md) |
| `add_key` | A paid key: give `next.add_url` |
| `send_invites` | Proposals are waiting: the owner sends them at `next.dashboard_url` · [invite-a-teammate.md](references/invite-a-teammate.md) |
| `connect_agents` | Point their agents at the gateway · [connect-your-agent.md](references/connect-your-agent.md) |
| `finish` / `done` | Nothing is missing. Recommend `recommended_model` · [pick-a-recipe.md](references/pick-a-recipe.md) |

4. After every write, read the status again and say the new `next`.

## Rules

**NO TENANT ARGUMENT:** the brand is the credential's. MCP tools and CLI verbs
take none; the HTTP methods take the `brand_id` from `getMyBrand`, never one
the user typed.

**THE MODEL TO RECOMMEND** is `recommended_model` from the status: the first
recipe the workspace's keys can run (`getRecipes` marks the same one
`recommended`). Never an `agent/*` name, and nothing at all while
`can_use_models` is false. "Which key next?" is `getRecipes` → `unlock`.

**AN INVITE IS A PROPOSAL.** `proposeInvite` writes it into step 4 and sends
nothing. A person sends it from the dashboard.

**FREE TIERS MAY TRAIN ON PROMPTS.** Repeat the guide's `terms_note`: no
personal data through a free key.

## Same tools, other surfaces

| Method | MCP tool (`@spideriq/mcp-gate`) | CLI |
|---|---|---|
| getOnboardingStatus | `gate_onboarding_status` | `spideriq gate setup status` / `next` |
| updateOnboarding | `gate_onboarding_update` | `spideriq gate setup answer` |
| getProviderGuide | `gate_provider_guide` | `spideriq gate setup guide <provider>` |
| addKey | `gate_add_key` | `spideriq gate setup add-key <provider>` (key on stdin or `$SPIDERIQ_PROVIDER_KEY`) |
| proposeInvite | `gate_invite_contributor` | `spideriq gate setup invite <email> --provider …` |
| getRecipes | `gate_recipes` | `spideriq gate recipes [--usable]` |

The MCP tool and the CLI refuse a paid key or a sign-in themselves, before any
request, and return the link.

## References

- [run-setup.md](references/run-setup.md) — the six steps from chat, with a real status
- [add-a-key.md](references/add-a-key.md) — paste or link, `extra_fields`, refusals
- [invite-a-teammate.md](references/invite-a-teammate.md) — proposing, and what the owner does next
- [connect-your-agent.md](references/connect-your-agent.md) — OpenClaw, Hermes, n8n, Cursor; what does not work
- [pick-a-recipe.md](references/pick-a-recipe.md) — which recipes your keys run, slot states, which key to add next

## Learnings

- [A 422 echoed the key](learnings/2026-10-16-a-422-echoes-the-key/artifacts/what-we-learned.md)
- [There is no Anthropic door](learnings/2026-10-16-no-anthropic-door/artifacts/what-we-learned.md)
