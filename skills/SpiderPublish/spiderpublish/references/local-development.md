# Local development — `spideriq dev`, a pulled site folder, and push

> **For a coding tool editing a site's templates and components as files** (Claude Code, Codex,
> Antigravity). Content — pages, posts, docs, forms, booking, settings — stays API work: the rest of
> this skill. This page is the file workflow around it.

## When to use

| You want to… | Use |
|---|---|
| change a site's Liquid templates, sections, snippets, layout, or its own components, and SEE the result before it ships | **this page** — `spideriq dev --site <domain>` |
| create or edit a page, post, doc, form, booking, setting, navigation | the API (`references/content.md`, `forms-booking.md`, …) |
| change a global (`is_global`) component | nobody does: copy it to a new slug |

## Steps

### 1. Pull the site

```bash
export SPIDERIQ_CONTENT_READ_KEY=ck_...     # the site's own `site` read key
spideriq dev --site acme.com                # first run pulls into ./acme.com, then serves it
spideriq dev --site acme.com --pull         # pull again (refuses to drop edits you have not pushed)
```

The CLI must be signed in to the workspace that owns the site (`-w <slot>` picks the slot). The pull
writes:

```
acme.com/
  AGENTS.md                 how to work in this folder (short: read every turn)
  CLAUDE.md                 one line: @AGENTS.md
  .spideriq/docs/           six pages generated on this pull (also at http://localhost:4321/__docs)
  site.json                 domain, project, _config.json, pulled baseline (sha256 per file)
  theme/<kv-key>            the EFFECTIVE template set: the theme, with the site's own rows over it
  components/<slug>/        the site's own components as files (never global ones)
```

Codex and Antigravity read `AGENTS.md`; Claude Code reads `CLAUDE.md`, which imports it. An
`AGENTS.md` or `CLAUDE.md` you wrote yourself is kept: the pull rewrites only the ones it wrote.

### 2. Read the generated docs before you edit

| `.spideriq/docs/` | What it answers |
|---|---|
| `templates.md` | which file a page and a URL render, KV keys, layouts and blocks |
| `merge-tags.md` | every `{{ tag }}`, from the merge-tags spec |
| `components.md` | the folder format, the four tiers, Shadow DOM, CDN libraries, layouts |
| `warnings.md` | each rule `/__warnings` can report, and its fix |
| `push-deploy.md` | what goes live when, every push refusal and what to do |
| `this-site.md` | its theme, its own template rows and components, the global slugs it may use |

They are generated from the sources of truth (the Worker's code, the merge-tags spec, this skill), so
trust them over memory. They are rewritten on every pull; do not edit them.

### 3. The loop

1. Edit under `theme/` or `components/<slug>/`.
2. Look at http://localhost:4321 — the production Worker renders it, with hot reload.
   `/__component/<slug>` shows one component alone at phone and desktop width.
3. `curl -s localhost:4321/__warnings` → `{"warnings":[]}` for every page you touched.
4. `spideriq dev push --site acme.com --dry-run` → the plan, nothing written. Show it to the owner.

### 4. Push

```bash
spideriq dev push --site acme.com           # the same dry runs, then a yes, then each write with its token
```

Only changed files are sent, only to the site the folder came from, and every write is
`dry_run` → `confirm_token`. A push never deletes.

| You pushed | Live when |
|---|---|
| a component | on the next request, within ~60 s (edge cache) — no deploy |
| a template under `theme/` | on the site's next deploy (`spideriq content deploy`, preview → confirm) |

## Gotchas

- **A page set to `default` renders `templates/page.liquid`, not `index.liquid`** — the home page
  included. `templates.md` lists which file each page template and URL renders, for this site.
- **The content is live and read-only.** The dev server's proxy forwards GET only and answers
  `405 DEV_SERVER_READ_ONLY` to anything else. A page that looks empty is a content question, not a
  template bug: check the page in the dashboard or through the API.
- **No read key, no content.** Without the site's `site` read key the preview reads keyless;
  and a folder served without `--site` or `--domain` reads nothing on plain `localhost`
  (`404 No content configured for domain`).
- **Multi-project workspaces.** The pull reads the site's project's templates; a deploy may merge
  across projects. `site.json` → `notes` says so. Compare one page with the live site.
- **A Tier 4 (React/Vue/Svelte) component is built on the server**, never locally: it renders as
  `component_build_failed` here until the server has built it.
- **A refused push sent nothing.** Every guard runs before the first dry run. `push-deploy.md` lists
  each refusal with what to do.

## Verify

```bash
ls acme.com/AGENTS.md acme.com/CLAUDE.md acme.com/.spideriq/docs/   # six .md pages
curl -s localhost:4321/__docs                                       # lists the same six
curl -s localhost:4321/__warnings                                   # {"warnings":[]}
spideriq dev push --site acme.com --dry-run                         # the plan you expect, nothing else
```

## See also

- `references/templates-deploy.md` — themes, deploy, preview, rollback (API)
- `references/components.md` — authoring components through the API
- `references/content.md` — pages, sections, navigation, settings (API)
