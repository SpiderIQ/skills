# Publish a changelog — version-stamped release notes

> **REQUIRES — read before you plan.**
> **Package:** works in **every** universe (kitchen sink · mcp-publish default · mac-128).
> **Tools:** `createChangelog` `publishChangelog` `updateChangelog` `listChangelog`
> **Live on PUBLISH — no deploy needed.** Content is fetched from STORE at request time; allow ~60s for the edge cache (`s-maxage=60`). **Do not run a deploy to make content appear, and do not tell the user a deploy is pending.** Deploy is only for templates / theme / the config overlay.
> **Not sure which universe you are in?** SKILL.md → *Step 0*.


The changelog is the **fourth first-class content type**, alongside pages, posts
and docs. It is a flat, date-ordered feed of version-stamped entries rendered at
`/changelog` with RSS + Atom feeds, and it is the right model whenever the thing
being announced has a **version number**.

Pick the right type before you write anything:

| Use | When |
|---|---|
| **changelog** | "What shipped in v2.10.0" — version-stamped, dated, short, one entry per release. |
| **post** (`references/content.md`) | Ongoing editorial — a launch story, a tutorial, an opinion piece. Has an author byline, tags, categories, a cover image. |
| **press release** (`references/press-newsroom.md`) | An announcement aimed at journalists — dateline, media kit, contact roster, embargo. |

Everything below is **project-scoped**. Bind a project first (`spideriq use <id>`,
a `-w/--workspace`, or an `X-Project-Id` header).

---

## The model

| Field | Notes |
|---|---|
| `version` | The label, **unique per brand**. A duplicate returns **409**. Free-form text — `v2.10.0`, `0.1.0` and `propagate-v0.1.0` are all real values in production. |
| `title` | The release headline. |
| `body` | Tiptap JSON, **or** `{"markdown": "..."}` / `{"html": "..."}` — both are normalised to Tiptap server-side. |
| `published_at` | The release date. **This is what the public page orders by** — see the ordering section below. |
| `status` | `draft` → `published` → `archived`. `deleteChangelog` is a soft archive: the entry drops off `/changelog` and the feeds, it is not destroyed. |

An entry has **no** author, tags, categories, cover image or SEO fields. If you
need any of those, you wanted a post.

---

## The 3-call path

```
1. createChangelog(version="v2.10.0",
                   title="Component rollback",
                   body={"markdown": "Restore an earlier component version…"})
   → lands as a DRAFT, id returned

2. publishChangelog(changelog_id)
   → live on /changelog + the RSS/Atom feeds
   → fires the changelog.published notification to subscribers (FIRST publish only)

3. deploySite()   # ONLY if you also changed templates or settings
```

Step 3 is usually unnecessary. Changelog entries are **fetched live** by the
renderer at request time, so a publish is visible immediately — no deploy. You
deploy when you changed the *template*, not when you added an entry.

### Verify (don't trust the 200)

```
listChangelog(status="published", include_body=false)   # cheap index — is it there?
```
Then fetch the public page and confirm the entry renders in the position you
expect. `include_body=false` matters: 25 entries WITH bodies is ~128k characters
and will blow a tool-output ceiling.

---

## Dates — set them explicitly when backfilling

`published_at` defaults to the moment you publish. That is right for a release
you are shipping today and **wrong for every entry you backfill**, because the
public timeline is ordered by date: import ten historical releases in one
sitting and they land in import order, not release order.

Three places accept an explicit date. All take ISO-8601; a naive value is read
as UTC; a malformed one is a **422**, never a 500.

```
# A. At create — pre-stamp the date. Does NOT publish; the entry stays a draft.
createChangelog(version="v2.1.0", title="…", body=…,
                published_at="2026-06-15T14:00:00Z")

# B. At publish — stamp a specific date instead of now. WINS over any date
#    already on the entry, so this is also the correction path.
publishChangelog(changelog_id, published_at="2026-06-15T14:00:00Z")

# C. After the fact — re-date an entry that already went out wrong.
updateChangelog(changelog_id, published_at="2026-06-15T14:00:00Z")
```

**Backfilling a history — do it in release order, oldest first**, giving each
entry its real date at create time:

```
for entry in history_oldest_first:
    id = createChangelog(version=…, title=…, body=…, published_at=entry.date)
    publishChangelog(id)
```

Posts and press releases take the same `published_at` argument on create,
update and publish. Press has one extra caveat: publishing **notifies the
journalist list on the first transition, backdated or not** — import a press
archive by creating the releases with `published_at` set, not by publishing each
one (`references/press-newsroom.md`).

---

## Ordering — the trap that has already cost a live page

**The list is ordered by DATE, not by version string.** This matters more than
it sounds, because the obvious template-side fix is wrong:

```liquid
{% comment %} ❌ WRONG — Liquid's built-in `sort` is a TEXT sort {% endcomment %}
{% assign sorted = changelog_entries | sort: "version" | reverse %}
```

As text, `"v2.10.0" < "v2.2.0" < "v2.9.0"`. So the tenth release renders between
the first and the second, and every release from v10 onward scatters. This ran
live on a production tenant in August 2026: the API returned correct order the
whole time and the template re-sorted it into nonsense.

There are two right answers, in order of preference:

**1. Give the entries correct dates and don't sort at all.** The API already
returns newest-first by `published_at`. Iterate `changelog_entries` as they
arrive. This is what both bundled themes do.

```liquid
{% for entry in changelog_entries %} … {% endfor %}
```

**2. If the dates genuinely can't reflect release order, ask the API for
version order** — it compares each component as an integer, so v2.10.0 outranks
v2.9.0:

```
listChangelog(sort="version")
```

For the rendered page, set `changelog_sort: "version"` in the project's
`_config.json`. Only if a template must sort client-side, use the version-aware
filter — never the built-in `sort`:

```liquid
{% assign sorted = changelog_entries | sort_semver: "version" | reverse %}
```

`sort_semver` reads the first run of dot-separated integers anywhere in the
label, so `v2.10.0`, `0.1.0` and `propagate-v0.1.0` all compare correctly.
Labels with no digits sort to one end rather than scattering.

---

## Pagination

`listChangelog` takes the same `page`/`page_size` pair as posts and echoes them
back, alongside `total` (the count of ALL matching entries, so you can page to
the end).

```
listChangelog(page=1, page_size=25, include_body=false)
→ { entries: [...], total: 103, page: 1, page_size: 25 }
```

`limit`/`offset` are still accepted for older callers. `page`/`page_size` win
when both are sent. `page_size` is capped at 200 — there is no way to ask for
an unbounded list.

---

## Correcting a published entry

Entries are **not frozen**. `updateChangelog` is a PATCH — only the fields you
send change:

```
updateChangelog(changelog_id, title="…")               # fix a headline
updateChangelog(changelog_id, body={"markdown": "…"})  # fix the body
updateChangelog(changelog_id, version="v2.10.1")       # still unique → 409 on collision
updateChangelog(changelog_id, published_at="…")        # fix the date
```

Re-publishing an already-live entry does **not** re-fire the notification, so
correcting an entry never double-notifies subscribers.

---

## Anti-patterns

| ❌ Don't | ✅ Do |
|---|---|
| `changelog_entries \| sort: "version"` in a template | Trust the API's date order, or `sort_semver` if you must sort |
| Backfill history and hope it orders right | Pass `published_at` on every backfilled entry |
| Roll the major version to dodge a two-digit minor (`v3.0.0` after `v2.9.0`) | Fix the ordering; any version number works |
| `listChangelog()` with bodies to check whether an entry exists | `include_body=false` — the index is ~50× smaller |
| `deploySite()` after every published entry | Entries are fetched live; deploy only for template/settings changes |
| Use a changelog entry for a launch story | That's a post — it has an author, tags and a cover image |

---

## See also

- `references/content.md` — posts, pages, docs (and their `published_at`)
- `references/press-newsroom.md` — press releases, and why a backdated publish
  still notifies journalists
- `references/templates-deploy.md` — overriding `templates/changelog.liquid`
