## social-media-enrichment

The "it has a Facebook page but no email" rescue skill. One business's social
handles in → a recovered email / phone / real website / socials out, or a typed
skip. Backed by the SpiderSocial worker.

### What this skill does

- **`submit_social_enrichment`** — takes a business's known social handles
  (Facebook preferred, then Instagram) and/or a single social-only website
  (linktr.ee / fb / ig), and recovers whatever contact info it can. Returns a
  `job_id`.
- **`get_job_results`** — the recovered `{email, phone, website, socials}` with a
  `recovered_fields` list and `credits_spent` / `cost_usd`, OR a typed skip
  `reason`.
- **`get_job_status`** — progress.
- **`cancel_job`** — abandon a queued job.

### How recovery works

The recovery reads the business's social profiles and folds any recovered
contact info back in **additively** — it never overwrites a value you passed. If
the business already has a usable email, the job self-skips (`has_email`) so a
credit is spent only where it's actually needed.

### Typical workflows

- **Rescue a no-email lead** — `scrape-website-extract-leads` returned a business
  with social links but no email; this skill recovers one, then
  `verify-email-deliverability` confirms it's safe to send.
- **Bulk, via the campaign toggle** — for a whole list, enable
  `workflow.social_media_enrichment` on a `lead-search` campaign instead of
  looping; every no-email business is enriched, re-verified, and merged back
  automatically.

### Why this matters

A business with an active Instagram but no email on its site is a lead you'd
otherwise drop. Recovering the contact from the profile it *does* maintain turns
a dead row into a deliverable one — and you pay only when a field is actually
recovered.

### Cost & gating

Social Media Enrichment is a paid, plan-gated capability. A recovery spends a
credit; a skip costs nothing. Pass a stable `place_id` as the exactly-once key so
a retried business is never billed twice.
