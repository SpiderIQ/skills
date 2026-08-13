# Funnels — the Flow graph: multi-step journeys with branching, splits and embeds

> **REQUIRES — read before you plan.**
> **Using THIS skill?** ✅ You can do all of it. `listFunnelTemplates` `getFunnelTemplate` `applyFunnelTemplate` · graph: `addFlowNode` `updateFlowNode` `removeFlowNode` `reorderFlowNodes` `addFlowEdge` `updateFlowEdge` `removeFlowEdge` `archiveFlow` — HTTP methods, no tool ceiling.
> **On MCP instead?** ⚠️ The 12 `flow_*` and 4 `funnel_template_*` tools are `@spideriq/mcp` (kitchen sink) **ONLY**. **Do not substitute a `sys-form-multistep-funnel` component and call it a funnel** — see "The naming trap" below.
> **Gate shape:** `archiveFlow` is **OPT-IN** gated — omitting `dry_run` archives immediately. That is the OPPOSITE default from `deletePage` / `updateSettings`.
> **Live on PUBLISH — no deploy needed.** Content is fetched from STORE at request time; allow ~60s for the edge cache (`s-maxage=60`). **Do not run a deploy to make content appear, and do not tell the user a deploy is pending.** Deploy is only for templates / theme / the config overlay.
> **Not sure which universe you are in?** SKILL.md → *Step 0*.

## Two names for the same call

The body below uses the **MCP tool** names. If you are driving this skill's HTTP
methods instead, substitute:

| This skill (HTTP) | MCP tool |
|---|---|
| `listFunnelTemplates` / `getFunnelTemplate` / `applyFunnelTemplate` | `funnel_template_list` / `_get` / `_apply` |
| `createFlow({kind:'funnel'})` · `getFlow` · `updateFlow` | `flow_create` · `flow_get` · `flow_update_meta` |
| `addFlowNode` · `updateFlowNode` · `removeFlowNode` · `reorderFlowNodes` | `flow_add_node` · `flow_update_node` · `flow_remove_node` · `flow_reorder_nodes` |
| `addFlowEdge` · `updateFlowEdge` · `removeFlowEdge` | `flow_add_edge` · `flow_update_edge` · `flow_remove_edge` |
| `archiveFlow` | `flow_archive` |

Same routes, same semantics, same gates — only the caller differs.

## The naming trap (read this first — it is the #1 wrong turn)

Two unrelated things are called "funnel" in SpiderPublish:

| | `sys-form-multistep-funnel` | A **Flow** with `kind='funnel'` |
|---|---|---|
| What it is | a marketplace **page component** | a first-class **flow row** with its own graph |
| Lives in | one page's blocks | `booking_flows`, own URL `/f/<flow_id>` |
| Steps | linear, fixed | a graph — branch, split-test, embed other flows |
| Logic | none | edges with `when` conditions + actions |
| Analytics | page-level | per-node walk |
| Tools | `insertSection` | the 12 `flow_*` tools |

If the user says *"a multi-step form on the pricing page"* they probably want the
**component**. If they say *"a funnel"*, *"an A/B tested opt-in path"*,
*"upsell after the order form"*, or anything with **branching**, they want a
**Flow**. When it is genuinely ambiguous, ask — building the wrong one is a full
rebuild, not an edit.

## Clone before you compose

Do not build a blank graph. Flow templates are self-contained bundles (graph +
seed page snapshots) meant to be cloned and adapted:

```
funnel_template_list()                  # → { items, count }; bundle bodies omitted
funnel_template_get({ slug })           # → full flow_config graph + seed_pages
funnel_template_apply({ slug })         # → clones the graph AND creates its pages
```

`funnel_template_get` before `apply` — it shows the exact node/edge shape you are
about to inherit, so you can plan the adaptation instead of discovering it after.

`funnel_template_upsert` is **admin-only** (super_admin or a marketplace-authoring
brand). It is how a tested flow gets promoted into a starter — not part of a
normal build.

## The data model

One flow = an ordered list of **nodes** plus event-triggered **edges** between
them. `kind` is a product label; `funnel`, `form` and `booking` are creatable
(`page` / `commerce` land in later phases).

```
flow_create({ kind: 'funnel', name })      → { flow_id, ... }
  │
  ├─ nodes  (flow_add_node — slug unique within the flow)
  │    page          { slug, type:'page', page_id, position,
  │                    reveal_mode:'scroll'|'click_step',
  │                    layer?, collects_fields?, visible_when? }
  │    split         { slug, type:'split', split_kind:'a/b'|'conditional',
  │                    variants?|rules?, default_to?, evaluate_order? }
  │    funnel_embed  { slug, type:'funnel_embed', funnel_id, expansion:'inline' }
  │
  └─ edges  (flow_add_edge)
       { from_node_slug,
         on_event: 'click'|'submit'|'timer'|'scroll_milestone'|'entry'|'field_change',
         to_node_slug, when?, action? }
```

### Node types, in plain terms

- **`page`** — a real CMS page rendered as a step. `reveal_mode:'scroll'` makes it
  a long-scroll step; `'click_step'` makes it advance on interaction.
- **`split`** — pure routing, renders nothing. `split_kind:'a/b'` for a split test,
  `'conditional'` for rules. Always set `default_to` so an unmatched visitor has
  somewhere to go.
- **`funnel_embed`** — composes another flow into this one. `expansion:'inline'`
  splices the inner flow's pages into this walk and folds its answers under the
  embed's slug, addressable as `funnel.<slug>.field.<name>`.

### Embed limits (enforced at insert, as a 400)

| Error | Means |
|---|---|
| `CYCLE_DETECTED` | a flow cannot embed itself or any ancestor |
| `NESTING_DEPTH_EXCEEDED` | more than 3 flows deep |
| `UNSUPPORTED_EXPANSION` | `expansion` other than `"inline"` — `"modal"` / `"widget"` are **not built yet** |

## Build order

```
1. funnel_template_list → get → apply            # clone a starter
   (only if nothing fits: flow_create({kind:'funnel'}))
2. create/adapt the PAGES the page nodes point at
   (createPage → publishPage — a node referencing an unpublished page is a dead step)
3. flow_add_node        # in walk order; slug must be unique
4. flow_add_edge        # wire every exit, including the failure path
5. flow_reorder_nodes   # if positions drifted — must list EXACTLY the existing slugs
6. flow_update_meta     # name/tags/settings/live_mode/head_code/footer_code
7. deploySite           # the pages are not live until you deploy
8. walk the flow yourself at /f/<flow_id> and verify each branch
```

## Gotchas

- **`flow_reorder_nodes` takes the complete set.** `node_slugs` must list exactly
  the existing slugs in the new order; positions are renumbered `0..N-1`. A
  partial list is an error, not a partial reorder.
- **Edges are keyed by the triple** `(from_node_slug, on_event, to_node_slug)`.
  `flow_update_edge` / `flow_remove_edge` need all three — there is no edge id.
- **`flow_remove_node` silently drops the edges that referenced it.** Re-check the
  graph after removing a node or you will have an unreachable step.
- **`flow_update_node` REPLACES the node**, it does not merge. Read it with
  `flow_get` first and send the whole definition back.
- **`flow_update_meta` only writes the fields you pass**, and changing `settings`
  **bumps the version**. It never touches nodes/edges.
- **`flow_archive` is an OPT-IN gate** — pass `dry_run:true` for a preview +
  `confirm_token`, then call again with the token. Omitting both archives
  immediately. This is the opposite default from `deletePage` / `updateSettings`,
  which are safe-default (see `deploy-protocol.md`).
- **`flow_get` on a legacy form/booking row translates on read** and sets
  `compat_translated:true` in the response. That flag means "this row predates the
  unified Flow model" — expect a thin graph, not a bug.
- **Tenant misses are 404, never 403.** A flow belonging to another tenant is
  indistinguishable from one that does not exist. Do not read a 404 as an auth
  problem.

## Verify

```
flow_get({ flow_id })            # graph is what you intended; no orphan nodes
                                 # every node's page_id resolves and is published
deployStatus()                   # the deploy that carries those pages is live
```

Then **walk it as a visitor** at `/f/<flow_id>` — take every branch, including the
`default_to` path on each split. A funnel that works on the happy path and dead-ends
on the fallback is the normal failure, and no tool reports it.

## See also

- `booking-model.md` — the shared `booking_flows` table and the `kind` discriminator
- `forms-booking.md` — `kind='form'` and `kind='booking'`, the sibling surfaces
- `marketplace.md` — `sys-form-multistep-funnel`, the page component (the other "funnel")
- `deploy-protocol.md` — opt-in vs safe-default gate flavours
