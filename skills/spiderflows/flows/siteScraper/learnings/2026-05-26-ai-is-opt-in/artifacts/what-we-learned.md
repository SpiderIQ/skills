# AI is opt-in, and CHAMP needs both halves

**Starting point, not ground truth — verify against current code.**

## The surprise

A default site crawl (`mode: contacts`) returns emails, phones, socials, and a
logo — but **no** team members, company vitals, or lead score. That's not a
failure: AI extraction is **opt-in**, and `contacts`/`compendium` spend **zero** AI
tokens. The AI sections come back `null`.

## What turns AI on

- `extract_team` → `team_members[]` (~500 tokens)
- `extract_company_info` → `company_vitals` (~500 tokens)
- `extract_pain_points` → `pain_points` (~500 tokens)
- `mode: leads` flips `extract_team` + `extract_company_info` on; `mode: full` adds
  pain points + lead scoring.
- `custom_ai_prompt` → `custom_analysis` (requires `compendium.enabled=true` and at
  least one of `system_prompt` / `user_prompt`, else `422`).

## CHAMP lead scoring is both-or-nothing

`lead_scoring` only appears when you pass **both** `product_description` **and**
`icp_description`. Supplying just one is a hard `422`
(`validate_champ_requirements`). Supply both, or neither.

You don't choose the scoring model — lead analysis is routed server-side through
SpiderGate to 32B+ models (`spideriq/lead-analysis`), because 8B models grade ICP
fit poorly (they call everything an "A"). Pass `product_description` +
`icp_description` and let the gateway handle the rest.

## Reading the results

An empty AI section almost always means **the feature was off**, not that the data
was absent. Before telling the user "no team on this site", confirm you enabled
`extract_team` (or `mode: leads`/`full`) — otherwise `team_members` is `null` by
design.

## Rule of thumb

- Default crawl = contacts only, no AI cost.
- Want team/company/pain-points? Enable the flag (or use `leads`/`full`).
- Want a lead grade? Pass **both** `product_description` and `icp_description`.
- A `null` AI field after a no-AI crawl is expected, not a bug.
