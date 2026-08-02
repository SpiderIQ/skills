---
name: verify-email-deliverability
version: 1.0.0
client: verify-email-deliverability
client_version: "1.0.0"
description: Verify email addresses for deliverability via SMTP checking.
category: data-collection
triggers:
  - verify email
  - check email
  - validate email
  - is this email valid
  - email verification
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U00002709"
    primaryEnv: OPVS_PAT
---

# Verify Email Deliverability

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## When to Use This Skill

Use **verify-email-deliverability** when the user wants to check whether email addresses are real and safe to send to. This is the natural next step after extracting emails with `scrape-website-extract-leads` or before launching an outreach campaign. Performs SMTP-level checks, not just format validation.

**Do NOT use this skill for:**
- Finding email addresses -- use `scrape-website-extract-leads` to extract them from websites first
- Sending emails -- this only validates deliverability, it does not send anything
- Looking up a person by email -- use `find-people-extract-linkedin-profile` to research people

## Job Type

| Type | What It Does |
|------|--------------|
| `spiderVerify` | Checks one or more email addresses via DNS MX record lookup and SMTP mailbox probing. Returns deliverability status, risk score, and flags for disposable/role-based/free-provider addresses |

## Expected Processing Times

- **1-5 emails:** 5-15 seconds
- **10-50 emails:** 15-30 seconds
- Larger batches scale linearly

## What Results Contain

For each email verified: deliverability status (valid/invalid/risky/unknown), a risk score from 0.0 (safe) to 1.0 (dangerous), and boolean flags for disposable email services, role-based addresses (info@, support@), and free providers (Gmail, Yahoo). Also includes MX records and SMTP server response details.

### Risk Score Quick Reference

| Score | Meaning |
|-------|---------|
| 0.0 - 0.3 | Safe to send |
| 0.3 - 0.6 | Send with caution |
| 0.6 - 1.0 | Avoid sending -- high bounce risk |

## Anti-Patterns

- Do NOT verify more than 100 emails in a single job -- split large lists into batches of 50
- Do NOT re-verify emails that were already checked recently -- results are cached for 24 hours
- Do NOT use this as a substitute for a proper email warm-up process -- verification confirms the address exists but does not guarantee inbox placement

## Response Guidelines

- Group results by status: deliverable, risky, invalid
- Show risk score and key flags (disposable, role-based) for each email
- For bulk results, show summary counts first (e.g., "12 valid, 3 risky, 5 invalid"), then details
- Recommend removing emails with risk_score above 0.6 from outreach lists
- If many results are role-based (info@, support@), suggest finding personal contacts instead

## Available Methods

- `submitJob` -- Submit an email verification job
- `getJobStatus` -- Check the current status of a submitted job
- `getJobResults` -- Retrieve the verification results
- `cancelJob` -- Cancel a running or queued job
