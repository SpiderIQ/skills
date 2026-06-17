# Authoring is not live — publish ≠ deploy

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

You `createPost`, you `publishPost`, you tell the user "it's published!" — and
they refresh their site and it's not there. You didn't do anything wrong with the
post. You skipped the step that actually changes the live site: **deploy**.

## The three states

SpiderPublish separates *authoring* from *the live site* on purpose:

```
1. AUTHOR     createPost / createPage      → a DRAFT row in STORE (Postgres)
2. PUBLISH    publishPost / publishPage    → row flips to "published"
                                              (visible to the API, NOT the site)
3. DEPLOY     deploySite / deployProduction → renders + pushes to the CF edge
                                              (NOW the live site changes, ~2-5s)
```

Steps 2 and 3 are **different**. Publishing makes content eligible to appear;
deploying is what regenerates the edge. You usually need both. A create + publish
with no deploy means the new content is sitting in STORE, correct and published,
but invisible to visitors.

## The deploy is itself two-phase on production

`deployPreview` → returns a `preview_url` + `confirm_token` (`cft_…`) →
`deployProduction(confirm_token)` actually ships it. Same `dry_run` →
`confirm_token` shape guards `deletePage`, `applyTheme`, `updateSettings`. On a
production tenant, preview first. Envelopes: 410 expired · 409 consumed ·
403 mismatch.

## What "good" looks like

```
createAuthor / createCategory / createTag   (set up taxonomy)
createPost  (draft, correct field names)
publishPost (draft → published)
deployPreview → deployProduction  (or deploySite one-shot)
deployStatus  (confirm it shipped)
→ only NOW report it live
```

## The rule

Never report a content change as "live" until a **deploy** has succeeded. Publish
is necessary but not sufficient.

## See also

- `references/deploy-protocol.md` — the full two-phase pipeline + five-lock defense.
- `references/templates-deploy.md` — deploy recipes (preview-only, rollback).
