# Templates — Jinja2, server-rendered, preview-before-send

SpiderMail templates are server-side Jinja2 (sandboxed). Like Postmark's template
API, you create/manage and **render** them entirely over the API. The discipline
that matters: **preview before you send**, and know which `template_type` does what.

## Template types (how the template combines with the body)

| `template_type` | Behaviour |
|---|---|
| `signature` | Appended to the body |
| `header` | Prepended to the body |
| `layout` | Wraps the body via a `{{ body }}` slot (header + footer chrome) |
| `full` | The entire email — `body` is one of its variables |

A `layout` is the common one for branding: your markdown body lands in the
`{{ body }}` slot; the rest is your chrome.

## Steps

1. **List / inspect** — `listTemplates`, then `getTemplate <id>` for the source +
   detected variables.
2. **Create** — `createTemplate` with `name` + `html_source` (+ `template_type`).
   Variables auto-detect from `{{ ... }}` if you don't list them.
3. **Preview** — `previewTemplate <id>` with real `variables` → rendered HTML,
   **without sending**. Always do this before a real send.
4. **Send with it** — `sendEmail` with `template_name=<name>` and
   `template_data={...}`.

## Create + preview (the safe loop)

```bash
# Create a layout with a {{ body }} slot
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/templates" -H "Content-Type: application/json" \
  -d '{
    "name":"acme-layout",
    "template_type":"layout",
    "html_source":"<div style=\"font-family:sans-serif\"><p>{{ body }}</p><hr><p style=\"color:#666\">{{ sender_name }} · {{ title }} · Acme Corp</p></div>",
    "variables":["body","sender_name","title"]
  }'
# → { id: 17, name: "acme-layout", variables: ["body","sender_name","title"], ... }

# Preview with real values BEFORE sending — returns rendered HTML, sends nothing
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/templates/17/preview" -H "Content-Type: application/json" \
  -d '{"variables":{"body":"Hi Bob — worth a quick chat?","sender_name":"Alice","title":"Head of Sales"}}'
# → { rendered_html: "<div …>", ... }
```

## WRONG

```bash
# WRONG: sending with a template you never previewed, with a missing variable
-d '{"payload":{"action":"send","from_email":"alice@acme.com","to":["bob@lead.com"],
      "subject":"Hi","body_text":"…","template_name":"acme-layout",
      "template_data":{"body":"…","sender_name":"Alice"}}}'
# → `title` is missing → it renders EMPTY (Jinja2 doesn't error on a missing var).
#    The recipient sees "Alice ·  · Acme Corp". Preview first to catch this.

# WRONG: an uppercase / spaced template name
-d '{"name":"Acme Layout", ...}'
# → 422: names are [a-z0-9-_] and lowercased. Use "acme-layout".
```

## RIGHT

```bash
# RIGHT: preview catches the empty var, then send with the full data set
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/jobs/spiderMail/submit" -H "Content-Type: application/json" \
  -d '{"payload":{"action":"send","from_email":"alice@acme.com","to":["bob@lead.com"],
       "subject":"Quick question","body_text":"Hi Bob — worth a quick chat?",
       "template_name":"acme-layout",
       "template_data":{"sender_name":"Alice","title":"Head of Sales"}}}'
# Note: for a `layout`, body_text fills the {{ body }} slot — don't also pass body in template_data.
```

## Field notes

- `name` — unique per client, `[a-z0-9-_]`, lowercased server-side.
- `variables` — auto-detected from the source if omitted; list them to document intent.
- `previewTemplate` accepts `variables` (preferred) or the legacy alias `template_data` — both work.
- **Missing variables render empty, they do not error** — preview is your only guard.
- Update uses **PUT** (`updateTemplate`); send only the fields you change.
- A mailbox can carry a `default_template_id` (set via the dashboard / mailbox
  PATCH) so every send from it applies that template with no per-send config.

## Verify

```bash
# Render a template with sample data and eyeball the HTML — sends nothing
curl -s -X POST -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/mail/templates/17/preview" -H "Content-Type: application/json" \
  -d '{"variables":{"body":"test","sender_name":"Alice","title":"Sales"}}'
```
