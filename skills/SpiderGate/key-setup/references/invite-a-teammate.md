# Reference — invite a teammate

When a provider account belongs to someone else (a colleague holds the OpenAI
login), the owner invites them to add that key themselves. You **propose** the
invite; the owner **sends** it from the dashboard. You never email anyone.

## Steps

1. `getOnboardingStatus` → read `answers.teammates`.
2. Build the list to send:
   - keep every entry with `status: proposed`, as `{email, providers}`;
   - same email as the new one → add the new providers to it;
   - otherwise append `{email, providers}`.
   Entries with `status` `sent`, `completed` or `expired` are invites, not
   proposals. Leave them out; they stay.
3. `proposeInvite` with `{"answers": {"teammates": [ …the whole list… ]}}`.
4. Tell the owner: "I've prepared the invite for anna@example.com (OpenAI).
   Send it from https://app.spideriq.ai/dashboard/gate/setup?step=4."

The MCP tool `gate_invite_contributor` and `spideriq gate setup invite` do
steps 1–3 for you.

## WRONG → RIGHT

**WRONG — sending only the new teammate**
```json
{"answers": {"teammates": [{"email": "cy@example.com", "providers": ["groq"]}]}}
```
That REPLACES the list: every other proposal is gone.

**RIGHT — the whole proposed list**
```json
{"answers": {"teammates": [
  {"email": "bo@example.com", "providers": ["nvidia_nim"]},
  {"email": "cy@example.com", "providers": ["groq"]}
]}}
```

**WRONG — "I've sent Anna an invite."** Nothing was sent.
**RIGHT — "It's ready; send it from step 4."**

## What happens next

The owner presses Send. Anna gets one email with a link valid for 72 hours,
adds her key on her own page, and her entry moves to `sent`, then
`completed`. Status shows `expires_in_h` while it is open.

## Gotchas

- At most 20 teammates and 25 providers each. Providers are checked against
  the provider list.
- Only the brand owner can propose and send. A brand member's request is refused.

## Verify

`getOnboardingStatus` → `answers.teammates` shows the entry with
`status: proposed`, and `next.action` is `send_invites`.
