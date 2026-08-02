# Reference — Manage the team (members, roles, invitations)

The team lives on one brand. Roles are **`owner`** (the creator, immovable),
**`brand_admin`** (full management), and **`client_user`** (read-only). Only
owner/admin may mutate — mirrors Clerk's `org:admin` vs `org:member`
([competitors.md](competitors.md)).

## The two flows

```
Add a NEW person   →  sendBrandInvitation  →  (they sign in & accept)  →  member
Change an EXISTING member  →  updateBrandMember (role/status) | removeBrandMember
```

## Invite a teammate

```bash
# brand_id 42 resolved from listBrands; you are owner/admin
curl -X POST https://spideriq.ai/api/v1/brands/42/invitations \
  -H "Authorization: Bearer $OPVS_PAT" -H "Content-Type: application/json" \
  -d '{"email": "dana@acme.com", "role": "client_user"}'   # role default: client_user
```
- Status is **`pending`** until the invitee signs in and accepts. It expires in
  **7 days**.
- `resendBrandInvitation` re-sends the email and resets the 7-day clock.
- `cancelBrandInvitation` revokes a pending invite.

### WRONG → RIGHT — acceptance

**WRONG** — "I'll accept the invite for them."
A PAT **cannot** accept an invitation on someone else's behalf. Acceptance
requires the invitee's own logged-in session (`POST /brands/invitations/accept`
is session-only) or the `auth` skill's `acceptInvite` run as that user.

**RIGHT** — send the invite, then tell the user: *"Invitation sent to
dana@acme.com — they'll get an email and become a member once they sign in and
accept."* Track it with `listBrandInvitations`.

## Change a member's role / remove a member

```bash
# Find the member's user_id
curl -s https://spideriq.ai/api/v1/brands/42/members \
  -H "Authorization: Bearer $OPVS_PAT" | jq '.members[] | {user_id, name, role}'

# Promote client_user → brand_admin
curl -X PATCH https://spideriq.ai/api/v1/brands/42/members/usr_7f3a \
  -H "Authorization: Bearer $OPVS_PAT" -H "Content-Type: application/json" \
  -d '{"role": "brand_admin"}'

# Off-board
curl -X DELETE https://spideriq.ai/api/v1/brands/42/members/usr_7f3a \
  -H "Authorization: Bearer $OPVS_PAT"
```

## "Invites waiting for ME"

```bash
curl -s https://spideriq.ai/api/v1/brands/invitations/pending \
  -H "Authorization: Bearer $OPVS_PAT"   # invitations addressed to the caller's own email
```
This is the only members/invites read that doesn't take a `brand_id` — it's the
caller-centric "who invited me" view. Accepting is still a signed-in action.

## Verify

- After invite: `listBrandInvitations` shows the new row as `pending`.
- After role change: `listBrandMembers` shows the new `role`.
- After removal: the user_id is gone from `listBrandMembers`.

## Gotchas

- **You cannot change or remove the `owner`.** The server rejects it — there is
  always exactly one owner per brand.
- **403** on any of these = caller is `client_user`. Check `membership_role`
  first (the `<HARD-GATE>` in SKILL.md).
- **Removing a member does not free a billing seat.** Seat/plan accounting lives
  in the dashboard ([billing.md](billing.md)) — don't claim "that frees up a
  seat on your plan."
- `member_user_id` is the **user** id from `listBrandMembers`, not an email and
  not the invitation id.
