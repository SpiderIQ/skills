# Surfaces & auth — how you talk to SpiderIQ

Every flow is reachable four ways. They are the **same API** underneath; pick the
one that fits your runtime. All on `https://spideriq.ai/api/v1`.

## The four surfaces

| Surface | You are | How you call |
|---|---|---|
| **HTTP** | any agent that can make requests | `curl`/`fetch` against `https://spideriq.ai/api/v1/...` with a Bearer header |
| **CLI** | a shell-capable agent | `npx @spideriq/cli ...` (`spideriq jobs ...`, `spideriq campaigns ...`) |
| **MCP** | an MCP-host agent (Claude Code, Cursor) | the `@spideriq/mcp` tools (`submit_job`, `create_campaign`, `get_job_results`, …) |
| **skill** | you, right now | this skill routes you to the right recipe; the recipe shows the HTTP/CLI/MCP call |

You never run a worker yourself and you never touch a queue. You submit a request,
SpiderIQ runs the chain server-side, and you read results back.

## Auth — one Bearer PAT

Every call carries a Personal Access Token in the `Authorization` header:

```
Authorization: Bearer <client_id>:<api_key>:<api_secret>
```

- **CLI / MCP** load it for you from `~/.spideriq/credentials.json` — you never paste it.
- **HTTP**: send the header yourself. **Never echo the secret into logs or chat.**
- **SSE** is the one exception (EventSource can't send headers): the token rides as
  a query param — `GET /events/stream?token=<client_id>:<api_key>:<api_secret>`.
  Treat that URL as a secret; don't paste it back.

A malformed token → `401`; an inactive account → `403`. A valid token scoped to
the wrong tenant simply sees no data — IDAP is tenant-isolated by `client_id`.

Your PAT is **self-identifying** (`spideriq_pat_<agent_ref>_<secret>` — the
`<agent_ref>` is your permanent handle; legacy `spideriq_pat_<32-hex>` tokens
still authenticate) and carries an **OPVS address** (`<name>@opvs.run`, saved as
`opvsAddress` in `credentials.json`) — your public, messageable identity. You are
**one account**: re-running `spideriq auth request` from a new folder/machine
ROTATES the same account (your held PAT wins), and `--as <your-opvs-address>`
RECOVERS it on a fresh box — it never forks a ghost. Full model: `_shared/auth.md`.

## Token economy — ask for YAML

Every `GET` accepts `?format=yaml` or `?format=md` (validated against
`^(json|yaml|md)$`). On large result sets YAML is **40–76% fewer tokens** than
the default JSON. Set it once and forget it:

```bash
# per-call
curl "https://spideriq.ai/api/v1/idap/businesses?campaign_id=camp_x&format=yaml" \
  -H "Authorization: Bearer $SPIDERIQ_PAT"

# CLI / MCP: set the env var once
export SPIDERIQ_FORMAT=yaml
```

`md` is for when a human will read the output; `yaml` is the default you want for
agent-to-agent traffic. `POST` bodies can also be sent as `text/yaml` instead of JSON.

## What this buys you

- One token works across HTTP, CLI, MCP, and SSE.
- One base URL (`/api/v1`) for submit, lifecycle, progress, and read.
- Results are **never** returned inline at scale — submit returns an id, you read
  the data back through IDAP (see [reading-results.md](reading-results.md)).

See also: [run-modes-and-progress.md](run-modes-and-progress.md) for single vs
campaign and how to watch progress without tight-looping.
