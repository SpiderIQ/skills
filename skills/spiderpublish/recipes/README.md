# Recipes

Step-by-step procedures the [SKILL.md](../SKILL.md) router points at. Each
recipe is a single Markdown file with this exact shape:

```markdown
# Recipe: <task name>

**Goal:** <one sentence>
**Use when:** <trigger conditions>
**Prerequisites:** <what must exist first; which reference docs to read>

## Steps
1. `<tool / CLI call>` — <purpose>
2. ...
N. Deploy — follow `../../reference/deploy-protocol.md`

## Gotchas
| Gotcha | What happens | Fix |
|---|---|---|

## Verify
- <how to confirm success>

## See also
- <related recipe(s)>
```

## Recipe inventory (v0.1.0)

See [SKILL.md](../SKILL.md) decision tree for the canonical list. Each row
points at a file in this directory tree:

```
recipes/
├── content/      → pages, posts, docs, navigation, domains, themes,
│                   section overrides, scroll heroes
├── components/   → create, update + propagate, rollback, find-by-slug
├── booking/      → forms, booking flows, calendar OAuth, embed snippets,
│                   template cloning
├── directory/    → IDAP listing imports
└── clone/        → SpiderClone (public URL → Liquid template)
```

## Authoring rules

1. **Ground tool calls.** Every `spideriq` / MCP / `curl` invocation in a recipe
   must match the live signature. Read `GET /api/v1/content/help` and
   `packages/mcp-tools/src/publish/*.ts` (in the internal monorepo) before
   writing. Mark unknowns `<!-- VERIFY: ... -->`.
2. **Never re-explain deploy.** The two-phase pipeline + five-lock defense
   lives once in [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md).
   Every recipe's final step points there.
3. **Encode sequencing, not just tools.** A recipe that lists three tool
   names with no order, preconditions, or gotchas has failed its job.
4. **Honest hard-gates only.** Don't claim something is mandatory if it's
   opt-in — the original `?dry_run=true` "mandatory" framing caused the F-8
   incident (Wave-3 close, 2026-05-20). Match the actual API behaviour.
