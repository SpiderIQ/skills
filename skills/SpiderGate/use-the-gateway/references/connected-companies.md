# Connected companies — use a connected company's key, never change it

A company can be **connected** to other companies its owner runs. Inside that group each
company lets the others **use** its gateway keys; it never lets them **change** them. Your
agent sees two read-only answers and nothing else:

| Read | HTTP | MCP | CLI |
|---|---|---|---|
| What you can use now (+ `connected`) | `GET /api/gate/v1/subscriptions` | `gate_subscriptions` | `spideriq gate subscriptions` |
| Your group + who uses your keys | `GET /api/gate/v1/group?days=1-90` | `gate_group` | `spideriq gate group --days N` |

Both take the brand from the credential. There is no brand parameter, so there is nowhere to
put another company's id. Needs `@spideriq/mcp-gate` ≥ 1.16.0 (sink `@spideriq/mcp` ≥ 1.100.0)
or `@spideriq/cli` ≥ 1.80.0.

## The order the gateway tries keys

```
  your request ──▶ 1. your own keys ──▶ 2. connected companies' keys ──▶ 3. the shared pool
                    (yours to change)     (use only)                       (nobody's to change)
```

`gate_group` returns this as `group.order_of_use: ["own", "connected", "pool"]`.

## Steps

1. **Is my company connected?** Call `gate_group`.
   - `group: null` → not connected. That is the answer, not an error. Stop here.
   - Otherwise `group.companies[]` lists each member: `brand_id`, `name`, `is_mine`,
     `keys_shared` (active gateway keys it lets the group use).
2. **What can I use?** Call `gate_subscriptions`. Your own rows are under `subscriptions`.
   A connected company's keys are under the top-level `connected` array, one row per key:

   | Field | Meaning |
   |---|---|
   | `owner_brand_id`, `owner_name` | the company that owns the key |
   | `provider`, `key_label` | which provider, and the owner's label for it |
   | `health_status` | the key's last health reading |
   | `plan_name`, `price_usd_month` | the subscription behind it, and what it costs per month |
   | `display_email` | the account the subscription is on |
   | `use_only` | always `true` |

   No `connected` key at all means the same as `group: null`: nothing to use from a group.
3. **Who uses my keys?** `gate_group` → `my_keys[]`: only keys your company owns that carried
   requests in the window. `usage_by_company[]` splits `total_requests` by company;
   `keep_private: true` means the key is kept to your own company even inside the group.
4. **Keep one of my keys to myself.** `update_brand_integration` with `keep_private: true`
   (MCP; your own key only). Turning it **off** is a human act: the tool sends `false` and the
   server answers `403 human_act_required`. Report that; do not retry.

## WRONG → RIGHT

| WRONG | RIGHT |
|---|---|
| `update_brand_integration` on a connected company's `integration_id` to fix its label | Tell the owner company. Every write on a connected key answers **404**: it is not yours. |
| Look for a `gate_connect` / `gate_pair` tool, or POST to `/brands/{id}/integrations/group*` | There is none, by design. Connecting, disconnecting and pairing are done by a human admin in the dashboard. The raw routes answer an API client **403 `human_act_required`**, identically on every retry. |
| Read `group: null` (or a missing `connected`) as a failed call and retry | It is the answer: your company is not connected. |
| Quote `price_usd_month` as what your company pays | It is what the **owner** pays for that subscription. Your usage of it shows up in its owner's `gate_group` → `usage_by_company`. |
| Pass `brand_id` to read another company's group | There is no such parameter; the brand is always your credential's. |

## Verify

- `gate_group` answers `200` with `window.days` equal to what you sent (default 7).
- Every `connected[]` row has `use_only: true`.
- A write you did not mean to make on a connected key would have been a `404` — if you got a
  `200`, the key was your own.
