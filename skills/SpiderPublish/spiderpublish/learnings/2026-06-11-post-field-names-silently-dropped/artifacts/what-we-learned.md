# Post field names that silently drop

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

You call `createPost` with a cover image, an author, a category, and a featured
flag. The post is created — but the cover image is blank, there's no author,
it's in no category, and it's not featured. **No error.** The data just isn't
there.

This is what a paying client's agent hit on 2026-06-10:

> createPost ignores: cover_image_url, author_id, category_id
> updatePost ignores: cover_image_url, category_id, featured, body

## Why it happens

The SpiderPublish write endpoints (`POST /dashboard/content/posts`,
`PATCH /dashboard/content/posts/{id}`) build the row from a known set of keys and
**ignore everything else with no error**. The OLD skill schema sent the *wrong*
key names, so the backend dropped them:

| You meant | Old skill sent (DROPPED) | Backend actually keeps |
|---|---|---|
| cover image | `cover_image` | **`cover_image_url`** — the name MUST end in `_url` |
| featured | `featured` | **`is_featured`** |
| category | `category_id` (one) | **`category_ids`** — a **LIST** of UUIDs |
| author | *(omitted on createPost)* | **`author_id`** (UUID) or **`author_name`** (free text) |

The MCP tool `content_create_post` had the right names all along — only the
marketplace skill's `client/schema.yaml` was wrong. So "the API is broken" was
really "the skill taught the wrong field names."

## What "good" looks like

```jsonc
// createPost
{
  "title": "Launch week",
  "body": { /* Tiptap JSON document */ },
  "cover_image_url": "https://media.cdn.spideriq.ai/…/hero.jpg",  // _url!
  "author_id": "…uuid…",            // create one first via createAuthor
  "category_ids": ["…uuid…"],       // a LIST, even for one
  "is_featured": true                // not "featured"
}
```

Set up taxonomy first when you need it: `createAuthor` → `createCategory` →
`createTag` return the UUIDs you pass to `createPost`.

## Update — the 3 worst aliases are now folded server-side (0.4.1, 2026-06-11)

After a VayaPin production agent hit this again on 0.4.0, the content API was
changed to **accept the three most-confused aliases** instead of dropping them
(`apply_post_field_aliases` in `app/schemas/content.py`, a `mode='before'`
model_validator on PostCreate/PostUpdate):

```
cover_image -> cover_image_url    featured -> is_featured    category_id -> category_ids (single -> list)
```

The **canonical field wins** if both are sent. This is a safety net, not a
licence — **every OTHER misnamed field is still silently dropped**, so the rule
below still holds. Two adjacent traps the same report surfaced:
`cover_image_url` is host-allowlisted (use a `uploadMedia` CDN url, not an
arbitrary host → 422), and `vayapin_pins` wants the public `COUNTRY:CODE` (the
`vayapin` field from `vayapinCards`), not the pin UUID.

## The general rule

SpiderPublish write endpoints are **silently lenient** — an unknown key is not an
error, it's a no-op. So a typo'd or renamed field looks like "the API ignores
it." When a field "doesn't persist," first check the **exact** name against
`client/schema.yaml` / the MCP tool, not whether the endpoint "works."

## See also

- `references/content.md` — the full post-authoring flow.
- `learnings/2026-06-11-authoring-is-not-live/` — and even with the right fields,
  the post isn't live until you deploy.
