---
name: social-media-enrichment
version: "1.0.0"
description: >
  Social Media Enrichment — recover a missing email, phone, real website, or
  social links for ONE business from its public social handles (Facebook,
  Instagram, LinkedIn, Twitter/X, TikTok) or a single social-only website
  (linktr.ee / facebook / instagram). Recovered fields are folded in additively,
  never overwriting what you passed. Use when a lead has social profiles but no
  usable contact email, as a targeted follow-up after scrape-website-extract-leads
  came back empty, or as the plan-gated social_media_enrichment stage inside a
  lead campaign. A paid, plan-gated capability; the job self-skips (with a typed
  reason) when there's nothing to recover or the business already has an email.
category: data-collection
requires_auth: true
requires_brand: true
triggers:
  - social media enrichment
  - enrich from social media
  - recover email from facebook
  - recover email from instagram
  - find contact from social handles
  - get email from social profile
  - no email but has social
  - recover missing contact info
  - social profile to email
client: social-media-enrichment
client_version: "1.0.0"
metadata:
  openclaw:
    emoji: "\U0001F4E1"
    primaryEnv: OPVS_PAT
---

# Social Media Enrichment

Recover the contact info a lead is missing — from the social profiles it *does*
have.

```
  social handles (facebook / instagram / …)  ─┐
  a social-only website (linktr.ee / fb / ig) ─┼─►  Social Media Enrichment  ─►  { email, phone, website, socials }
  known email/phone (context, folded in)      ─┘                                  OR  { skipped, reason }
```

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first (auth, PAT, `?format=yaml`, polling).

One business in, recovered contact fields out — or a **typed skip** (e.g. the
business already had an email). It reads the business's known handles (Facebook
preferred, then Instagram) plus any single social-only website, and returns
whatever it can recover. Everything recovered is **additive** — it never
overwrites a value you passed in.

## When to Use This Skill

Use **social-media-enrichment** when a business has public social profiles but
**no usable contact email**, and you want to recover one before adding it to an
outreach list. It's the natural rescue step after `scrape-website-extract-leads`
returns a lead with social links but no email.

**Do NOT use this skill for:**
- Extracting emails that are already on a website — use `scrape-website-extract-leads`.
- Checking whether a recovered email is deliverable — pass it to
  `verify-email-deliverability` next.
- Looking up a named PERSON on LinkedIn — use `find-people-extract-linkedin-profile`.
- Running a whole Maps → Site → Verify pipeline — use `lead-search` /
  `run-enrichment-pipeline` (they can turn this on per-campaign via the
  `workflow.social_media_enrichment` toggle; see `references/campaign-toggle.md`).

## Job Type

| Type | What It Does |
|------|--------------|
| `spiderSocial` | Takes ONE business's social handles (+ optional social-only website) and recovers a missing email / phone / real website / social links, or self-skips with a typed reason. Recovered fields are folded in additively. |

<HARD-GATE name="pass-place_id-for-exactly-once">
ALWAYS pass a stable `place_id` (the business's Google place_id) when you have
one. It is the **exactly-once recovery key** — there is NO idempotency key, so
re-submitting the same business is charged again. `place_id` lets the service
recognise a business it has already recovered and avoid double-spending a
credit. Omit it only for a genuine one-off where you have no stable id.
</HARD-GATE>

## Rules (Non-Negotiable)

**READ RESULTS, NOT THE SUBMIT:** the submit returns `job_id` + `status:queued` —
NOT the recovered contact. The recovery runs in a worker seconds later. MUST poll
`getJobResults` until the job is terminal; reporting a recovered email off the
submit response is a silent lie.

**SKIP IS A NORMAL OUTCOME:** a `status: "skipped"` result with a `reason` (e.g.
`has_email`, `no_social_handle`) is a **healthy, expected** result — NEVER treat
it as a failure. The most common skip, `has_email`, means "this business already
had a usable email, so no credit was spent." Surface the reason; don't retry it.

**PROVIDE AT LEAST ONE HANDLE:** pass at least one social handle
(`--facebook`/`--instagram`/…) or a `--website`, or the job self-skips
`no_social_handle` (nothing to try) — it will not error, it just does nothing.

**PLAN-GATED + PAID:** Social Media Enrichment is a paid capability the account's
plan must enable. A non-entitled account's job self-skips `not_entitled` (or the
submit is rejected). Recovery spends a credit ONLY when it actually recovers a
field (a skip costs nothing).

**ADDITIVE, NEVER DESTRUCTIVE:** anything you pass in `email`/`phone` is context
the recovery folds around — it is never overwritten. Passing a known `email`
deliberately triggers the `has_email` self-skip.

## Approach

1. **Gather the business's social handles** — from a prior
   `scrape-website-extract-leads` result, a Maps listing, or the client. Any of
   facebook / instagram / linkedin / twitter / tiktok, and/or a single
   social-only website.
2. **Submit** one enrichment job (`references/run-social-enrichment.md`).
3. **Poll `getJobResults`** — read the recovered `{email, phone, website, socials}`
   or the typed skip `reason`.
4. **Verify a recovered email** before outreach — hand it to
   `verify-email-deliverability`.

## Decision tree — pick a reference

| The user wants to… | Read |
|---|---|
| Recover contact info for one business + read the result | `references/run-social-enrichment.md` |
| Understand the recovered vs. skipped result shape + the reason taxonomy | `references/read-results.md` |
| Turn enrichment on/off for a whole lead campaign (not one business) | `references/campaign-toggle.md` |

## What Results Contain

A completed job returns either a **recovery** or a **skip**:

- **Recovered** — `status: "recovered"`, plus any of `email`, `phone`, `website`
  (a real, non-social site), and `socials` (a map of recovered social links).
  `recovered_fields` lists exactly what was newly found; `credits_spent` /
  `cost_usd` report what the recovery cost.
- **Skipped** — `status: "skipped"`, `skipped: true`, and a `reason`:

  | reason | meaning |
  |---|---|
  | `has_email` | the business already had a usable email — nothing to recover (no credit spent) |
  | `no_social_handle` | no handle or social website was provided to try |
  | `not_entitled` | the account's plan does not include Social Media Enrichment |
  | `over_cap` | the per-campaign / daily usage cap was reached |
  | `sc_unavailable` | recovery is temporarily unavailable (fail-open skip; retry later) |

Full field-by-field breakdown: `references/read-results.md`.

## Expected Processing Times

- **One business:** typically 5–30 seconds (a couple of upstream fetches).
- A self-skip (`has_email` / `no_social_handle`) returns almost immediately.

## Anti-Patterns

- Do NOT report a recovered email from the submit response — poll `getJobResults`.
- Do NOT treat a `skipped` result as an error or auto-retry it — the reason is the answer.
- Do NOT re-submit the same business without a `place_id` — no idempotency key
  means a second submit is charged again (see the HARD-GATE).
- Do NOT send a recovered email without verifying it — pass it through
  `verify-email-deliverability` first.
- Do NOT loop this over a whole city one business at a time — for bulk, enable the
  `workflow.social_media_enrichment` stage on a `lead-search` campaign
  (`references/campaign-toggle.md`).

## Response Guidelines

- Lead with the outcome: "recovered an email + phone" or "skipped — already had
  an email."
- Show `recovered_fields` explicitly so the user sees exactly what's new.
- If `skipped`, state the `reason` in plain language and what (if anything) to do
  next (e.g. `no_social_handle` → gather a handle first; `not_entitled` → the plan
  needs Social Media Enrichment enabled).
- Recommend verifying any recovered email before it enters an outreach sequence.

## Available Methods

- `submitJob` — submit a Social Media Enrichment (`spiderSocial`) job.
- `getJobStatus` — check the current status of the job.
- `getJobResults` — retrieve the recovered fields (or the typed skip reason).
- `cancelJob` — cancel a queued/running job.

Full API surface + the `guidance:` envelope: `client/schema.yaml`.

## References (loaded on demand)

- **Always read before submitting:** `references/run-social-enrichment.md`
- `references/read-results.md` — the recovered/skipped result shape + reason taxonomy.
- `references/campaign-toggle.md` — enable enrichment across a whole lead campaign.

## See also

- **Sibling skills:** `scrape-website-extract-leads` (get the handles first) ·
  `verify-email-deliverability` (verify the recovered email) · `lead-search` /
  `run-enrichment-pipeline` (bulk, via the campaign toggle).
- **Learnings** (`learnings/`) — starting points, not ground truth; verify against
  current behaviour:
  - `2026-07-12-skipped-is-a-normal-result` — a skip is a healthy outcome, not a failure.
  - `2026-07-12-place-id-is-the-exactly-once-key` — no idempotency key; `place_id` prevents double-spend.
