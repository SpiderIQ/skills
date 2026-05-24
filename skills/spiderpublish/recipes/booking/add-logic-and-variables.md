# recipes/booking/add-logic-and-variables

Add conditional logic + declared variables to a `kind='form'` flow — branch on answers, jump to specific questions, compute values, capture URL params. The "if X, then Y" surface.

## When to use

- A form needs to skip questions based on prior answers (e.g. "If team_size = solo, skip the 'How many seats?' question").
- You want to send respondents to different thank-you screens based on their answers.
- You want to capture URL params (`?utm_source=...`) as hidden fields.
- You want to compute derived values (e.g. `total = qty * price`) and surface them in subsequent questions.

For form authoring fundamentals (theme, fields) → [`build-form.md`](build-form.md). For an end-to-end pipeline (create → publish → embed) → [`build-lead-gen-form.md`](build-lead-gen-form.md).

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **A draft form exists.** Logic and variables can be added on a draft OR before publish. Adding logic to an already-published form re-validates at publish time.
3. **You know your field IDs.** Logic rules reference fields by `id`, not by label. Inventory with `form_get({ flow_id })` first.

## The three constructs

| Construct | What | Tool |
|---|---|---|
| **Logic rule** | `when X then Y` — branch based on answers | `form_add_logic_rule` |
| **Variable** | Declared value (string/number/bool) settable from logic | `form_declare_variable` |
| **Hidden field** | URL-param-capturable value persisted on the lead row | `form_add_hidden_field` |

These compose: a logic rule can read a hidden field, set a variable, and jump to a target step.

## Logic rules — branching

### Shape

```
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "solo" },
    then: { type: "jump_to", target: "step_thankyou" }
  }
})
```

Each rule has a `when` (the condition) and a `then` (the action). Rules evaluate in declaration order — the first matching rule fires.

### The `when` operators

| Op | Meaning | Field types it works on |
|---|---|---|
| `eq` | Equals (case-insensitive for strings) | All |
| `neq` | Not equals | All |
| `gt` / `gte` | Greater than / ≥ | number, opinion_scale, rating, nps |
| `lt` / `lte` | Less than / ≤ | Same |
| `in` | Value in array | select, picture_choice, checkbox |
| `not_in` | Value not in array | Same |
| `contains` | Substring match | text, textarea, email |
| `is_empty` / `is_filled` | Field has/hasn't been answered | All |

Compound conditions via `all` (AND) or `any` (OR):

```
when: {
  all: [
    { field: "team_size", op: "in", value: ["small", "medium"] },
    { field: "company_size", op: "gte", value: 10 }
  ]
}
```

### The `then` actions

| Action | What it does |
|---|---|
| `jump_to: { target: "<step_id>" }` | Skip to a specific step (forward only — no backward jumps) |
| `skip_to_thankyou: { screen_id: "<thx_id>" }` | Jump to a specific thank-you screen (different screens for different paths) |
| `set_variable: { name: "<var>", value: ... }` | Assign a variable that subsequent questions can recall via `{{variable:name}}` |
| `set_hidden: { key: "<key>", value: ... }` | Set a hidden field (alternative to URL-param capture) |
| `end` | Submit immediately, skipping remaining steps |

### Example — multi-path form

```
# Rule 1: enterprise leads → enterprise thank-you + sales handoff
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "set_variable", name: "lead_tier", value: "enterprise" }
  }
})

# Rule 2: also jump enterprise to a specific thank-you screen
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "skip_to_thankyou", screen_id: "thx_enterprise" }
  }
})

# Rule 3: solo leads → self-serve thank-you
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "team_size", op: "eq", value: "solo" },
    then: { type: "skip_to_thankyou", screen_id: "thx_selfserve" }
  }
})
```

The result: respondents picking `large` get the enterprise thank-you with sales contact info; respondents picking `solo` get the self-serve onboarding link.

## Variables — declared, typed, default-valued

Variables are session-scoped — they live for the duration of one form submission. Use them to compute derived values that subsequent questions / thank-you screens can reference.

```
form_declare_variable({
  flow_id: "<flow_id>",
  variable: {
    name: "estimated_total",
    type: "number",
    default: 0
  }
})

# Set it via a logic rule (after the relevant fields are answered)
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "qty", op: "is_filled" },
    then: {
      type: "set_variable",
      name: "estimated_total",
      value: { expression: "{{field:qty}} * {{field:price_per_unit}}" }
    }
  }
})
```

The renderer's recall-token syntax: `{{field:<field_id>}}` for answer values, `{{variable:<name>}}` for declared variables, `{{hidden:<key>}}` for hidden fields.

### Variable types

| Type | Notes |
|---|---|
| `string` | Default `""`. Use for derived text (concatenated names, etc.). |
| `number` | Default `0`. Supports `+`, `-`, `*`, `/` in `expression`. |
| `boolean` | Default `false`. Toggle for conditional rendering. |

## Hidden fields — URL-param capture

Hidden fields are URL-querystring-captured at form load. Only DECLARED keys are sourced; arbitrary query params are stripped (security model).

```
form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "utm_source", label: "UTM source" }
})

form_add_hidden_field({
  flow_id: "<flow_id>",
  hidden_field: { key: "ref", label: "Referral code", default_value: "organic" }
})
```

When the visitor lands at `https://<tenant>/f/<flow_id>?utm_source=instagram&ref=ABC123`, both values persist on the lead row. If `ref` isn't in the URL, `default_value: "organic"` is used.

Hidden fields ALSO show up in `when` conditions, so you can branch on referral source:

```
form_add_logic_rule({
  flow_id: "<flow_id>",
  rule: {
    when: { field: "ref", op: "eq", value: "ABC123" },
    then: { type: "set_variable", name: "discount_code", value: "VIP-15" }
  }
})
```

`when.field` accepts BOTH visible field IDs AND hidden field keys.

## Validate before publish

```
form_validate_logic({ flow_id: "<flow_id>" })
// → { valid: true, errors: [], warnings: [...] }
```

The server-side cross-validation runs 14 rule classes:

| Class | Catches |
|---|---|
| Field-reference | Rule references a `field` that doesn't exist in the flow |
| Step-reference | `jump_to.target` references a step that doesn't exist |
| Screen-reference | `skip_to_thankyou.screen_id` references a thank-you screen that doesn't exist |
| Variable-reference | `set_variable.name` references an undeclared variable |
| Operator-domain | Operator (`gt`, `contains`, etc.) used on incompatible field type |
| Forward-jump-only | `jump_to.target` points backward (loops) |
| Hidden-key-uniqueness | Duplicate `hidden_field.key` |
| Variable-default-type | Variable `default` type doesn't match declared `type` |

Run after EVERY logic mutation. The local `form_validate({ flow })` runs a subset (structural checks); `form_validate_logic` is the full cross-validation.

## Remove logic

```
form_remove_logic({
  flow_id: "<flow_id>",
  rule_id: "rule_..."           # from form_get's flow.logic[].id
})
```

Rules are indexed by `id`. Get them via `form_get` and look at `flow.logic[]`. Removal is immediate; no dry_run gate.

## End-to-end example — lead-gen with branching thank-you screens

```
# 1. Declare variables for the tier classification
form_declare_variable({ flow_id, variable: { name: "lead_tier", type: "string", default: "unknown" } })

# 2. Add hidden fields for attribution
form_add_hidden_field({ flow_id, hidden_field: { key: "utm_source", label: "UTM source" } })
form_add_hidden_field({ flow_id, hidden_field: { key: "campaign",   label: "Campaign" } })

# 3. Add branching logic
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "eq", value: "solo" },
    then: { type: "set_variable", name: "lead_tier", value: "solo" }
  }
})
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "in", value: ["small", "medium"] },
    then: { type: "set_variable", name: "lead_tier", value: "smb" }
  }
})
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "set_variable", name: "lead_tier", value: "enterprise" }
  }
})

# 4. Branch to different thank-you screens based on tier
form_add_logic_rule({
  flow_id, rule: {
    when: { field: "team_size", op: "eq", value: "large" },
    then: { type: "skip_to_thankyou", screen_id: "thx_enterprise" }
  }
})

# 5. Validate
form_validate_logic({ flow_id })
# → { valid: true, errors: [], warnings: [] }

# 6. Publish
form_publish({ flow_id })   # safe-default dry_run=true
form_publish({ flow_id, confirm_token })
```

The lead row now carries: `team_size`, `lead_tier`, `utm_source`, `campaign`. Different visitors see different thank-you screens. Downstream (CRM, email) can branch on `lead_tier` for routing.

## Recall tokens — referencing values in field labels + thank-you screens

Once you've declared variables / hidden fields, reference them in subsequent field labels OR thank-you screen text:

```
# Field label that uses a previous answer
{ id: "confirm_name", type: "text", label: "Just to confirm — your name is {{field:name}}, correct?" }

# Thank-you screen that uses a variable
{
  id: "thx_enterprise",
  title: "Welcome, {{field:name}} — enterprise tier",
  description: "We'll be in touch via {{field:email}} within 24h. Tier: {{variable:lead_tier}}.",
  button_mode: "redirect",
  redirect_url: "https://calendly.com/sales/enterprise"
}
```

Tokens are interpolated by the renderer at submit time / render time.

## Anti-patterns

1. **Backward jumps (`jump_to.target` pointing to a step before the current one).** Validator rejects — would cause infinite loops. Use `set_variable` + a forward jump to a different branch.
2. **Logic on a hidden_field key you never declared.** `when.field: "utm_source"` without `form_add_hidden_field({key: "utm_source"})` → validator says `field not found`. Declare first.
3. **`set_variable` with an undeclared variable name.** Validator says `variable not declared`. Use `form_declare_variable` first.
4. **Operator-domain mismatch (`gt` on a `select` field, `contains` on a `number`).** Validator catches; pick the right operator for the field type.
5. **Adding 20+ logic rules.** Hard to reason about; debugging which rule fires becomes a maintenance burden. Refactor: use fewer rules that set variables (`lead_tier`), then a small number of variable-based jumps.
6. **Forgetting `form_validate_logic` after every mutation.** Each rule add is a chance to introduce a cross-reference bug. Re-run validation as a free safety net.

## See also

- [`build-form.md`](build-form.md) — theme + fields (foundation)
- [`build-lead-gen-form.md`](build-lead-gen-form.md) — end-to-end pipeline (logic plugs in at step 4)
- [`clone-form-template.md`](clone-form-template.md) — start from a template that may already have logic
- [`embed-form.md`](embed-form.md) — embed the logic-enabled form
- [`../reference/booking-model.md`](../reference/booking-model.md) — `kind='form'` flow shape (`flow.logic[]`, `flow.variables{}`)
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — `form_*` tool catalog
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
