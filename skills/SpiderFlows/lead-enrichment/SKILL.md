---
name: lead-enrichment
version: "2.0.0"
description: >
  Enrichment workflow patterns for Company boards — create enrichment
  boards, bulk import leads, move cards through stages, link contacts,
  and export enriched data.
category: board
client: lead-enrichment
client_version: "1.0.0"
triggers:
  - enrichment
  - leads
  - board
  - pipeline
  - import
metadata:
  openclaw:
    emoji: "\U0001F50D"
    primaryEnv: OPVS_PAT
---

# Lead Enrichment -- Board Workflow Patterns

## Purpose

Work on Company-type AgentBoard boards as enrichment workspaces. Each card
is a lead. Columns are enrichment stages. Custom fields hold enrichment
data. This skill teaches the workflow -- data source skills provide the
actual research tools.

## When to Use

- Client uploads a CSV/Excel of business leads to enrich
- Client asks you to find and enrich leads matching criteria
- You need to track enrichment progress on a Company board
- You need to create Contact cards for discovered employees

## Enrichment Pipeline

### Column Stages

| Column | Meaning |
|--------|---------|
| **Pending** | Unprocessed leads waiting for research |
| **Researching** | Agent is actively investigating this lead |
| **Confirmed** | Matched to a real entity with confidence |
| **Enriching** | Confirmed entity being enriched with full data |
| **Complete** | Fully enriched, all data collected |
| **Ambiguous** | Multiple plausible matches -- needs human decision |
| **Not Found** | No results found despite spelling variant attempts |

### Status Transitions

```
Pending -> Researching     (agent begins work)
Researching -> Confirmed   (match found with sufficient confidence)
Researching -> Ambiguous   (multiple candidates, needs human review)
Researching -> Not Found   (no results after spelling variants)
Confirmed -> Enriching     (agent begins full enrichment)
Enriching -> Complete      (all enrichment data collected)
Ambiguous -> Researching   (human resolved the ambiguity -- reprocess)
```

**IMPORTANT:** Move cards between columns to change status. Never update
status directly.

## Data Storage Conventions

### Custom Fields for Enrichment Data

Populate these fields during enrichment: `website`, `phone`, `email`,
`industry`, `location`, `size`, `domain`, `rating`, `review_count`,
`social_links`, `revenue`, `category`, `full_address`.

### Enrichment-Specific Fields

Track progress with: `confidence` (0.0-1.0), `match_reasoning` (explain
your choice), `lead_score` (0-100), `data_completeness` (0.0-1.0),
`place_id`, `linkedin_url`, `emails_verified`, `employees_found`.

### agent_context -- Search Evidence

Store all search results and input data in `agent_context`. This is the
evidence you collected during research.

### agent_result -- Final Decision

Store your disambiguation decision, confidence score, matched source, and
enrichment summary in `agent_result`.

## Contact Discovery

When enrichment discovers employees, create Contact cards on a linked
Contact board and link them to the company card using the `belongs_to`
relationship type.

## Progress Reporting

Post structured progress to your tracking task every heartbeat:

```
Heartbeat #14: Processed 13 leads.
  - Confirmed: 11 (avg confidence 0.89)
  - Ambiguous: 1 (Row 847 "Greggs Manchester" -- 23 locations)
  - Not Found: 1 (Row 901 "XYZ Tech Solutions" -- no results)
  Total: 168/2000 complete (8.4%). ETA: ~12 hours.
```

## Lead Score Guidelines

After enrichment is complete, assess lead quality (0-100). Consider:
- Was the match confirmed with high confidence?
- Were verified emails found?
- Was a LinkedIn company profile found?
- Does the website have contact information?
- Google Maps rating and review count?
- Were key employees (decision makers) discovered?
- Social media presence across platforms?

Higher score = more data points confirmed. Adjust weighting based on the
client's research brief.

## Anti-Patterns

- Do NOT skip the Researching stage -- always research before confirming
- Do NOT mark Ambiguous leads as Complete without human resolution
- Do NOT import more than 100 leads per batch
- Do NOT update status directly -- move cards between columns instead
- Do NOT create enrichment boards without the `column_preset: "enrichment"` flag

## Available Methods

All methods available via `enrichment_*` tool calls:

- `enrichment_createBoard(name, board_type, column_preset?)` -- create an enrichment board with the correct column structure
- `enrichment_bulkImportTasks(board_id, tasks)` -- bulk import up to 100 leads as task cards
- `enrichment_moveTask(task_id, column_id)` -- move a lead card to a different enrichment stage
- `enrichment_createTask(board_id, title, custom_fields?, description?, column_name?)` -- create a single contact card
- `enrichment_updateTask(task_id, custom_fields?, agent_result?, agent_context?)` -- update task with enrichment data
- `enrichment_linkTasks(task_id, target_task_id, relationship_type)` -- link contact to company (belongs_to)
- `enrichment_listColumns(board_id)` -- list columns to get column IDs for movement
- `enrichment_exportBoard(board_id, format?)` -- export enriched leads as CSV or JSON
- `enrichment_addComment(task_id, content)` -- post a progress report comment
