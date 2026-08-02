# The `/api/v1/spideriq/content` prefix is dead — use `/api/v1` direct

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

An agent test reported a pile of failures that all looked like the API was
broken:

- "Schema says `/api/v1/spideriq/content/*`, actually works `/api/v1/content/*`"
- "`/content/categories` → 404 Not Found (route not registered)"
- "`/content/settings` → 404, `/content/domains` → 404"
- "POST → 403 'Not authenticated' even with a valid PAT"

All of these traced back to **one** wrong thing: the base path.

## Why it happens

`/api/v1/spideriq/...` is the **OPVS-proxy** path — the old opvsHUB gateway
forwarded a *subset* of routes under that prefix. The marketplace skill does NOT
go through that proxy: its `provider_config.base_url_env` points
`SPIDERIQ_API_URL` straight at `https://spideriq.ai`. So `/api/v1/spideriq/...`
hits the real API, which has **no `/spideriq/` segment** → 404 for everything.
The "missing endpoints" and "auth disabled" were all this 404 in disguise.

## The real map (verified 2026-06-11)

```
base_url: /api/v1          (https://spideriq.ai/api/v1)

PUBLIC reads (no auth, published only, needs X-Content-Domain):
  GET /content/posts        GET /content/settings      → 200
  GET /content/authors      GET /content/navigation/…  → 200
  GET /content/categories   → 200  (returns {categories:[],total:0} when empty)

AUTHORING (Bearer PAT, sees drafts, tenant from the token):
  GET/POST/PATCH/DELETE /dashboard/content/{posts,pages,docs,authors,tags,
                          categories,navigation,settings,domains,media,deploy,…}
  GET /dashboard/content/posts (Bearer)  → 200   ← auth works fine

DEAD:
  /api/v1/spideriq/content/...  → 404 (the old proxy prefix)
  POST /api/v1/content/posts    → 405 (public path is READ-ONLY; writes are on /dashboard/content)
```

## What "good" looks like

- Reads that need drafts, and ALL writes → `/api/v1/dashboard/content/...` with
  `Authorization: Bearer <client_id:api_key:api_secret>`.
- Public reader features (search, featured, marketplace) → `/api/v1/content/...`.
- Never `/api/v1/spideriq/...`. Never POST to `/api/v1/content/...`.

The skill's `client/schema.yaml` now encodes exactly this, so a generated client
gets it right without the agent reasoning about paths.

## See also

- `references/gaps.md` — the full verified verdict on the 2026-06-10 report.
- `learnings/2026-06-11-post-field-names-silently-dropped/` — the *other* half of
  that report (real, and fixed).
