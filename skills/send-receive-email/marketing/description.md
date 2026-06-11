## send-receive-email

The full SpiderMail surface for agents. 11 tool calls covering inbox browsing, thread reading, sends, replies, and templates.

### What this skill does

- **Browse mailboxes** — `list_mailboxes` returns every box the brand has access to: inboxes, shared, archives. Box metadata includes unread count, last activity, and access level.
- **Read messages and threads** — `list_messages`, `get_message`, `list_threads`, `get_thread`. Threads are first-class — agents can request a full conversation in order, with all attachments inlined as references.
- **Inbox hygiene** — `mark_read`, `mark_unread`, `archive_thread`. State changes are audit-logged.
- **Compose + reply** — `compose_message` for new threads, `reply_to_thread` for ongoing conversations. Both accept a list of attachments by reference (use `upload-host-media` from `@spideriq/publish-skills` to host them first if needed).
- **Templates** — `list_templates`, `render_template`. Templates are authored by humans in the SpiderMail dashboard; agents render them with variables and then send via `compose_message` or `reply_to_thread`.

### Typical workflows

- **Inbox triage** — list unread threads, get each, classify, mark-read or archive based on classification.
- **Lead follow-up** — query mail for threads from a specific sender, reply with a templated message customized per recipient.
- **Approval workflow** — agent reads an "approval request" thread, makes the decision according to its policy, replies with the resolution.

### Auth + isolation

Per-brand scoping is enforced server-side — there's no flag the agent can pass to escape the active brand's mailbox. Send authorization is per-mailbox; the brand admin controls which mailboxes a given agent can send from.
