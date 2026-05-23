# Reference

Cross-cutting context the recipes cite. Lives here so each fact has one home —
no recipe re-explains deploy, no recipe re-lists tools.

## Files (planned for v0.1.0)

| File | What it covers | Why it's separate |
|---|---|---|
| `deploy-protocol.md` | Two-phase `dry_run`/`confirm_token` gate + the five-lock tenant defense + `deploy-readiness` + rollback. **Opt-in, not mandatory** — the F-8 lesson. | Every recipe's last step points here — don't re-explain |
| `block-types.md` | `ContentBlock` shape + the rule that custom CSS goes in the `css` field, not `<style>` inside `html_template` + how block validators reject `data.layout` / `data.data_binding` at the wrong nesting | Hot trap surface; covered by Rule 64 in internal LEARNINGS |
| `tool-surface.md` | CLI vs MCP map, which MCP package to install (atomic vs kitchen sink), discovery endpoints (`/content/help`, `/content/help/block-fields`, `/dashboard/idap/merge-tags`), "prefer one-shot tools" rule | Tool inventory drifts faster than SKILL.md should — keep here |
| `booking-model.md` | `booking_flows` shape (`kind`, `flow.json`, `schema.json`), cal.com as slot-resolver, calendar-OAuth-by-invite mechanics, `kind='form'` vs `kind='booking'` URL semantics (both `/f/<id>`) | Heaviest single subsystem; warrants its own file |

## Authoring rules

Same as recipes:

1. Ground every tool signature against the live code or `GET /api/v1/content/help`.
2. Match actual API behavior — don't claim mandatory when it's opt-in.
3. State the *why*, not just the *what* — agents make better edge-case decisions
   when they understand the reason for a rule.
