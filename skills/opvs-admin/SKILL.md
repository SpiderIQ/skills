---
name: opvs-admin
version: "2.0.0"
description: >
  Full admin control over the OPVS agent platform — gateway config,
  cron scheduling, skills management, channel bindings, and gateway operations.
category: admin
client: opvs-admin
client_version: "1.0.0"
homepage: https://app.opvs.ai/admin/agents
metadata:
  openclaw:
    emoji: "\u2699\uFE0F"
    primaryEnv: MANAGEMENT_API_KEY
---

# OPVS Admin

## When to Use

- View or update gateway settings (model defaults, memory search, context pruning, compaction)
- View or change a specific agent's runtime config (model override, context tokens)
- Manage cron jobs or scheduled tasks for agents
- Manage channel bindings (which agent handles which channel/account)
- Enable, disable, or configure skills in the gateway
- Check gateway health, reload config, or verify connectivity
- Create, list, or delete skills at the workspace level
- Assign skills to a specific agent

For reading/writing agent workspace files (SOUL.md, AGENTS.md, user
profiles, memory notes), use the **opvs-workspace** skill instead.

## Config Change Workflow

After making any moltbot config change (agent config, bindings, skills,
gateway settings), always reload the gateway. Config changes are written
to disk immediately but the gateway only picks them up on reload.

## Cron Job Rules

### Schedule Types

| Kind | Use For |
|------|---------|
| `cron` | Standard cron expressions (e.g., "0 9 * * 1-5" for weekdays 9 AM) |
| `every` | Repeating intervals in milliseconds |
| `at` | One-shot at a specific ISO 8601 timestamp |

### Session Target Rules

- `isolated` -- fresh session for one-off tasks. Requires `payload.kind: "agentTurn"`
- `main` -- persistent session for memory updates and state changes. Supports both `agentTurn` and `systemEvent`

### Delivery Modes

- `announce` -- sends agent response to a channel target (`channel:<id>` or `user:<id>`)
- `webhook` -- POSTs response to a URL
- `none` -- silent, runs job without delivering output

## Binding Rules

Bindings use array indices, not IDs. Always GET current bindings first to
find the correct index before modifying or deleting.

## Skill Activation

Skill activation requires both steps:
1. Create or enable the skill entry in moltbot.json (gateway-level)
2. Assign the skill to the agent's whitelist (workspace-level)

Both steps are needed, followed by a gateway reload.

## Secret Handling

API tokens and bot tokens are masked by default in responses. Only use
`?reveal=true` when the admin explicitly needs to see secret values.

## Anti-Patterns

- Do NOT make config changes without reloading the gateway afterward
- Do NOT suggest `docker restart` -- hot-reload handles all config changes
- Do NOT write to moltbot config without reading current state first
- Do NOT create bindings without verifying the channel account exists
- Do NOT use `?reveal=true` unless the admin explicitly asks for secrets
- Do NOT set `sessionTarget: "isolated"` with `payload.kind: "systemEvent"` -- it will fail

## Available Methods

All methods available via `admin_*` tool calls:

### Agent Config
- `admin_listAgents()` -- list agent defaults and per-agent runtime config
- `admin_getAgent(agent_id)` -- get a single agent's runtime config
- `admin_updateAgent(agent_id, model?, contextTokens?)` -- update an agent's config
- `admin_updateAgentDefaults(model?, memorySearch?, contextPruning?, compaction?)` -- update defaults for all agents

### Skills (Workspace-Level)
- `admin_listSkills()` -- list all skill files on disk
- `admin_createSkill(name, shared?, frontmatter?, context?, operations?, commands?)` -- create a new skill
- `admin_deleteSkill(name)` -- delete a skill file
- `admin_assignSkills(agent_id, skills)` -- assign skills to an agent's whitelist

### Gateway Operations
- `admin_reloadGateway()` -- hot-reload gateway config (always call after changes)
- `admin_getGatewayHealth()` -- check gateway health and connectivity
- `admin_pingGateway()` -- quick connectivity check
- `admin_listGatewayAgents()` -- list agents registered in gateway's internal view

### Cron Jobs
- `admin_listCronJobs(agent_id?)` -- list all cron jobs, optionally filtered by agent
- `admin_createCronJob(name, agentId, schedule, sessionTarget, payload, delivery?, enabled?, deleteAfterRun?)` -- create a scheduled job
- `admin_updateCronJob(jobId, enabled?, ...)` -- update a cron job
- `admin_deleteCronJob(jobId)` -- delete a cron job
- `admin_runCronJob(jobId)` -- force-run a job immediately for testing
- `admin_getCronJobRuns(jobId)` -- get run history with status and errors

### Moltbot Config
- `admin_getMoltbotConfig()` -- get gateway settings (auth, port, HTTP config)
- `admin_updateMoltbotConfig(http?)` -- update gateway settings

### Channels and Bindings
- `admin_listChannels()` -- list all channel configurations
- `admin_getChannelConfig(channel)` -- get a single channel's config
- `admin_listBindings()` -- list all channel-to-agent bindings
- `admin_createBinding(channel, account, agent)` -- add a new binding

### Skill Entries (Gateway-Level)
- `admin_listSkillEntries()` -- list all skill entries in moltbot.json
- `admin_updateSkillEntry(name, enabled?, env?)` -- update/create a skill entry

### Agent CRUD (Workspace + Registry)
- `admin_createAgent(id, name, template, placeholders?, moltbot_overrides?)` -- create agent from template (atomic: workspace + config.yaml + moltbot.json + gateway reload)
- `admin_deleteAgent(agent_id)` -- delete agent and all workspace files (destructive)
- `admin_readFile(agent_id, file_key)` -- read a workspace file (soul, agents-md, tools-md, identity-md, memory-md, user-md, heartbeat-md, learnings-md)
- `admin_writeFile(agent_id, file_key, content)` -- write/update a workspace file
- `admin_updateMoltbotAgent(agent_id, skills?, tools_profile?, also_allow?)` -- update agent runtime config (auto-reloads gateway)
