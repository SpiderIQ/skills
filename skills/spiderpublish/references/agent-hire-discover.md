# Agent hire lifecycle — discover → hire → get the flow_id → embed (headless, NO dashboard)

**Read when:** the client says "switch my agent (e.g. Aisha → Zara)", "hire an agent", "which
agents can I hire?", "what agents do I already have?", "add a different SDR", or needs the
`flow_id` UUID to drop into `<SpiderAgent flowId=…>` / `agent_flow_get_embed_snippet` — and there
is **no dashboard** in the loop (a headless Claude Code / Cursor session).

This is the surface that lets a client agent do — with no dashboard — what used to be dashboard-only.

**Two feeds (OPVS AG.0 contract).** There are TWO distinct agent lists — pick by intent:
- **Feed A — my OWN hired roster** (`agent roster`): agents this tenant ALREADY hired from OPVS.
  Embedding one is a **FREE reuse** (no charge). This is the "I already hired them, let me put one
  on my site" path — VayaPin's actual case (their 39 hires incl. Zara).
- **Feed B — the GLOBAL storefront** (`agent catalog`): every published agent any client can **BUY**.
  Hiring a new one is **OPVS-billed**.

| Capability | MCP tool | CLI verb | Endpoint |
|---|---|---|---|
| **Roster** — agents I already hired (Feed A, free re-embed) | `list_agent_roster` | `spideriq agent roster` | `GET /dashboard/content/agents/roster` |
| **Catalog** — the global storefront to BUY a new agent (Feed B) | `list_agent_catalog` | `spideriq agent catalog` | `GET /content/marketplace/components?category=agent` |
| **Hire** → mint the `kind='agent'` flow | `hire_agent` | `spideriq agent hire <id> [--roster]` | `POST /marketplace/agents/{by-profile/…\|component_id}/hire` |
| **List** MY LOCAL embedded flows + each `flow_id` | `list_hired_agents` | `spideriq agent list` | `GET /dashboard/content/agents/hireable` |

> On the mac-128 / atomic `@spideriq/mcp-publish` slice these are folded into the consolidated
> **`agent_flow`** tool as `op=list_roster | list_catalog | hire | list_hired` (same behavior; one
> tool slot). The kitchen-sink `@spideriq/mcp` exposes the granular tools above.
>
> Three "agent lists" — don't conflate: **`roster`** = hired on OPVS (free to embed) · **`catalog`**
> = global storefront (buy new) · **`list`** = already embedded as a local `kind='agent'` flow (has a
> `flow_id` to mount).

## The walkthrough — embed an agent I ALREADY hired (VayaPin: put Zara on the site)

```bash
# 1) ROSTER — the agents I already hired from OPVS. Find Zara + her catalog_profile_id.
spideriq agent roster
#   Zara Cohen  (active · SDR)
#     catalog_profile_id: c641fdc5-…     ← the hire key (a FREE reuse)

# 2) HIRE (--roster) — reuses the existing hire; NO 402/charge.
spideriq agent hire c641fdc5-… --roster
#   → status=active   flow_id: 4d9b… (the UUID you embed)
#   or status=provisioning → re-run:  spideriq agent hire c641fdc5-… --roster --flow-id 4d9b…

# 3) LIST — confirm it's now a local flow and grab the flow_id.
spideriq agent list
#   Zara Cohen  (active · sdr)
#     flow_id: 4d9b…

# 4) EMBED — never hand-compose the markup.
spideriq agent embed-snippet 4d9b… --mode inline
#   → <div data-spiderflow-flow="4d9b…" …> + loader <script>
#   React app:  <SpiderAgent flowId="4d9b…" />
```

**Buying a NEW agent instead** (Feed B — OPVS-billed): `spideriq agent catalog` → find the tile
`id` → `spideriq agent hire <component_id>` (no `--roster`). A priced agent returns
`status=payment_required` with a `handoff_url`.

MCP equivalent (kitchen-sink): `list_agent_roster` → `hire_agent {catalog_profile_id}` →
`list_hired_agents` → `agent_flow_get_embed_snippet {flow_id}`. Atomic slice: `agent_flow`
with `op=list_roster` → `op=hire {catalog_profile_id}` → `op=list_hired` → `op=get_embed_snippet`.

## The three things that bite

1. **Two hire keys — pick by feed.** From the **roster** (Feed A) the key is `catalog_profile_id`
   → hire with `--roster` (MCP: `catalog_profile_id`) for a **free reuse**. From the **catalog**
   (Feed B) the key is the tile's `component_id` → hire with no flag (OPVS-billed buy). The Feed-B
   `profile_id` (`agent_meta.opvs_catalog.profile_id`) is only an **optional cross-check**
   (`--profile-id`), never the thing you hire by. Passing both `--roster` id and a component_id is an
   error — one feed per hire.

2. **`hire` returns a `status` field, not an HTTP 402/202/200.** The endpoint ALWAYS answers HTTP
   200 and flattens OPVS's outcome into a `status` discriminator — **branch on the field**:
   - `payment_required` → open `handoff_url` (OPVS-hosted Stripe; SpiderPublish runs **no**
     checkout), pay, then re-call `hire`.
   - `provisioning` → re-call `hire` with the **echoed `flow_id`** (`--flow-id`) to poll; honor
     `retry_after`. The call is idempotent on `flow_id`.
   - `active` → `flow_id` is live — **that** is the UUID you embed.

3. **After hiring, the visitor origin must be allowlisted on the agent's OPVS binding** — otherwise
   the browser's session-mint (§6.2 handshake to OPVS) **403s and the embed never mounts a
   conversation**. SpiderPublish can't verify this locally (the allowlist lives OPVS-side). For a
   foreign BYOS host, declare it up front: `spideriq agent hire <id> --origin https://app.example.com`
   (MCP: `embed_origins:[…]`) — those origins are UNIONed into the OPVS bind allowlist. Render
   success (HTTP 200 + shadow host present) does NOT prove the conversation works — that's the
   surface, not the live convo (same honesty split as [`agent-embed.md`](agent-embed.md)).

## What each returns

- **`list_agent_roster`** (Feed A) — `{ agents: [{ catalog_profile_id, display_name, role_title,
  status, agent_type, avatar_url, pricing, management_api_agent_id }], total }`, proxied from OPVS
  `GET /employees/hires` (brand-scoped). `catalog_profile_id` is the free-reuse hire key. A 409
  `OPVS_NOT_CONNECTED` / `OPVS_BRAND_NOT_CONFIGURED` means the workspace's OPVS account/brand isn't
  wired up yet.
- **`list_agent_catalog`** (Feed B) — `content_components` rows with `category='agent'` (the
  daily-synced GLOBAL storefront, `is_global`). Each: `id` (hire key), `name`/`slug`,
  `agent_meta.opvs_catalog.profile_id`.
- **`hire_agent`** — `{ status, flow_id?, handoff_url?, retry_after?, … }`. See rule 2. A Feed-A
  (`--roster`) hire is a free reuse → typically `status=active` straight away.
- **`list_hired_agents`** — `[{ agent_flow_id, name, status, role }]`. `agent_flow_id` is the
  `flow_id` you embed; a `paused`/`canceled` agent will 403 the session-mint even though it lists.

## Don't confuse this with…

- **`agent_flow_*` authoring** (create/update/publish a flow from a binding you already have) —
  that's [`agent-embed.md`](agent-embed.md). Hire is how you *get* a bound flow in the first place.
- **Agent COMPONENTS** (`marketplace_category='agent'` reusable `<opvs-agent>` blocks) —
  [`agent-component-authoring.md`](agent-component-authoring.md). Different primitive.
- **`spiderflows` / lead-search** — those FIND prospects; this hires an agent to talk to them.
