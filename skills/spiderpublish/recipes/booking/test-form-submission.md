# recipes/booking/test-form-submission

Submit a **fake test answer** to a published form to verify validation + routing + storage end-to-end, without polluting production responses. Uses `form_test_submit` (or the marketplace twin `marketplace_form_test_submit`).

## When to use

- After editing a form's validation rules — confirm a bad payload returns the right `declared_fields` envelope.
- After wiring up routing/email notifications — confirm the submission shows up in the responses dashboard.
- CI / scripted smoke tests after deploys — see [`../audit/deploy-readiness.md`](../audit/deploy-readiness.md).
- Verifying a marketplace form template behaves correctly before recommending it.
- Pattern: "I want to know this form actually works without filling it in by hand."

## Prerequisites

- A PAT scoped to the tenant.
- The form's `flow_id`.
- The form **must be published** — `form_test_submit` reads only `status='active'` rows and returns 404 for drafts. Call `form_publish` first.
- An answer payload that matches the form's declared fields.

## The one call

```
form_test_submit({
  flow_id: "<uuid>",
  answers: {
    "email":      "qa@example.com",
    "first_name": "QA Bot",
    "company":    "ACME"
  }
})
# → {
#     success: true,
#     status:  200,
#     accepted: true,
#     body: { submission_id: "sub_...", ... }
#   }
```

The tool POSTs to `/api/v1/booking/{flow_id}/submit?test=true` with auto-generated `Idempotency-Key` and `X-Customer-Timezone: UTC` headers. Body can be **flat** `{field_id: value}` OR **nested** `{step_id: {field_id: value}}` — match whichever shape your form's `flow.json` uses.

### With explicit headers

```
form_test_submit({
  flow_id:         "<uuid>",
  answers:         { ... },
  idempotency_key: "qa-2026-05-24-001",     # for reproducible runs
  timezone:        "Europe/Berlin"            # affects timestamp interpretation server-side
})
```

## ⚠️ What `?test=true` actually does

**Honest framing**: the `?test=true` query param is forwarded to the endpoint, but it **only suppresses SendGrid confirmation emails for the shared QA load-test tenant** (`LOAD_TEST_CLIENT_ID`). For arbitrary tenants, it does NOT:

- Bypass the published-required gate (you still need `status='active'`).
- Suppress notification webhooks or other configured automations.
- Mark the submission as "test" in the responses table — it shows up as a real submission.
- Suppress count metrics on the dashboard.

If you need true isolation, use a **dedicated test tenant** (a sandbox `cli_*` you can wipe) rather than relying on `?test=true` on a production tenant.

## The marketplace twin

For marketplace-listed form templates (browsing the public catalog, validating examples before adopting):

```
marketplace_form_test_submit({
  template_slug: "newsletter-2step",
  answers:       { email: "qa@example.com" }
})
```

Submits against the canonical published example of the marketplace template, NOT against a tenant flow. Same envelope shape; same idempotency semantics. Use it when validating a template before `form_create_from_template`.

## Validation-error envelopes

Bad payloads return a structured envelope:

```json
{
  "success": false,
  "status": 400,
  "accepted": false,
  "body": {
    "code": "field_validation_failed",
    "errors": [
      { "field_id": "email", "code": "format", "message": "Not a valid email." }
    ],
    "declared_fields": ["email", "first_name", "company"]
  }
}
```

`declared_fields` is the canonical list of field IDs the form expects — surface it when you got a field-mismatch 400 to help the caller fix the payload shape.

Common error codes: `required` (missing), `format` (bad email/phone/url), `enum` (not in choices), `range` (out of min/max), `pattern` (regex mismatch).

## Steps — typical QA flow

```
1. form_get({ flow_id })                      — read the field list to construct payload
2. form_publish({ flow_id })                  — if not already; safe-default gated
3. form_test_submit({ flow_id, answers })     — happy path
4. form_test_submit({ flow_id, answers: {...with one bad field} })
                                              — confirm validation envelope
5. (Eyeball the responses dashboard or query the `form_responses` table)
```

For CI:

```bash
# Smoke test on every deploy
spideriq form submit test --flow-id <uuid> --answers '{"email":"qa@example.com"}'
# Exit 0 on accepted=true; non-zero on any validation error
```

## Gotchas

- **404 on a draft form is the most common failure.** `form_test_submit` requires `status='active'`. Publish first.
- **Idempotency-Key is auto-generated if absent** — fine for one-off tests, problematic for retries. Pass an explicit key for reproducible runs (a duplicate key returns the original response without re-inserting).
- **Field-id mismatch returns 400 with `declared_fields`.** Read the envelope — the field IDs in your payload may differ from the form's actual field IDs (especially after `form_remove_field` + `form_add_field` re-runs).
- **Nested vs flat payload depends on the form's step structure.** Single-step forms accept flat. Multi-step forms accept either, but if you're testing per-step validation, use nested to scope errors correctly.
- **Submissions land in the real responses table.** Use a dedicated test tenant for high-volume tests; relying on `?test=true` to "clean up later" doesn't work — there's no automatic test-submission purge.
- **Notifications fire.** If the form has an email-routing rule or webhook, a test submission triggers them. Disable routing for QA flows OR use a dummy email + webhook URL.

## Verify

```
# Confirm the submission landed
GET /api/v1/dashboard/booking/flows/<flow_id>/responses?limit=1
# → most recent submission carries your test payload

# OR via CLI
spideriq form responses list <flow_id> --limit 1
```

For visual confirmation that the form itself is rendering before testing:

```
content_visual_check({
  page_url: "https://<tenant>/f/<flow_id>",
  viewport: "desktop"
})
# Assert: dom.shadow_hosts.includes("spideriq-form")
# DO NOT assert on body_text_preview — see Rule 62 in ../reference/booking-model.md
```

## Anti-patterns

- **Testing against draft forms expecting it to "just work."** 404. Publish first.
- **Relying on `?test=true` for test/prod isolation.** It only suppresses SendGrid for the load-test tenant. Use a sandbox tenant.
- **Looping `form_test_submit` 100× to load-test.** Use the load-test tenant + dedicated tooling; you'll trip rate limits on a real tenant.
- **Hardcoding field IDs from old form versions.** Read `form_get` → `flow.json.fields[]` for current IDs every time; `form_update_field` may have renamed them.
- **Composing the submit URL by hand.** Use the MCP tool — the path encoding + headers + idempotency-key generation all matter and are easy to get wrong manually.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "submit a test answer to a form"
# Top-1 should be: recipes/booking/test-form-submission.md
```

## See also

- [`build-form.md`](build-form.md) — author the form before testing it
- [`lock-form-for-review.md`](lock-form-for-review.md) — freeze the form during QA so it doesn't change mid-test
- [`form-as-page-section.md`](form-as-page-section.md) — embed the form in a page; test-submit still hits the same endpoint
- [`../audit/deploy-readiness.md`](../audit/deploy-readiness.md) — wire test-submit into the pre-deploy checklist
- [`../reference/booking-model.md`](../reference/booking-model.md) — `booking_flows` schema + Rule 62 visual-check assertion
