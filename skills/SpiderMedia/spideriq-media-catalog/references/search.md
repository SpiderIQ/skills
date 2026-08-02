# Search the media catalog (search vs list)

`searchAssets` is for "I know part of the name / any of these tags." `listAssets`
is for "show me the catalog, filtered exactly." They look similar and share param
names — but the tag logic is opposite. Get this wrong and you silently get the
wrong set.

## WRONG

```bash
# WRONG: expecting listAssets tags to match ANY of two tags
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/assets?tags=hero&tags=banner"
# → returns ONLY assets tagged BOTH hero AND banner (AND) — usually far fewer than expected.

# WRONG: expecting q to match a tag or metadata value
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/search?q=hero"
# → q matches the KEY/FOLDER substring only. If "hero" is a tag (not in the key/folder), this misses it.
```

## RIGHT

```bash
# RIGHT: ANY of several tags → searchAssets (overlap)
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/search?tags=hero&tags=banner&format=yaml"
# → assets tagged hero OR banner.

# RIGHT: substring on the key/folder → searchAssets q
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/search?q=campaigns/2026&kind=image&format=yaml"
# → images whose key/folder contains "campaigns/2026".

# RIGHT: an exact folder + ALL tags → listAssets (AND)
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/assets?folder=campaigns/2026&tags=hero&tags=approved"
# → assets in exactly that folder carrying BOTH hero AND approved.
```

## The difference, in one table

| | `listAssets` (`/catalog/assets`) | `searchAssets` (`/catalog/search`) |
|---|---|---|
| `tags` | **AND** — must carry every tag | **ANY** — overlap, any one tag |
| `folder` | exact-match filter | (no folder param — use `q`) |
| `q` | (not available) | substring on **key/folder only** |
| `kind` | filter | filter |
| `status`, `storage_tier` | filters | (not available) |
| pagination | `limit` + `offset` | `limit` only |

## Gotchas

- `q` is **key/folder substring only** — case-insensitive, but it does NOT look
  inside `tags` or `metadata`. To match a tag, pass it as `tags=`.
- `searchAssets` has **no `offset`** — it returns the top `limit` matches
  (newest-first). For deep pagination of an exact filter, use `listAssets`.
- Both cap `limit` at 500.
- Combining `q` + `kind` + `tags` is AND across the three axes (but `tags` is
  ANY *within* the tag set).

## Verify

```bash
# Find any video whose key/folder mentions "promo"
curl -s -H "Authorization: Bearer $SPIDERIQ_PAT" \
  "https://spideriq.ai/api/v1/media/catalog/search?q=promo&kind=video&format=yaml"
```
