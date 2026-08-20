# Branches (SubSequences) — authoring, not routing

A branch says: *when X happens to a lead, stop their sequence or jump them to a
different step.* You author them with `sendAddBranch` / `sendUpdateBranch` /
`sendDeleteBranch`, and read them back on `sendGetCampaign` → `branches`.

## The one rule that matters

> **Nothing executes a branch yet.** Authoring one changes what nothing does
> today — the execution half ships in a later slice. Report a campaign as
> *"branches authored"*, never as *"now branching"*.

This is not a caveat to bury. A human who believes a reply now stops the
sequence will stop watching their inbox for the thing that is still going to
happen.

## The four triggers

| trigger | fires on | fields |
|---|---|---|
| `classification` | the AI verdict on an inbound reply | `verdict` — `eq` / `in` over `human`, `outreach_reply`, `auto_reply`, `bounce` |
| `reply_text` | a literal string in the reply body | `text` — `contains` / `not_contains` / `starts_with` / `equals` |
| `unresponsive` | no reply after N days | `days` — `gte`, 1–365 |
| `bounced` | a bounce of a given severity | `severity` — `eq` / `in` over `permanent`, `temporary` |

Two names are **not** on that list, for **different** reasons — and the
difference is the whole point:

- **`open` is excluded permanently.** Apple Mail Privacy Protection fires open
  pixels with no human involved. An open is noise, which is also why
  `stop_condition` has no `'open'`. This will not change.
- **`click` is DEFERRED, not forbidden.** ⚠️ **Campaign-level stop-on-click
  already works** — set the campaign's `stop_condition: 'click'`. So when a
  human says *"stop the sequence if they click"*, do that, rather than
  reporting it impossible. Only *branching* on a click is unavailable.

`warmup` is deliberately not a branchable verdict: it exists in the database so
warm-up traffic can be labelled, and it is kept outside the model's vocabulary
so bot noise cannot inflate engagement.

## `match` is a TREE, never a string

```json
{"op": "eq", "field": "verdict", "value": "human"}
```

Compose with `{"op":"and","nodes":[…]}`, `{"op":"or","nodes":[…]}`,
`{"op":"not","node":{…}}`.

An unknown operator, an unknown field, or an extra key is **rejected with 422**,
not ignored — so a match that comes back accepted is a match that means what it
says.

## WRONG / RIGHT

### Sending a predicate string

```
WRONG   match: "verdict == 'human'"
WRONG   match: {"op": "regex", "field": "text", "value": "not.*interested"}
RIGHT   match: {"op": "eq", "field": "verdict", "value": "human"}
RIGHT   match: {"op": "contains", "field": "text", "value": "not interested"}
```

There is no predicate anywhere in this grammar that takes a pattern, and there
will not be one — a user-authored regex is a denial-of-service against whatever
evaluates it. If literal matching is not enough, that is a request for a new
named predicate, not for a pattern.

### Sending `{}` to mean "always"

```
WRONG   match: {}                 → 422
RIGHT   match: {"op": "always"}
```

`{}` is the column **default**, and it means **matches nothing** — deliberately,
so a half-written row sits inert instead of firing on everything. That makes it
a safety floor, never something you choose. A branch that matches nothing has no
symptom at all: it is configured, it is listed, and it never does anything.

### Jumping to a step that isn't there

```
WRONG   action: "jump_to_step", action_arg: {"step_index": 4}   # campaign has 3 steps → 422
RIGHT   sendGetCampaign first; aim at a step_index the campaign actually has
```

And the mirror of it: **a step a branch jumps to cannot be deleted** while that
branch exists (409). Re-aim or remove the branch first. That includes *disabled*
branches — `enabled: false` means "off for now", so silently orphaning one
converts a reversible state into something broken the day it is switched back
on.

### Deleting when you meant to disable

```
WRONG   sendDeleteBranch — because the user said "turn that off for now"
RIGHT   sendUpdateBranch {enabled: false}
```

A disabled branch keeps the rule *and the reasoning behind it* visible. A
deleted one loses both, and the next person re-derives it.

### Patching half a pair

```
WRONG   sendUpdateBranch {trigger: "bounced"}                    → 422
RIGHT   sendUpdateBranch {trigger: "bounced",
                          match: {"op":"eq","field":"severity","value":"permanent"}}
```

`trigger`+`match` move together, and so do `action`+`action_arg`. A match names
fields that belong to **one** trigger's grammar, so changing either alone would
store a match its trigger cannot read — accepted by every layer, and dead.
Repeat the unchanged half.

## Gotchas

- **Branches are CAMPAIGN-scoped, not per-step.** There is no "branch on step
  2". A branch watches the whole sequence; `jump_to_step` names its *target*.
- **Authoring works while the campaign is ACTIVE.** Unlike editing a step, a
  branch re-aims nobody's current position, so it does not need a pause.
  Anything `stopped` or `completed` refuses every write.
- **`sendGetCampaign` lists disabled branches too.** That is on purpose — a
  branch that is deliberately off is something a human has to be able to see.
- **There is a per-campaign ceiling.** Well past any real sequence; if you hit
  it, you are describing a state machine rather than a follow-up sequence, and
  the answer is usually fewer, broader rules.

## Verify

```
sendGetCampaign {campaign_id}
  → branches[]: each has the id, trigger, match and action you intended
  → every jump_to_step action_arg.step_index appears in steps[]
  → any branch you meant to leave off shows enabled: false
```

Then say: *"N branches authored on <campaign>. ⚠️ Nothing evaluates them yet —
they will take effect when branch execution ships."*

## See also

- `references/run-a-sequence.md` — the sequence itself: shell → touches → copy →
  source → preview → hand over.
- `references/two-clocks.md` — why a campaign can be active and still not send
  today.
