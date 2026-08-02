# membership_role gates every workspace mutation — read it, don't assume it

## The lesson
`workspace` mutations (`updateBrand`, `updateBrandSettings`,
`updateBrandMember`, `removeBrandMember`, `sendBrandInvitation`,
`cancelBrandInvitation`, logo, information) are all **owner/brand_admin only**. A
`client_user` calling any of them gets **HTTP 403**. The caller's role for a
brand is the `membership_role` field on each entry from `listBrands` (and on
`getMe` in the `auth` skill).

So the correct shape of any mutating task is: **listBrands → read
membership_role → only then mutate** (the `<HARD-GATE>` in SKILL.md).

## Why this is load-bearing (a real incident)
On 2026-06-09 (WR1, fixed in PR #1582) `GET /api/v1/brands` **silently dropped**
`membership_role` from its response. Effect: every non-super-admin read back as a
plain "member", the dashboard's `useBrand().isAdmin` evaluated false, and genuine
brand-admins **couldn't edit anything** gated on the role — even though the server
would have authorized them. The field is small but load-bearing: when it's
missing or wrong, the entire admin surface looks broken.

For an agent the failure mode is the inverse: if you *assume* admin and fire a
write as a `client_user`, you get a 403 and the user is confused about why
"nothing happened." Reading the role first lets you tell them plainly: *"You're a
client_user on Acme — only an owner or brand_admin can change roles. Ask an admin,
or I can show you who they are with listBrandMembers."*

## Apply
- Before any write: confirm `membership_role ∈ {owner, brand_admin}` for the
  target brand.
- Treat a 403 as "wrong role", not "bug" — surface the role requirement.
- The owner is immovable: you can't change/remove the `owner` role.

> Starting point, not ground truth — verify against current `brands.py` gates.
