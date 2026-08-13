# Design the blog — the listing page, the post page, and which of the three paths to take

> **REQUIRES — read before you plan.**
> **Package:** the three design paths differ. Path A (**CMS page**) and Path C (**template override**) work in **every** universe. Path B (`content_override_section`) is **kitchen-sink only**.
> **Tools:** `createPage` `publishPage` `insertSection` `template_get` `template_upsert` `listSiteTemplates` `applySiteTemplate` (all universes) · `content_override_section` (kitchen sink only — Path B)
> **Needs `deploySite`.** Templates, theme files and the deploy-time `_config.json` overlay live in per-tenant KV and only change on deploy — unlike content, which is live on publish.
> **Not sure which universe you are in?** SKILL.md → *Step 0*.

Writing posts is `content.md`. This file is about the **pages the posts appear on** —
the `/blog` index and the `/blog/{slug}` post layout. They are a different subsystem
from the posts themselves, and the most common blog request ("make the blog look
like X") touches only this file.

## The misconception that wastes the most time

**There is no `dm-blog-listing` component. There is no blog component at all.**

Agents routinely try `content_update_component({slug:'dm-blog-listing'})` or go
hunting the marketplace for a blog block. The blog index is **template-based**,
not block-based — it is rendered by `templates/blog.liquid` in the per-tenant
override KV, merged over the bundled default theme. Nothing to PATCH.

Similarly: **creating a component with slug `blog` does not override anything.**
Components and theme sections are separate subsystems.

## Three paths — pick deliberately

| | Path A — CMS page | Path B — section override | Path C — template upsert |
|---|---|---|---|
| What you do | create a page at slug `blog` | `content_override_section` | `template_upsert('templates/blog.liquid')` |
| You get | full block composition | a thin wrapper over Path C | direct Liquid control |
| Needs | any universe | **kitchen sink only** | any universe |
| Best for | marketing-shaped blog index (hero + featured + FAQ + CTA) | quick restyle when you have the sink | precise control, loops, pagination |
| Reversible by | deleting the page | re-override | re-upsert |

Path B writes to the **same place** as Path C (`templates/blog.liquid` /
`templates/blog-post.liquid` in the tenant KV). It is a convenience wrapper, not a
different capability — so **on mcp-publish, Path C is not a downgrade**, it is the
same operation with the path spelled out.

### Path A — a CMS page at slug `blog` (fully opt-in)

```
createPage({ slug: 'blog', template: 'default', blocks: [...] })
publishPage({ id })
deployPreview() → deployProduction({ confirm_token })
```

`/blog` now renders your blocks instead of the built-in listing. To revert,
delete the page — the legacy listing returns automatically.

> ⚠️ **`/blog/tag/{tag}` keeps the legacy listing.** There is no per-tag CMS-page
> hook. If your design depends on tag pages matching the index, Path A will look
> inconsistent — use Path C instead.

> ⚠️ **Use `template: 'default'`, never `'blank'`.** `blank` drops the whole layout,
> not just header/footer, so the page carries no background and headings render
> white-on-white on a dark tenant. Same rule as the newsroom page (LEARNINGS Rule 125).

### Path C — override the Liquid (works everywhere)

```
template_get({ path: 'templates/blog.liquid' })       # bundled default if no override yet
template_upsert({ path: 'templates/blog.liquid', content: <modified> })
template_upsert({ path: 'templates/blog-post.liquid', content: <modified> })
previewTemplate(...)                                   # eyeball before deploy
deploySite()
```

CLI equivalent: `spideriq templates set 'templates/blog.liquid' --file ./blog.liquid`.

`template_get` returning a **big inline-CSS template** means that is **your tenant's
prior customization** sitting in KV — not what SpiderPublish ships. The default is
small and CSS-variable-driven.

## Shop before you design

Before hand-writing a blog layout:

```
listSiteTemplates()          # `blog-minimal` is a purpose-built blog starter
listPageTemplates()          # single-page starters
listMarketplaceComponents({ category: 'content' })   # 10 content sections
listMarketplaceComponents({ category: 'hero' })      # 6 heroes for a blog cover
```

For a Path-A index, the sections that actually compose a good blog page live under
`content`, `hero`, `cta`, `social-proof` and `trust-authority` — **not** under a
`blog` category (there isn't one). Search wider than the noun.

## Colors before templates

Most "the blog doesn't match our brand" requests are a settings change, not a
template rewrite. `updateSettings` injects CSS custom properties into every page's
`<head>`, including the blog:

| Field | Controls |
|---|---|
| `primary_color` | the **accent** — links, buttons. **Not the background.** |
| `surface_color` | the page background |
| `surface_elevated_color` | cards, the post-card surface on the index |
| `body_text_color` · `heading_color` · `subtle_color` | type |

The single most common colour mistake: setting `primary_color` expecting the
background to change. It is the accent. Background is `surface_color`.

Anything the palette can't reach: a `<style>` block in `custom_head_scripts`.
Both need a deploy.

## The blog is not done until…

| | |
|---|---|
| Taxonomy | at least one **author** and the tags/categories the index filters on exist |
| Content | at least one post **published** (a design reviewed against an empty index is not reviewed) |
| Index | `/blog` renders your design — and `/blog/tag/{x}` too if you took Path A (it won't) |
| Post page | `templates/blog-post.liquid` matches the index — restyling only the index is the usual half-finish |
| Reachability | `/blog` is **linked from navigation** (`updateNavigation`) — otherwise it is an orphan URL |
| Feeds | `/feed.xml` / `/atom.xml` still render if you changed the post template |
| Live | **deployed** |

## Post-write field names (the silent-drop trap)

Belongs to `content.md` but bites every blog build:

| Want to set | Use | NOT |
|---|---|---|
| cover image | `cover_image_url` (host-allowlisted — `uploadMedia` first) | `cover_image` |
| featured flag | `is_featured` | `featured` |
| categories | `category_ids` (a **list** of UUIDs) | `category_id` |

The three aliases are folded server-side now, but **any other misnamed field is
still silently dropped with no error**.

## Verify

```
deployStatus()
content_visual_check({ url: 'https://<tenant>/blog' })
  → screenshot shows your layout
  → body_text_preview contains your post titles (the index is server-rendered)
content_visual_check({ url: 'https://<tenant>/blog/<a-published-slug>' })
```

If a post's body renders blank in the dashboard editor but fine on the site — that
is the markdown-sibling/Tiptap editor gap, not a design bug. Verify the **served
page**, never the editor.

## See also

- `content.md` — writing posts, authors, tags, categories, navigation
- `templates-deploy.md` — themes, `blog-minimal`, the two-phase deploy
- `block-types.md` — the 15 block types for a Path-A index
- `marketplace.md` — browsing sections to compose with
- `press-page-design.md` — the same problem solved for the newsroom, with archetypes
