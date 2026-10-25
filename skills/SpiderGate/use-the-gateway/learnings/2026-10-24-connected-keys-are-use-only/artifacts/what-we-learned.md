# A connected company's key is use only

## What it is

An owner who runs several companies can connect them. Inside the group each company lets
the others **use** its gateway keys. The gateway tries keys in this order:

```
  1. your own keys  ──▶  2. connected companies' keys  ──▶  3. the shared pool
```

An agent sees the group through two reads: `gate_subscriptions` (a top-level `connected`
array, each row `use_only: true`) and `gate_group` (the members, and who sends requests
through your own keys).

## The traps

1. **A connected key looks like any key, and every write on it is a 404.** The
   brand-integration routes only ever find keys the brand owns. An agent that tries to
   relabel, rotate, test or delete a connected key gets `404`, not `403`: from where it
   stands, the key does not exist. Tell the owner company instead.

2. **There is no connect tool, and there must not be one.** Connecting two companies lends
   one company's paid keys to the other. The dashboard routes for it are session-only and
   answer an API client `403 human_act_required` on every retry. A tool for it would be dead
   on arrival and would advertise a capability the platform withholds. `verify-tool-set`
   fails the build on any gate tool named for connect, disconnect, pair or group
   add/remove/join/leave.

3. **`group: null` is an answer.** So is a `/subscriptions` answer with no `connected` key.
   Both mean "not connected". Neither is a failure to retry.

4. **Keep private is one-way for an agent.** `update_brand_integration` with
   `keep_private: true` keeps one of your own keys from the group. `false` is sent so the
   server can refuse it (`403 human_act_required`); turning it off is a human act.

## How to apply

- Read `use_only` on every row before you plan a write; a `true` means do not write.
- Quote `price_usd_month` as the owner's cost, never yours.
- When a user asks to connect or disconnect companies, say it is done by an admin in the
  dashboard; do not look for a tool.
