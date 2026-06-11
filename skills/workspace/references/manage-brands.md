# Reference — Manage a brand (rename, settings, profile, logo)

A "brand" is one workspace. These ops act only on a brand the caller belongs to,
and every mutation needs `owner`/`brand_admin`.

## Steps

1. **Resolve the brand_id + your role.** `brand_id` is an INTEGER, not the
   `cli_…` public id.
   ```bash
   curl -s https://spideriq.ai/api/v1/brands \
     -H "Authorization: Bearer $OPVS_PAT" | jq '.brands[] | {id, name, membership_role}'
   # → { "id": 42, "name": "Acme", "membership_role": "owner" }
   ```
2. **Read before you write.** `GET /brands/42`, `/brands/42/settings`,
   `/brands/42/information` — so you PATCH only what actually changes.
3. **Mutate (owner/admin only).** PATCH is partial — send only changed keys.

## WRONG → RIGHT

**WRONG — using the cli_ public id as brand_id**
```bash
curl ... https://spideriq.ai/api/v1/brands/cli_b3q656h2cg8j9o6z/settings   # 404 / 422
```
**RIGHT — the integer id from listBrands**
```bash
curl -X PATCH https://spideriq.ai/api/v1/brands/42/settings \
  -H "Authorization: Bearer $OPVS_PAT" -H "Content-Type: application/json" \
  -d '{"settings": {"primary_color": "#0B5FFF", "tone": "professional"}}'
```

**WRONG — PATCH /settings with the full object, blanking fields you didn't mean to**
```bash
-d '{"settings": {"primary_color": "#0B5FFF"}}'   # fine — merge semantics
# but sending a top-level replacement of every key risks clearing tone/logo_url
```
**RIGHT — send ONLY the keys you change.** `updateBrandSettings` merges; omitted
keys are left untouched, not cleared.

**WRONG — changing `billing_email` to "move the subscription"**
```bash
curl -X PATCH .../brands/42 -d '{"billing_email":"new@acme.com"}'
```
`billing_email` is only the **contact** address. It does NOT move the Stripe
subscription or payment method. To change billing, send the user to the dashboard
portal — see [billing.md](billing.md).

## Logo

```bash
# Upload (multipart — a real file/bytes, never a URL). Converted to WebP → R2.
curl -X POST https://spideriq.ai/api/v1/brands/42/logo \
  -H "Authorization: Bearer $OPVS_PAT" -F "file=@./logo.png"
# Remove
curl -X DELETE https://spideriq.ai/api/v1/brands/42/logo -H "Authorization: Bearer $OPVS_PAT"
```

## Creating a second workspace (rare)

```bash
curl -X POST https://spideriq.ai/api/v1/brands \
  -H "Authorization: Bearer $OPVS_PAT" -H "Content-Type: application/json" \
  -d '{"name": "Acme EU", "description": "European entity"}'   # → caller becomes owner
```
Most accounts have exactly one brand. **Confirm intent before creating** — a
stray brand is visible in every workspace switcher and looks like a bug.

## Verify

- After a settings change: re-`GET /brands/42/settings` and confirm the changed
  key, and that untouched keys (logo_url, tone) are still present.
- After rename: `listBrands` shows the new name; the slug (if changed) resolves.

## Gotchas

- **403 on a PATCH** = the caller is a `client_user`, not owner/admin. This is
  expected, not a bug — tell the user which role they'd need.
- **`brand_id` type** — the server binds it as `int` (`brands.py:59`). Passing a
  numeric string is usually fine; passing the `cli_` id is not.
- `?format=yaml` on the GETs cuts tokens 40–76% for large settings blobs.
