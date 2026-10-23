# Reference — connect your agent

Once a key is in (`can_use_models: true`), point the owner's agents at the
gateway. Three values go into every agent:

| Value | What |
|---|---|
| Base URL | `https://spideriq.ai/api/gate/v1` |
| API key | A `spideriq_pat_…` agent key from **Gate → Keys** |
| Model | `recommended_model` from the status. Never `agent/chat` |

The gateway is OpenAI chat-completions. It has `/chat/completions`,
`/embeddings`, images, audio, media and `/models`. It has **no** `/responses`,
no `/messages` and no legacy `/completions`.

The agent key:
- is shown once;
- expires in 1 hour to 90 days; there is no "never";
- is minted only by a **brand owner**, in a browser. You cannot mint one: send
  the owner to Gate → Keys.

Rejected keys: `sk-…` (401) and `sg_key_…` (501). `/models` does not list
aliases (`/aliases` does), so a picker that reads `/models` will not offer
`agent/*` or `client:*` names.

## Which agents work

| Agent | Verdict | Where the 3 values go | Caveat to print |
|---|---|---|---|
| **OpenClaw** | **Works.** OPVS's own fleet runs this way (`register_spidergate_providers.py:49-81`, a recorded session on `openai-completions`). | `models.providers.<name>`: `baseUrl`, `apiKey`, `api: "openai-completions"`, `models[].id`. Model ref `<name>/<model>`. | Production uses the composite `client_id:key:secret`; **a PAT is unmeasured** → TL. |
| **Hermes Agent** | Works with caveat (not run). There is no integration in our repo. | `~/.hermes/config.yaml` → `model: {provider: custom, base_url, api_key (or key_env), default}`, or `hermes model` → "Custom endpoint". | Needs a model with **≥64k context** or it refuses at start. `OPENAI_BASE_URL` does not apply to `custom`. |
| **n8n** | Works with caveat. | OpenAI credential "Base URL" (in source; the docs page lags) + "API Key". Model typed **by ID**. | Leave **"Use Responses API" OFF**. 🔴 Coding-plan keys (Zhipu/Qwen/BytePlus) are for interactive tools only — n8n automation on them is a ToS risk; say so on the page. |
| **Cursor** | Works with caveat: **Ask/chat only.** | Settings → "Override OpenAI Base URL" + "OpenAI API Key" + custom model name. | Agent mode sends Responses API → fails here (Cursor staff, forum, 2026-03-07). Tab never uses custom keys. Whether a model name containing `/` or `:` is accepted is unmeasured → TL. |
| Claude Code | **Does not work** | needs `ANTHROPIC_BASE_URL` → `/v1/messages` | Do not list it. |
| Codex CLI | **Does not work** | `wire_api` is `responses` only | Do not list it. |

(Table as measured in the research report of 2026-10-16. "TL" marks what was
not yet tried against the live gateway.)

## Steps

1. `getOnboardingStatus` → `can_use_models` true, read `recommended_model` and
   `answers.uses.agents`.
2. For each agent they ticked, give its row: where the three values go and the
   caveat. Hermes: check the recommended model has ≥64k context.
3. If they ticked Claude Code or Codex CLI: say plainly it does not work here,
   and why.
4. Mark setup done: `updateOnboarding {"state": "done"}`.

## Gotchas

- An agent that calls `/responses` (Cursor Agent mode, n8n with "Use Responses
  API" on, Codex CLI) gets a 404. That is the gateway's shape, not an outage.
- Do not paste the owner's agent key back to them; it is a secret too.
