# SpiderIQ Skills

Agent skills for every [SpiderIQ](https://spideriq.ai) product. Install once,
your agent learns how to author, publish, and deploy on SpiderPublish (and,
as they ship, SpiderMail and SpiderGate).

## Install

```bash
npx skills add SpiderIQ/skills
```

Works for Claude Code, Cursor, Codex, and Antigravity from one command.
Skills install into your **agent runtime** — they never touch your project's
`CLAUDE.md`, `AGENTS.md`, or `.cursorrules`.

## What's inside

| Skill | What it teaches | Status |
|---|---|---|
| `spiderflows` | Run SpiderIQ flows (server-side pipelines). Today: the lead / local-business chain — Google Maps → site crawl → email verify → optional VayaPin pin (sold as both leadSearch and localSeo). Single run or multi-location campaign, full lifecycle, results via IDAP. More flows added here as recipes. | ✅ v0.1.0 |
| `spiderpublish` | Pages, posts, docs, components, navigation, themes, forms, booking flows, custom domains, two-phase deploy | ✅ v0.1.0 |
| `spidermail` | Mailboxes, threads, send, templates, automation | 🔜 |
| `spidergate` | LLM completions, routing, traces, cost tracking | 🔜 |

Each skill is a folder under [`skills/`](./skills) with its own `SKILL.md`,
recipe library, and reference docs. Skills are discovered independently —
your agent loads the one whose frontmatter matches the task.

## Designer kits (a different door)

Designers building full-time SpiderPublish templates use the per-product
designer kits, not this repo. Greenfield bootstrap:

```bash
npx degit SpiderIQ/SpiderPublish/designer-kit my-templates-project
```

## How skills work

1. You install the suite once via `npx skills add SpiderIQ/skills`.
2. Each skill's frontmatter (`description` block) is always-loaded into your
   agent's context. Costs ~50–100 tokens per skill.
3. When you ask the agent to do something, the skill whose description matches
   loads its `SKILL.md` body — a lean router pointing at a specific recipe.
4. The agent reads the matching recipe, executes its steps, and verifies the
   result before returning.

Three-tier progressive disclosure: frontmatter (always) → SKILL.md body (on
match) → recipe file (on routing). Per-recipe content never burns context
unless the agent's task actually needs it.

## Contributing

Recipes get tighter as we run into more failure modes. If your agent failed
on a SpiderIQ task, the right fix is usually a better recipe or a sharper
anti-pattern in the relevant `SKILL.md`. Open an issue or PR.

## License

MIT. See [LICENSE](./LICENSE).
