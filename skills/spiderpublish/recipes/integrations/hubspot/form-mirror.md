# recipes/integrations/hubspot/form-mirror

Mirror a HubSpot form into a SpiderPublish `kind='form'` flow — for tenants migrating off HubSpot or running parallel surfaces. Mapping is one-way (HubSpot → SpiderForms); submissions on the mirrored form route back to HubSpot via webhook.

## When to use

- The tenant has 12 HubSpot forms in production and wants to migrate to SpiderForms without rewriting each by hand.
- Running a SpiderForms surface (faster, custom-themed) while keeping HubSpot as the CRM/marketing-automation backend.
- A/B testing the SpiderForms UX against the HubSpot embed without changing the data destination.
- Pattern: "HubSpot is the data home; SpiderForms is the prettier surface."

## Honest framing

- This is a **one-time-or-periodic mirror**, not a live sync. HubSpot is the source of truth for form *structure*; SpiderForms is the source of truth for form *experience*.
- HubSpot's form schema is rich (calculated fields, smart fields, dependent fields, GDPR consent blocks); SpiderForms covers the common 80%. Expect ~80% of fields to map cleanly; the rest need manual conversion or omission.
- Submissions on the SpiderForms surface POST back to HubSpot's `/submissions/v3/integration/submit` endpoint via a server-side webhook on the SpiderForms flow.

## Prerequisites

- A HubSpot Private App access token with `forms` scope.
- The HubSpot form's `formId` (UUID from HubSpot dashboard URL).
- A SpiderPublish PAT scoped to the tenant.
- HubSpot portal ID (for the submission webhook URL).

## Step 1 — Pull the HubSpot form

```python
import requests

HS_TOKEN = "pat-na1-..."
FORM_ID  = "abc-def-..."

r = requests.get(
    f"https://api.hubapi.com/marketing/v3/forms/{FORM_ID}",
    headers={"Authorization": f"Bearer {HS_TOKEN}"}
)
hs_form = r.json()

# Returns:
# {
#   id, name, fieldGroups: [{fields: [{name, label, fieldType, required, options, ...}]}],
#   submitButton, redirectUrl, notifications, ...
# }
```

## Step 2 — Map fields

| HubSpot `fieldType` | SpiderForms type | Notes |
|---|---|---|
| `single_line_text` | `short_text` | Direct |
| `multi_line_text` | `long_text` | Direct |
| `email` | `email` | Direct (with format validation) |
| `phone` | `phone` | Direct |
| `number` | `number` | Direct (min/max from HubSpot validations) |
| `date` | `date` | Direct |
| `single_checkbox` | `boolean` | Yes/no semantics; HubSpot's "consent" subtype maps to `gdpr_consent` SpiderForms field |
| `multiple_checkboxes` | `multiple_choice` | Options array maps 1:1 |
| `dropdown` | `single_choice` (dropdown variant) | Options array maps 1:1 |
| `radio` | `single_choice` (radio variant) | Same |
| `file` | `file_upload` | Direct (size limit aligns to SpiderForms tenant config) |
| `calculation` | **NOT SUPPORTED** | Omit; compute server-side after submission |
| `smart_field` (progressive profiling) | **NOT SUPPORTED** | Omit; use SpiderForms variables to approximate |

```python
def map_hubspot_field(hs_field):
    SUPPORTED = {
        "single_line_text": "short_text",
        "multi_line_text":  "long_text",
        "email":            "email",
        "phone":            "phone",
        "number":           "number",
        "date":             "date",
        "single_checkbox":  "boolean",
        "multiple_checkboxes": "multiple_choice",
        "dropdown":         "single_choice",
        "radio":            "single_choice",
        "file":             "file_upload"
    }
    if hs_field["fieldType"] not in SUPPORTED:
        return None    # skip unsupported types; log them

    return {
        "id":          hs_field["name"],
        "type":        SUPPORTED[hs_field["fieldType"]],
        "label":       hs_field["label"],
        "required":    hs_field.get("required", False),
        "placeholder": hs_field.get("placeholder", ""),
        "choices":     [{"label": o["label"], "value": o["value"]}
                        for o in hs_field.get("options", [])]
    }

sp_fields = [
    f for f in (map_hubspot_field(hf) for fg in hs_form["fieldGroups"] for hf in fg["fields"])
    if f is not None
]
unsupported = [
    hf for fg in hs_form["fieldGroups"] for hf in fg["fields"]
    if hf["fieldType"] not in {"single_line_text", "multi_line_text", "email", ...}
]
print(f"Mapped {len(sp_fields)} fields; skipped {len(unsupported)} unsupported")
```

## Step 3 — Create the SpiderForms flow

```
form_create({
  name:  hs_form.name,
  kind:  "form",
  flow: {
    title:    hs_form.name,
    fields:   sp_fields,
    submit_button_text: hs_form.submitButton.text || "Submit"
  },
  theme: { preset: "card-light" }     // or whatever matches the tenant brand
})
# → { flow_id: "flow_..." }
```

## Step 4 — Wire the submission webhook back to HubSpot

Submissions on the SpiderForms flow must POST to HubSpot to keep the CRM in sync:

```
form_update({
  flow_id: "<flow_id>",
  changes: {
    submission_destinations: [
      {
        type: "webhook",
        url:  f"https://api.hsforms.com/submissions/v3/integration/submit/{PORTAL_ID}/{FORM_ID}",
        payload_template: {
          "fields": [
            { "name": "{{field_id}}", "value": "{{field_value}}" }
          ],
          "context": {
            "pageUri":  "{{submission_page_url}}",
            "pageName": "{{submission_page_title}}"
          }
        }
      }
    ]
  }
})
```

The webhook fires on every submission, mapping SpiderForms field IDs back to HubSpot field names. **Field IDs MUST match HubSpot's internal names** (which is why we used `hs_field["name"]` as the SpiderForms field `id` in Step 2).

## Step 5 — Publish + embed

```
form_publish({ flow_id })            # safe-default gated
form_get_embed_snippet({ flow_id })  # for external sites
# OR embed into a SpiderPublish page — see ../../booking/form-as-page-section.md
```

## Steps — full flow

```python
1. hs_form = pull_hubspot_form(FORM_ID)
2. sp_fields, unsupported = map_fields(hs_form)
3. (audit unsupported; decide skip vs manual port)
4. flow = form_create(name, fields=sp_fields, ...)
5. form_update(flow_id=flow.id, submission_destinations=[hubspot_webhook])
6. form_publish(flow_id=flow.id)
7. (embed or share via /f/<flow_id>)
8. (test submission lands in HubSpot's responses dashboard)
```

## Gotchas

- **HubSpot's "dependent fields" (show field X if Y is checked) need manual rebuild** as SpiderForms conditional logic via `form_add_logic_rule`. Audit which HubSpot fields have `dependentFieldFilters` and port them by hand.
- **GDPR consent blocks are critical.** HubSpot has explicit `consent` field types; SpiderForms requires you to add a `boolean` field labelled appropriately + a separate "subscription preferences" question. Don't strip GDPR consent — surface it explicitly.
- **HubSpot's `fieldType` enum is larger than this mapping covers** (~25 types vs the ~12 mapped). Always log the `unsupported` list and surface it to the user.
- **Webhook signature verification** — HubSpot's submit endpoint accepts any POST; consider adding HMAC signing to the SpiderForms webhook payload if you need end-to-end auth.
- **Field-name uniqueness across HubSpot fieldGroups.** HubSpot allows duplicate `name` values across groups; SpiderForms requires unique field IDs per flow. Detect duplicates pre-create.
- **HubSpot UI's "smart fields" / progressive profiling** isn't easily mirrored — those depend on HubSpot's visitor cookie tracking. Skip; rely on SpiderForms' own variable-substitution if needed.

## Verify

```
form_get({ flow_id })
# → confirm field list matches the HubSpot form (minus skipped types)

# Test submit + verify it lands in HubSpot
form_test_submit({ flow_id, answers: {"email": "qa@example.com", ...} })

# Then check HubSpot's contacts dashboard for the test contact
# (or use HubSpot CRM API to query the most recent submission)
```

## Anti-patterns

- **Mirroring without checking the unsupported-types list.** Sweeping `calculation` and `smart_field` away silently breaks compliance + UX flows you didn't realize existed.
- **Skipping the webhook wire-up.** SpiderForms collects submissions in its own response table; HubSpot has no idea. CRM users wonder where the leads went.
- **Mapping HubSpot `single_checkbox` for GDPR consent → SpiderForms `boolean` without explicit labeling.** Compliance teams will reject — surface the consent semantics in the field label + add a separate subscriptions question.
- **Using HubSpot's CDN-hosted CSS classes in the SpiderForms theme.** SpiderForms has its own theme system; don't try to reuse HubSpot's styling unless you've explicitly imported the tokens.
- **One-time mirroring then editing both surfaces.** Pick a source of truth: re-pull HubSpot → SpiderForms periodically, or commit to SpiderForms as source and stop editing HubSpot. Drift = pain.

## See also

- [`../../booking/build-form.md`](../../booking/build-form.md) — the SpiderForms primitive being created in Step 3
- [`../../booking/form-as-page-section.md`](../../booking/form-as-page-section.md) — embed the mirrored form in a SpiderPublish page
- [`../../booking/test-form-submission.md`](../../booking/test-form-submission.md) — verify the webhook fires + lands in HubSpot
- [`../../booking/clone-form-template.md`](../../booking/clone-form-template.md) — if a SpiderForms template covers 80% of the HubSpot form shape, start there
