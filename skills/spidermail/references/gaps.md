# CLI / MCP gaps — CLOSED by the companion tools PR (was: the delta)

> **STATUS UPDATE 2026-06-11: these gaps are now CLOSED.** The companion PR
> `feat/mail-cli-mcp-tools` brings `@spideriq/core` + `@spideriq/mcp-mail` +
> `@spideriq/cli` up to the **full 45-method** surface this skill teaches (core
> 1.26.0 / mcp-tools 1.28.0 / mcp-mail 1.3.0 / mcp 1.31.0 / cli 1.25.0; builds +
> cli-smoke green; publish is post-merge). The delta below is retained as the
> record of what was missing and was added. If you're reading this after that PR
> merged + published, the CLI and MCP cover everything here.

This skill (the marketplace Tier-3 client) generates its methods directly from
`client/schema.yaml`'s HTTP declarations, so it covers the **full** SpiderMail PAT
surface. Before the companion PR, the **CLI** (`@spideriq/cli`) and **MCP**
(`@spideriq/mcp-mail`) surfaces did NOT — they wrapped a thinner (and partly
wrong) set of `@spideriq/core` methods.

**None of these ever blocked this skill** — every method it declares maps to a
real, PAT-reachable HTTP route (verified 2026-06-11). They were recorded per the
authoring requirement to surface missing CLI/MCP capability; the companion PR then
closed them (and fixed 4 pre-existing core route/param bugs — see end).

Verification basis (2026-06-10):
- CLI: `packages/cli/src/commands/mail.ts` (193 lines, 3 commands).
- MCP: `packages/mcp-tools/src/mail/mail.ts` (11 tools).
- core: `packages/core/src/client.ts` (mail methods grep).
- API: `app/api/v1/mail.py`, `app/api/v1/mail_templates.py`, `app/api/v1/jobs/spidermail.py` (route decorators).

This skill teaches **45 methods**. The CLI/MCP/core surfaces cover only a small
fraction of them; the table below is the full delta.

## Gap 1 — the CLI exposes only 3 read commands (of 45)

`spideriq mail` has exactly: `mailboxes`, `list <mailbox>`, `read <mailbox> <msg>`.
A foreign agent driving SpiderIQ through the CLI can **browse but cannot act** —
there is no CLI command for:

| Capability | HTTP route (exists) | CLI command (missing) |
|---|---|---|
| send / reply / forward | `POST /jobs/spiderMail/submit` | `spideriq mail send` |
| search | `GET /mail/search` | `spideriq mail search` |
| thread | `GET /mail/threads/{id}` | `spideriq mail thread` |
| session bootstrap | `GET /mail/session` | `spideriq mail session` |
| flags (read/star/label) | `PATCH /mail/messages/{id}` | `spideriq mail flag` |
| bulk triage | `POST /mail/messages/bulk` | `spideriq mail bulk` |
| snooze | `/mail/messages/{id}/snooze` | `spideriq mail snooze` |
| folders | `GET /mail/folders` | `spideriq mail folders` |
| labels (CRUD) | `/mail/labels*` | `spideriq mail labels` |
| saved views (CRUD) | `/mail/views*` | `spideriq mail views` |
| templates (list/preview/CRUD) | `/mail/templates*` | `spideriq mail templates` |
| compose-assist | `POST /mail/compose/assist` | `spideriq mail compose` |
| outreach + warmup | `/brands/{id}/mail/outreach/*` | `spideriq mail outreach` |

**Suggested fix:** add the above subcommands to `packages/cli/src/commands/mail.ts`
(each is a thin wrapper over a new `@spideriq/core` method — see Gap 3).

## Gap 2 — the MCP slice is missing template + flag tools

`@spideriq/mcp-mail` ships 11 tools: `list_mailboxes`, `list_messages`,
`read_message`, `send_email`, `get_inbox`, `search_mail`, `get_thread`,
`create_mailbox`, `delete_mailbox`, `test_mailbox`, `compose_assist`. Missing
relative to what this skill teaches:

- **No template tools at all** — an MCP agent cannot `list/get/create/preview` a
  template, so it cannot render-before-send or apply a saved template. (The API
  has full CRUD + preview in `mail_templates.py`.)
- **No flag/state tool** — there is no `update_message` MCP tool, so an MCP agent
  cannot mark read / star / label. (The API has `PATCH /mail/messages/{id}`.)
  Note: the **previous** skill schema even *declared* an `updateMessage` method,
  but no MCP tool or core method backed it — this expanded schema declares it
  against the real route.
- **No session / mailbox-stats / quarantine tools** — `get_session`,
  `get_mailbox_stats`, `list_quarantine`, `release_message` are API-only.
- **No organise tools** — `folders`, `bulk` triage, `snooze`, label-CRUD, and
  saved-view CRUD have no MCP tool. (All `/mail/*`, PAT-reachable.)
- **No outreach/warmup tools** — none of the Smartlead/lemlist/Instantly
  connection / sender / health surface is exposed via MCP.

**Suggested fix:** add `mail_get_template`, `mail_list_templates`,
`mail_create_template`, `mail_preview_template`, `mail_update_message`,
`mail_get_session`, `mail_bulk_update`, `mail_snooze`, `mail_list_labels`,
`mail_create_view`, `mail_outreach_health` (+ siblings) to
`packages/mcp-tools/src/mail/mail.ts` (+ core methods).

## Gap 3 — `@spideriq/core` lacks the backing methods

The core client (which both CLI and MCP call) exposes only: `listMailboxes`,
`listMessages`, `readMessage`, `getInbox`, `searchMail`, `getThread`,
`createMailbox`, `deleteMailbox`, `testMailbox`, `composeAssist`, `submitJob`.
It has **no** mail-template method, **no** `updateMessage`/flag method, **no**
`getSession`, **no** quarantine method. So Gaps 1 & 2 both bottom out here — the
fix is: add these methods to `packages/core/src/client.ts` once, then wire the CLI
command and the MCP tool over each.

Also: the MCP `compose_assist` tool's params (`prompt`, `draft`) **do not match**
the real API (`action`, `context`, `subject`, `tone`, `thread_context`). The skill
schema uses the real API shape; the MCP tool should be reconciled to it.

## Gap 4 — attachment full-text has no PAT route (minor SpiderMail bug)

`GET /mail/messages/{id}?include_attachments=true` returns each attachment's
metadata + an extracted-text **preview** (~500 chars) inline, and emits a hint
`retrieve_via: /api/v1/mail/attachments/{att_id}`. **That route is not served** —
grep of `app/` finds no `@router.get(".../attachments/{...}")`. So:

- The inline preview is the only PAT-reachable attachment text.
- The `retrieve_via` URL is a dead link (404). It should either be implemented
  (a `GET /mail/attachments/{id}` returning `full_text`/`storage_key`) or removed
  from the YAML output to avoid promising a route that doesn't exist.

This does not block the skill (it teaches the inline-preview reality) but is worth
fixing in SpiderMail. Captured in
`learnings/2026-06-10-attachments-inline-only/`.

## Scope decision — outreach/warmup lives HERE (not admin-skills 1.7)

`mail_outreach.py` (Smartlead/lemlist/Instantly connections + sender warmup +
deliverability health) is brand-admin-scoped integration management, which the
skill-suite plan's per-service map nominally assigns to **session 1.7
workspace-admin (`admin-skills`, "brands/integrations")**. The owner decided
(2026-06-10) that it belongs in **`@spideriq/mail-skills`** instead — it is an
email surface and reads are PAT-ok.

**Coordination flag for session 1.7:** `admin-skills` must NOT also ship the
`/brands/{id}/mail/outreach/*` methods, or two packages claim the same surface at
merge. Recorded on the board (task 1.1 comment) so the planner/1.7 sees it.

## What the companion PR added (the fix)

`feat/mail-cli-mcp-tools` (core 1.26.0 / mcp-tools 1.28.0 / mcp-mail 1.3.0 / mcp
1.31.0 / cli 1.25.0):
- **core/client.ts** — +34 mail methods covering every skill method, and FIXED 4
  pre-existing route/param bugs: `listMessages`/`readMessage` pointed at the
  phantom `/mail/{id}/messages…` (now `/mail/inbox?email=` and
  `/mail/messages/{id}`); `getInbox` used `mailbox` not `email`; `searchMail` used
  `query`/`from`/`date_from` not the real `email`/`q`/`from_addr`/`since`/`before`.
- **mcp-tools/mail.ts** — 11 → 46 tools, and FIXED `compose_assist` (was sending
  `prompt`/`draft`, which the API ignores; now `action`/`context`/…) and
  `create_mailbox` (was `email`/`password`; now `email_address`/`imap_*`/`smtp_*`).
- **cli/mail.ts** — 3 → 46 subcommands via a shared `runMail()` helper.

## Status

No `needs-replan` was raised: the skill is fully authorable against the live HTTP
surface (45 methods, every one a verified-served route). The CLI/MCP/core gaps are
now CLOSED by the companion PR (post-merge publish), not deferred.
