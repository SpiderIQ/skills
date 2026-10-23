# Reference — run setup from chat

The dashboard's setup wizard has six steps. From chat you walk the same six, one
question at a time, and save each answer as you go.

| Step | Wizard label | From chat |
|---|---|---|
| 1 | How you will use it | `uses.goals` (agents · chat · build · media · team) and `uses.agents` (openclaw · hermes · cursor · n8n · own_code · other) |
| 2 | What you already pay for | `pays_for` — subscriptions they hold (`codex`, `gemini_cli`, `minimax` …). Each is a browser sign-in or a dashboard paste: give the link |
| 3 | Free keys | `free_keys_chosen` — then one free key at a time with `addKey` ([add-a-key.md](add-a-key.md)) |
| 4 | Ask your teammates | `proposeInvite` ([invite-a-teammate.md](invite-a-teammate.md)); the owner sends from the dashboard |
| 5 | Add keys | Paid keys: dashboard link only |
| 6 | Ready | Connect their agents ([connect-your-agent.md](connect-your-agent.md)); `state: done` |

## Steps

1. `getMyBrand` → `brand_id`.
2. `getOnboardingStatus`. If `state` is `not_started`, start at step 1.
3. Ask the step's question. Save the answer:

   ```http
   PATCH /api/v1/brands/{brand_id}/gate/onboarding
   {"step": 2, "answers": {"uses": {"goals": ["agents", "build"], "agents": ["openclaw", "hermes"]}}}
   ```

   The answer is the new status. Read its `next` and say it.
4. Repeat until `next.action` is `finish`, then send `{"state": "done"}`.

## A real status

This is the shape `getOnboardingStatus` returns (brand 2, mid-setup). It is
generated from the server's own test fixture, so it matches the handler.

```json
{
  "brand_id": 2,
  "state": "in_progress",
  "step": 3,
  "of": 6,
  "step_label": "Free keys",
  "answers": {
    "uses": {
      "goals": [
        "agents",
        "build"
      ],
      "agents": [
        "openclaw",
        "hermes"
      ],
      "other": null
    },
    "pays_for": [
      "codex"
    ],
    "free_keys_chosen": [
      "mistral",
      "groq"
    ],
    "teammates": [
      {
        "email": "bo@example.com",
        "providers": [
          "nvidia_nim"
        ],
        "status": "proposed"
      },
      {
        "email": "anna@example.com",
        "providers": [
          "openai",
          "deepseek"
        ],
        "completed_providers": [],
        "status": "sent",
        "invite_id": 11,
        "expires_in_h": 41
      }
    ]
  },
  "skipped_steps": [],
  "ui": {
    "bubble": "open",
    "login_prompt": "show"
  },
  "connected": [
    {
      "provider": "codex",
      "kind": "subscription",
      "via": "own",
      "keys": 1,
      "models": 1
    },
    {
      "provider": "groq",
      "kind": "free",
      "via": "own",
      "keys": 1,
      "models": 1
    }
  ],
  "pool": {
    "entitled": false,
    "providers": []
  },
  "waiting": [
    {
      "provider": "openai",
      "asked": "anna@example.com",
      "invite_id": 11,
      "expires_in_h": 41
    },
    {
      "provider": "deepseek",
      "asked": "anna@example.com",
      "invite_id": 11,
      "expires_in_h": 41
    }
  ],
  "can_use_models": true,
  "models_usable": 2,
  "models_total": 8,
  "recommended_model": "codex/gpt-6-sol",
  "pool_consent": {
    "state": null,
    "at": null
  },
  "next": {
    "action": "add_free_key",
    "provider": "mistral",
    "title": "Mistral AI",
    "kind": "free",
    "unlocks": null,
    "minutes": 3,
    "guide_url": "https://gate.spideriq.ai/docs/providers/mistral",
    "signup_url": "https://console.mistral.ai/api-keys",
    "add_url": "https://app.spideriq.ai/dashboard/gate/setup?step=3&provider=mistral",
    "dashboard_url": "https://app.spideriq.ai/dashboard/gate/setup?step=3"
  },
  "completed_at": null,
  "updated_at": "2026-10-21T12:00:00+00:00",
  "updated_by": "u_admin"
}
```

How to read it:

- `next` — the one thing to do. Here: add a free Mistral key on step 3. Say its
  `title`, give `signup_url` to get the key and `add_url` if they prefer the dashboard.
- `answers.teammates` — `proposed` entries are waiting for the owner to send;
  `sent` entries are real invites with `expires_in_h` left.
- `connected` — providers with the brand's own key, and how many models each
  serves. `pool` lists providers reached only through the shared pool.
- `can_use_models` / `models_usable` — whether an agent can call anything yet.
- `recommended_model` — the model to give an agent. Never `agent/chat`.
- `pool_consent` — the owner's own choice; you can read it, never set it.

## Gotchas

- `ui` and the pool consent are refused for an agent (403 `HUMAN_ACT_REQUIRED`).
- A derived field in a PATCH (`connected`, `can_use_models` …) is refused by
  name (`FIELD_IS_DERIVED`); an unknown one too (`ONBOARDING_UNKNOWN_FIELD`).
- Providers are checked against the provider list: a typo is a 422 naming it.

## Verify

`getOnboardingStatus` after each write shows the answer saved and a new `next`.
