# recipes/deploy/deploy-preview-only

Push the current STORE state to a **temporary preview URL** (`preview-<token>.sites.spideriq.ai`) without touching production. Use it to eyeball a change before consuming the production confirm_token.

## When to use

- About to deploy a high-risk change (theme swap, mass restore, new template) — preview first.
- Sharing a "before you confirm" URL with the client for sign-off.
- CI pipeline: build PR → preview deploy → run smoke tests → only then promote to production.
- Pattern: "I want to see what visitors WILL see, without them seeing it yet."

## The one call

```
content_deploy_site_preview()
# → {
#     preview_url:    "https://preview-cft01HXX.sites.spideriq.ai",
#     confirm_token:  "cft_01HXXXXXXXXXXXXXXXXX",
#     expires_at:     "2026-05-24T14:35:00Z",        # 5 minutes from now
#     preview: {
#       pages: 12,
#       components: 24,
#       settings_diff: { changed_keys: [...] },
#       templates_diff: { changed_files: [...] }
#     },
#     snapshot_hash:  "sha256:..."
#   }
```

Phase 11+12 Stage 2 — issues a preview URL + confirm_token without deploying. The preview URL points at a one-off Worker that serves the snapshot you'd land in production.

## Two ways to consume the preview

### Option A — Promote to production

If the preview looks right, consume the token:

```
content_deploy_site_production({
  confirm_token: "cft_01HXXXXXXXXXXXXXXXXX"
})
# → { status: "live", version_id: 49, deployed_at: "..." }
```

That's the canonical Phase 11+12 happy path — preview → confirm → live.

### Option B — Discard

Let the token expire (5 minutes — the deploy pipeline TTL is short). The preview URL stays accessible for the duration of the cache (~30 min), but no production change happens. Useful when:

- The preview revealed a bug; fix it in STORE, then `content_deploy_site_preview` again for a fresh token.
- You're sharing the preview link with the client and waiting for sign-off; if sign-off comes after 5 min, re-run preview for a fresh token before promoting.

## Steps — typical "share for sign-off" flow

```
1. (make whatever STORE edits — pages, components, settings)
2. content_deploy_readiness()                       — confirm no blocking issues
3. content_deploy_site_preview()                     — get preview_url + confirm_token
4. (send preview_url to the client / stakeholder)
5. (wait for sign-off)
6. content_deploy_site_preview()                     — fresh token if the original expired
7. content_deploy_site_production({ confirm_token })  — go live
8. content_visual_check({ page_url: "<production-url>" })
                                                     — verify the production deploy
```

## Steps — typical CI flow

```bash
# After PR merge → trigger CI build → for each tenant:
PREVIEW=$(spideriq content deploy preview --json | jq -r '.preview_url')
TOKEN=$(spideriq content deploy preview --json | jq -r '.confirm_token')

# Run smoke tests against the preview
spideriq content visual-check --page-url "$PREVIEW/landing" --viewport desktop || exit 1
spideriq content visual-check --page-url "$PREVIEW/landing" --viewport mobile  || exit 1

# Promote
spideriq content deploy production --confirm-token "$TOKEN"
```

(`spideriq content deploy preview --json` is the CLI wrapper for `content_deploy_site_preview`.)

## What lands in the preview

Everything in STORE that WOULD land in production:

- Latest published page versions (drafts NOT included unless previously published)
- Latest published component versions
- Current theme tokens + template Liquid files
- Current `content_settings` (SEO defaults, brand colors, analytics tags)
- Current `content_domains` config (but the preview URL is `preview-<token>.sites.spideriq.ai`, NOT the primary domain)

What does NOT differ between preview and production:

- DB rows (both read from the same `content_pages` / `content_components` tables)
- API endpoints (forms POST to the same `/api/v1/booking/<id>/submit`)
- Tenant data (form responses, IDAP records — same tables)

This means a preview deploy showing a form: that form is the real form. Test submissions land in the real responses table. Use [`../booking/test-form-submission.md`](../booking/test-form-submission.md)'s `?test=true` discipline.

## Gotchas

- **`expires_at` is 5 minutes** — deploy pipeline TTL is the strictest of the gate flavours. If your sign-off cycle is longer, expect to re-run preview for a fresh token.
- **Preview URL is publicly accessible** — anyone with the URL can hit it. Don't share preview URLs that include sensitive draft copy via email/Slack channels with broad membership.
- **CF cache holds the preview** for ~30 min after first hit. If you re-deploy preview with a different snapshot, the URL changes (new token), so cache doesn't conflict.
- **`content_visual_check` against the preview URL works** — same Playwright sidecar. Use it pre-promote to catch silent-200 failures.
- **`content_deploy_readiness` should still run** — preview deploys can succeed against a tenant with blocking-readiness issues (missing primary domain, etc.); production deploys reject. Don't be surprised when preview works and production rejects.
- **Forms in preview submit to the real flow** — test submissions land in the real responses table. Use a sandbox tenant for high-volume preview testing.
- **Multiple back-to-back previews** = multiple unused tokens. They expire after 5 min; no cleanup needed, but don't be alarmed.

## Verify

```
# After preview deploy
curl -sI "<preview_url>"
# HTTP/2 200
# server: cloudflare

# After promote
content_deploy_status()
# → latest.version_id should be the new production version
#   latest.status should be "live"

content_visual_check({
  page_url: "https://<tenant-domain>/<key-page>",
  viewport: "desktop"
})
# → confirm production now shows what preview showed
```

## Anti-patterns

- **Skipping preview on high-risk deploys** ("I'm sure"). Theme swaps, mass restores, template edits — always preview. The 5 minutes you save by skipping is gone the moment you have to roll back ([`rollback-deploy.md`](rollback-deploy.md)).
- **Holding a preview token for >5 minutes** and being surprised by 410. The TTL is short by design — fresh-token re-runs are cheap.
- **Sharing preview URLs in public channels** with sensitive draft content. The URL is unauthenticated.
- **Treating preview as "doesn't count."** Form submissions on the preview URL land in REAL responses. IDAP fills, analytics events — all real.
- **Running `content_deploy_site_production` with no prior preview** for a change that touches multiple pages. The legacy `content_deploy_site({ dry_run: true })` also returns a confirm_token, but the preview URL only comes from `content_deploy_site_preview`. Use the split tool when you actually want to look at the preview.
- **Promoting without `content_visual_check` against the preview URL first.** That's the whole point of the preview.

## Verify the recipe → tool

```bash
./scripts/find-tool-for-intent.sh "preview a deploy without going live"
# Top-1 should be: recipes/deploy/deploy-preview-only.md
```

## See also

- [`rollback-deploy.md`](rollback-deploy.md) — the recovery path when preview didn't catch it
- [`../audit/deploy-readiness.md`](../audit/deploy-readiness.md) — pre-deploy checklist; run BEFORE preview
- [`../audit/visual-check-a-page.md`](../audit/visual-check-a-page.md) — verify the preview URL renders correctly
- [`../content/custom-domain.md`](../content/custom-domain.md) — production URL setup (preview URL is always `*.sites.spideriq.ai`, never the custom domain)
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — full gate semantics + ConfirmTokenError map
