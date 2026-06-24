# Subscription checkout funnel

A recurring-plan funnel: plan checkout → upgrade-OTO → thank-you. Mirrors tripwire-oto but the
OTO upgrades the subscription line (`cart.upgrade_subscription_line`) instead of adding a one-off
product.

```
plan-checkout node → upgrade-OTO node → thank-you
(subscribe)          (accept = upgrade the plan · decline = keep base plan)
```

## Build

```
funnel_template_apply { slug: "subscription-checkout", name: "<plan> subscription <date>" }
# → DRAFT flow, kind="funnel": plan checkout + upgrade-OTO + thank-you. Capture flow_id.
```

Plans/products come from the template's Medusa catalog (product/plan creation is Medusa Admin —
[8.6c]).

## Customise, publish, walk

Same mechanics as [build-tripwire-oto.md](build-tripwire-oto.md):
- `flow_update_node` for copy; `op:"equal"` (never `"eq"`) on edges.
- Publish with `live_mode=true`; `content_visual_check` the `/f/<flow_id>` URL.
- Stripe TEST card `4242…`; the upgrade-OTO charges off-session on accept, no-op on decline.
- Orders land in `commerce_orders`; `commerce.order_placed` fires (verify via
  `notification_log channel='email' status='sent'`).

> Recurring-billing lifecycle events (renewal, cancellation, dunning) are NOT part of this funnel —
> the funnel captures the initial subscription order; ongoing billing is Stripe/Medusa side and the
> webhook receiver for it is carved as [8.4b].

Pairs with: [build-tripwire-oto.md](build-tripwire-oto.md) · [read-orders.md](read-orders.md)
