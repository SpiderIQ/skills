# Read commerce orders

Every completed funnel checkout writes a **Stripe-canonical order** — Stripe is the order-of-record
(Medusa is catalog/cart only). The order surface is **read-only**: there is no create/update/delete
(orders are written server-side on a succeeded PaymentIntent).

## Tools

| MCP tool | CLI | Returns |
|---|---|---|
| `commerce_order_list { status?, contact_email?, since?, limit?, offset? }` | `spideriq commerce orders list` | paginated orders (status badges, totals) |
| `commerce_order_get { order_id }` | `spideriq commerce orders get <id>` | line items, customer, payment/PaymentIntent, lifecycle |
| `commerce_order_stats { window: 7d\|30d\|90d\|all }` | `spideriq commerce orders stats` | total orders, succeeded-only revenue, dominant currency, per-status breakdown |
| `commerce_order_export_csv { ... }` | `spideriq commerce orders export` | CSV (client-side paging over list) |

`--since` accepts relative (`7d`/`12h`) or ISO. All are tenant-scoped to your own schema — there is
no cross-tenant path.

## Money fields (don't mix units)

- `total_amount_cents` — the **authoritative Stripe minor-unit** figure. Divide by 100 for display.
- Medusa line `unit_price` — **major-unit**. Never floating-point currency math across the two.

## Confirm a sale notified

A sale fires `commerce.order_placed`. To prove the email actually sent:

```sql
SELECT count(*) FROM notification_log
WHERE event_key='commerce.order_placed' AND channel='email' AND status='sent';
```

**Never check `mail_messages`** — that's the SpiderMail inbox store, a different surface.

## Filters compose

`commerce_order_list { status:"succeeded", contact_email:"buyer@x.com", since:"30d" }` returns only
that buyer's succeeded orders in the last 30 days.

Pairs with: [build-tripwire-oto.md](build-tripwire-oto.md)
