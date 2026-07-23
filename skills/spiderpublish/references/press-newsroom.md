# Run a newsroom — press releases, contacts, boilerplates, media kits

A newsroom is not just "a blog for announcements." A real one carries three
things around every release: **who journalists call**, **the About-us paragraph**,
and **the assets they download**. All four are authorable end-to-end from an
agent — which is the differentiator here. No other newsroom product exposes a
write-capable API; the incumbents are read-only or have no public API at all.

Reach for a **post** instead for ongoing editorial content, and the **changelog**
for version-stamped release notes. To **design the newsroom page itself** — which
components to compose, the four archetypes, the `press` data source — see
`references/press-page-design.md`. This reference is the *content* half (the
releases); that one is the *page* half.

---

## The model

| Thing | What it is |
|---|---|
| **Release** | The announcement. Slug + headline + body, optional dateline, hero image, legal tail. Statuses: `draft` → `scheduled` / `embargoed` → `published` → `archived`. A background sweep flips `scheduled` and `embargoed` releases to `published` when their time arrives. |
| **Contact** | A press contact (name, title, email, phone, region, beat, timezone). Attach several to a release via `contact_ids`. |
| **Boilerplate** | The reusable "About <company>" paragraph. One per language; mark one `is_default`. |
| **Media kit** | A downloadable asset bundle. **Story-scoped, not one-per-company** — hold a launch kit, a brand kit, exec headshots. |

Everything is **project-scoped**. Bind a project first (`spideriq use <id>`, an
`-w/--workspace`, or an `X-Project-Id` header).

---

## Steps

Build the supporting objects **first** so the release can reference them in one
call instead of three round-trips.

```
1. createPressContact(name="Dana Ruiz", title="Head of Communications",
                      email="press@acme.com", region="EMEA", beat="Product")
   → contact_id

2. createPressBoilerplate(label="About Acme — short",
                          body="Acme builds …", language="en", is_default=true)
   → boilerplate_id

3. createPressKit(slug="series-a-kit", name="Series A kit")
   → kit_id
   # then, per file — the media must ALREADY be uploaded:
   uploadMedia(...) → media_id
   attachPressKitAsset(kit_id, media_id, caption="Logo pack (SVG + PNG)")

4. createPressRelease(
     slug="acme-raises-series-a",
     title="Acme raises $20M Series A",
     subheadline="Led by Example Ventures.",
     body={"markdown": "## Acme raises…\n\nBERLIN — …"},
     release_type="press_release",
     dateline_city="BERLIN", dateline_date="2026-08-01",
     boilerplate_id=…, media_kit_id=…, contact_ids=[…])
   → lands as a DRAFT

5. publishPressRelease(release_id)          # live now + notifies journalists
   —or—
   schedulePressRelease(release_id, "2026-08-01T09:00:00Z")   # stage it
```

No `deploySite` is required — published releases render live from the API.

→ To surface these releases on a page (the newsroom itself), see
`references/press-page-design.md`. Schedule/embargo timing: Gotchas below.

---

## Gotchas

**`listPressReleases` returns drafts; the public newsroom does not.**
This is the *author* door. If `listPressReleases` shows rows but the public
newsroom is empty, nothing has been published yet — that is not missing data.

**`cursor` is not a page number.**
Pagination is keyset. Pass the previous response's `next_cursor` verbatim.
Feeding it an integer will not work, and there is no `offset`.

**The kit tools do not upload.**
`attachPressKitAsset` takes an **existing** media id. Upload first, then attach.
File size is denormalized from the media record automatically — you never send it.

**`schedulePressRelease` auto-publishes at the set time.**
The status flips to `scheduled`, and a background sweep flips it to `published`
the moment it's due — you can safely promise a client an unattended timed launch.
The time MUST be in the future; a past timestamp returns 400 and tells you to use
`publishPressRelease` for an immediate go-live. A naive datetime is read as UTC.

**WRONG** — a naive local time for a 9am launch, or a past time:
```
schedulePressRelease(release_id, "2026-08-01 09:00")   # read as 09:00 UTC, not local
schedulePressRelease(release_id, "2020-01-01T00:00:00Z")  # 400 — use publishPressRelease
```
**RIGHT** — an explicit future UTC instant:
```
schedulePressRelease(release_id, "2026-08-01T09:00:00Z")   # fires unattended at 09:00 UTC
```

**Embargo mints per-journalist preview tokens.**
`embargoPressRelease(release_id, embargo_until=…)` sets `status='embargoed'` and
returns one preview token **per press contact**, under `embargo_tokens` — surfaced
**exactly once**, so email them out immediately (no later read returns them again).
The release stays off the public door until the same sweep lifts it at
`embargo_until`. `embargo_until` must be a future instant. This is how you run a
real journalist-preview flow.

**Publishing notifies journalists.**
`publishPressRelease` fires the subscriber notification. `unpublishPressRelease`
takes the release back down, but the notification cannot be recalled — so publish
when the copy is final, not to "see how it looks." Use a draft + preview for that.

**Editing a published release is live immediately**, and changing its slug breaks
every existing link. Prefer a correction in place over a re-slug.

**Moving a release between projects carries its relations.**
`reassignPressReleaseProject` remaps contacts / kit / boilerplate to the target
project's equivalents where they exist rather than stranding them, and reports
the counts.

**These tools are in the kitchen-sink `@spideriq/mcp` only.**
They are not in `@spideriq/mcp-publish`, so a 128-tool Antigravity-style content
slice will not see them. Use `@spideriq/mcp` for newsroom work.

---

## Verify

```
getPressRelease(release_id)
  → status == "published"
  → contacts[] is populated (not just contact_ids echoed back)
  → boilerplate_id / media_kit_id are linked
  → embargo_token is ABSENT (it must never serialize)

listPressReleases(status="published")
  → the release appears
```

Then look at the live newsroom page. Do not judge a rendered SpiderPublish page
from `curl` alone — client-rendered bodies fool it; use a visual check.

---

## CLI equivalents

```bash
spideriq content press list --status draft
spideriq content press create --slug acme-raises-series-a --title "…" --markdown "…"
spideriq content press publish <release_id>
spideriq content press schedule <release_id> 2026-08-01T09:00:00Z

spideriq content press contacts create --name "Dana Ruiz" --email press@acme.com
spideriq content press boilerplates create --label "About Acme" --body "…" --default
spideriq content press kits create --slug series-a-kit --name "Series A kit"
spideriq content press kits attach <kit_id> <media_id> --caption "Logo pack"
```

Scheduling has a CLI verb (`press schedule`); **embargo does not** — drive
`embargoPressRelease` via the API/skill method (there is no `press embargo` CLI
verb by design). The token-minting response is only returned on the API call.

→ Design the page these releases appear on: `references/press-page-design.md`.
→ Themes / deploy mechanics: `references/templates-deploy.md`.
