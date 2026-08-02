---
name: vayapin
version: "1.0.0"
description: >
  Create enriched business profiles from crawled data — combines maps data, website content, contact info, and social profiles into a structured VayaPin business card.

category: data-collection
requires_auth: true
requires_brand: true
triggers:
  - create business profile
  - vayapin
  - business card
  - enrich business
client: vayapin
client_version: "1.0.0"
metadata:
  openclaw:
    primaryEnv: OPVS_PAT
---

# vayapin #data_collection

Vayapin CRM integration — manage contacts, deals, pipeline stages

/#lead-enrichment → enrichment board workflows
/#agentboard → general task management
/#send-receive-email → email communication

## Methods

- `submitVayapin(type, payload)` — Create a VayaPin business profile from enriched data. Requires business name, country code, and coordinates. Optionally include crawled markdown, contact info, and social links.
- `getJobStatus(job_id)` — Check status of a VayaPin job.
- `getJobResults(job_id)` — Get results of a completed VayaPin job.
