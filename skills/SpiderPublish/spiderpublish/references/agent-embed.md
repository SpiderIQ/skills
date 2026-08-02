# Agent Embed — put a live OPVS AI agent on a site (`kind='agent'`)

An **agent flow** is a `booking_flows`/`funnels` row with `kind='agent'`. It renders a live AI
agent (SDR / support / concierge / booking) on the tenant's deployed site, as a native flow served
from `https://<tenant>/f/<flow_id>` (and inline / concierge / headless mounts). It is the **same
primitive** as forms and booking flows — read [`booking-model.md`](booking-model.md) first for the
shared `flow.json` data model and the `/f/<id>` URL semantics.

**Read when:** the client wants "an AI agent / chatbot / SDR / concierge on my site", "embed an
agent", "put a sales rep widget on the page", or names an OPVS agent to render.

> **The honest split (say this to the client).** SpiderPublish renders the agent **surface** and
> stores the **binding** (public URLs + ids → the agent). It holds **zero credentials**. The live
> **conversation** (the streaming round-trip + grounding + all secrets) runs on **OPVS**. So
> creating, publishing, deploying, customizing, and embedding an agent flow is **live today**; the
> live conversation lights up once the client **hires an OPVS agent** (which mints the binding) and
> the agent's origin is bound to the site. Do NOT claim the end-to-end conversation works before
> the OPVS hire — it doesn't.

## Tools (`agent_flow_*`) — kitchen-sink `@spideriq/mcp` only

These 5 tools wrap `/api/v1/dashboard/booking/flows` with `kind="agent"`, mirroring `form_*`. They
ship in `@spideriq/mcp` ONLY (not the atomic `@spideriq/mcp-publish` — 128-tool ceiling).

| Tool | Does | Gate |
|---|---|---|
| `agent_flow_create` | create the flow + store the `flow.agent` binding | opt-in `dry_run` |
| `agent_flow_update` | edit the binding / UI / grounding | opt-in `dry_run` |
| `agent_flow_publish` | flip published | **safe-default** `dry_run` → call again with `confirm_token` |
| `agent_flow_preview_url` | return the canonical `/f/<id>` | read |
| `agent_flow_get_embed_snippet` | return the loader `<script>` + mount element | read |

> **NEVER hand-compose `/f/<id>` or the embed snippet.** Always return them from
> `agent_flow_preview_url` / `agent_flow_get_embed_snippet`. A hand-built URL is the #1 way an embed
> silently 404s (Rule 60 / the "8 broken iframes" incident).

## The binding — URLs + ids, NEVER a secret

The `flow.agent` AgentBinding comes from the **OPVS agent hire** — you don't invent it. It is
serialized into the public browser bundle, so it must be secret-free:

```jsonc
{
  "agent_id": "agt_…",
  "role": "sdr",                              // sdr | support | concierge | booking
  "ingress_url": "https://…",                 // OPVS SSE stream
  "session_url": "https://…",                 // OPVS handshake
  "grounding": { "mode": "page" },            // page | site | docs (+ optional knowledge_base_id)
  "ui": { "surface": "flow", "widgets": ["selection","confirmation","booking"], "theme_inherit": true },
  "escalation": { "board_id": "…", "channel": "board_comment" }
}
```

**Any credential-shaped key** (`token`, `secret`, `api_key`, `password`, `bearer`, `pat`, … at any
depth) is rejected with a `422` — server-side AND mirrored at the MCP boundary. If the client
pastes a key into the binding, that's the error you'll get; strip it.

## Recipe — create → publish → embed

```
1. agent_flow_create   { name, kind:"agent", flow:{ agent:<binding from OPVS> } }
                       → flow_id
2. agent_flow_publish  { flow_id }                    → dry_run preview + confirm_token
   agent_flow_publish  { flow_id, confirm_token }     → published
3a. agent_flow_preview_url        { flow_id }         → standalone /f/<id>  (link to it)
3b. agent_flow_get_embed_snippet  { flow_id, mode }   → inline / concierge snippet to paste
4. deploySite (the site deploy) — the surface goes live on the CF edge
5. visual-check the URL (assert dom.shadow_hosts, NOT body_text_preview — the agent is in shadow DOM)
```

**Never hand-write the mount markup.** Three surfaces emit the identical, corrected snippet from one
shared source (`buildAgentEmbedSnippet` in `@spideriq/core`) — they can never drift:
- **MCP** — `agent_flow_get_embed_snippet { flow_id, mode }` (or `agent_flow { op:"get_embed_snippet" }`)
- **CLI** — `spideriq agent embed-snippet <flow_id> --mode inline|concierge` (pure local, no API call)
- **Dashboard** — the **Copy embed code** button on the agent flow

## Four mount surfaces

| Mode | How | Use for |
|---|---|---|
| **Standalone** | publish + link `/f/<id>` | a dedicated "talk to us" page |
| **Inline** | `<div data-spiderflow-flow="<id>" data-spiderflow-kind="agent" data-spiderflow-mode="inline">` + loader | agent in a marketing page |
| **Concierge** | same, `data-spiderflow-mode="concierge"` | site-wide floating bubble |
| **Headless** | `<opvs-agent headless>` | client builds 100% of the UI |

> **Corrected snippet contract:** the loader keys on **`data-spiderflow-flow`** (+ `data-spiderflow-kind="agent"`
> + `data-spiderflow-mode`). An element using the old `data-spiderflow-id` / `data-opvs-agent` name is
> silently skipped and never mounts — always generate the snippet from one of the three surfaces above.

Agents render **in-DOM (open shadow root), never an iframe** — that's what makes them customizable
and lets the SSE stream through.

## Customization (3 tiers)

The agent inherits the site theme automatically. Override from the light DOM:

1. **Tokens (no code)** — `--opvs-agent-primary`, `--opvs-agent-radius`, `--opvs-agent-font-body`,
   … (site wins; `theme_inherit` default `true`).
2. **Parts / slots / events / API** — `::part(panel|launcher|message|widget-card|send-button)`,
   `slot="header"`/`slot="footer"`, `opvs-agent:open|close|message|widget-render`, and
   `el.open()/close()/send()/on()`. GSAP loads via `custom_head_scripts`.
3. **Headless** — `getState()` + `opvs-agent:state` + `send()`/`respondToWidget()`.

Full token/part/event/headless reference: **`apps/opvs-agent/CUSTOMIZATION.md`** in the monorepo
(also at https://docs.spideriq.ai/docs/site-builder/agent-embed).

## Gotchas

- **Surface ≠ conversation.** Render success (HTTP 200, shadow host present) does NOT mean the
  agent is talking — that needs the OPVS hire + a bound origin. Visual-check confirms the surface,
  not the convo.
- **Don't reach for `spiderflows`/`lead-search`** — those FIND prospects. This embeds an agent.
- **The binding is authored by OPVS**, not by you. If there's no binding yet, create the flow and
  tell the client the surface will wait for its OPVS agent hire.
- **Want the agent to read the page it's on?** That's page-grounding — opt in with `pageContext`
  (automatic on hosted pages). See [`page-grounding.md`](page-grounding.md).
