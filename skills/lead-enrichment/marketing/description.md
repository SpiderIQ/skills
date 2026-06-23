## lead-enrichment

Kanban-style enrichment board. 9 tool calls — manage leads through stages, attach notes, assign owners, query board state.

### What this skill does

- **`list_columns`** — board column definitions (typically `New / In Research / Contacted / Qualified / Won / Lost`).
- **`list_leads`** — leads in a column, paginated, filterable by tag/owner/age.
- **`get_lead`** — full lead detail including all attached IDAP entities (business, contacts, emails, phones, branding).
- **`move_lead`** — transition between columns. Move events are audit-logged and emit SSE events visible to `events-stream`.
- **`assign_lead`** / **`unassign_lead`** — owner assignment for human/agent collaboration.
- **`add_note`** / **`list_notes`** — attach context (call transcripts, prior interactions, qualification notes).
- **`add_tag`** / **`remove_tag`** — flexible categorization.

### Why a board, not a flat list?

Lead-gen is a stateful workflow — a lead goes through stages, accumulates context, and changes hands. A kanban model captures that lifecycle and makes the state queryable: "give me all leads in `Qualified` that have been there >7 days without movement" is a meaningful question that a flat list can't answer cleanly.

### Typical workflows

- **Auto-progression** — agent watches enrichment events. When `verify-email-deliverability` returns `valid` for a lead in `New`, agent auto-moves to `In Research` and triggers `lookup-company-data`.
- **Stale-lead detection** — agent queries `list_leads(column='Qualified', age_gt='7d')`, surfaces leads that have stalled, drafts re-engagement.
- **Hybrid human+agent** — humans drag leads on the dashboard, agent picks up the move event, runs the next enrichment step automatically.

### Identity model

Every lead is owned by a (brand, optional assignee). Agents acting on the brand can read all leads; assignees can be either humans or other agents.
