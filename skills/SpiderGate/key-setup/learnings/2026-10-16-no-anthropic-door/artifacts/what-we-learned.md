# The gateway has no Anthropic door and no Responses door

## What we measured

`https://spideriq.ai/api/gate/v1` is OpenAI chat-completions. It serves
`/chat/completions`, `/embeddings`, images, audio, media and `/models`.
`/messages`, `/responses` and the legacy `/completions` each answered 404 when
probed live (2026-10-16).

## What that means for agents

| Agent | Why |
|---|---|
| Claude Code | Needs `ANTHROPIC_BASE_URL` and `/v1/messages`. Does not work |
| Codex CLI | Its `wire_api` is `responses` only. Does not work |
| Cursor | Agent mode sends the Responses API. Ask/chat works; Agent does not |
| n8n | Works with "Use Responses API" OFF |

## What to do

- Never list Claude Code or Codex CLI as an agent the gateway serves.
- A 404 from an agent that calls `/responses` is the gateway's shape, not an
  outage. Switch the agent to chat-completions, or say it cannot connect.
