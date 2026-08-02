# Design an agent component — author a mountable `<opvs-agent>` marketplace block

A **marketplace agent component** is a `content_components` row with
`marketplace_category='agent'` that mounts the in-DOM `<opvs-agent>` web component bound to a
`kind='agent'` flow. It is the reusable, brand-skinned BLOCK an agent drops onto a page — distinct
from the **agent flow** itself.

**Read when:** the client wants to "design / build / brand an agent widget", "make a reusable AI
agent block", "add a section/widget/concierge/headless agent to the marketplace", or skin an
`<opvs-agent>` to their colors.

> **Two primitives, don't confuse them.** The `agent_flow_*` tools (see
> [`agent-embed.md`](agent-embed.md)) create the **flow** + its OPVS **binding** (the live
> conversation). This recipe authors a **component** that RENDERS such a flow. You usually do both:
> create/own the flow once, then design one or more components that mount it. The component holds
> **zero** credentials — it only carries a `flow_id` prop.

## The fast path — `content_create_agent_component` (MCP)

MCP consumers (`@spideriq/mcp`, `@spideriq/mcp-publish`) get one tool that bakes the entire shape:

```
content_create_agent_component {
  slug: "acme/agent-sdr",
  name: "Acme SDR",
  form_factor: "section",            // section | widget | concierge | headless
  role: "sdr",                       // optional → agent_meta.role
  default_flow_id: "<flow uuid>",    // optional → default_props.flow_id (mounts without per-insert props)
  skin: { primary: "#0b5", radius: "18px" }   // optional token overrides; omit = brand-inherit
}
→ component row (marketplace_category='agent', kind='interactive', js_runtime='web-component')
```

Then mount + ship:

```
page_insert_section { page_id, component_slug: "acme/agent-sdr", props: { flow_id: "<uuid>" } }
content_publish_page → content_deploy_site
```

The tool derives `agent_meta.surface` from `form_factor`, generates the `<opvs-agent>` template,
attaches the `opvs-agent` CDN dependency, and writes a parity-consistent `agent_meta`. **You never
hand-write the element.**

## The four form-factors

| `form_factor` | runtime surface | element | mount |
|---|---|---|---|
| `section`   | flow      | `surface="standalone"` | full-width in-page block / `/f/<id>` |
| `widget`    | inline    | `surface="standalone"` | compact inline card filling its host |
| `concierge` | concierge | `surface="concierge"`  | floating launcher + slide-over over `<body>` |
| `headless`  | inline    | `<opvs-agent headless>` | transport+state only — you render 100% of the UI |

`form_factor` is the **marketplace-LOCAL** discovery taxonomy. It is NOT the runtime `AgentSurface`
binding contract — it resolves to one. Browse by it:

```
content_list_marketplace_components { category: "agent", agent_form_factor: "concierge" }
```

## The manual path (OPVS Tier-3 client / raw HTTP) — the emission recipe

A generated HTTP client (`createComponent` → `POST /dashboard/content/components`) has no template
baker, so author the row directly. Set **all** of these (a missing field = a broken or invisible
component):

```jsonc
{
  "slug": "acme/agent-sdr",
  "name": "Acme SDR",
  "kind": "interactive",
  "js_runtime": "web-component",
  "marketplace_category": "agent",
  "dependencies": ["opvs-agent"],           // the content_cdn_allowlist KEY, not a URL
  "html_template": "<opvs-agent surface=\"standalone\" data-flow-id=\"{{ flow_id }}\"{% if title %} data-title=\"{{ title }}\"{% endif %} style=\"display:flex;flex-direction:column;width:100%;min-height:600px;--opvs-agent-primary:var(--primary,#eebf01);--opvs-agent-bg:var(--surface,#0A0A0B);--opvs-agent-surface:var(--surface-elevated,#111113);--opvs-agent-text:var(--body-text,#e5e5e5);--opvs-agent-font-body:var(--font-body,system-ui,sans-serif);\"></opvs-agent>",
  "props_schema": { "type": "object", "required": ["flow_id"], "additionalProperties": false,
                    "properties": { "flow_id": { "type": "string", "format": "uuid" } } },
  "agent_meta": { "role": "sdr", "surface": "flow", "form_factor": "section" },
  "tags": ["agent","ai","conversational","section","opvs-agent"]
}
```

Per form-factor, change only the element line:

- **widget** — same as section but `max-width:480px;min-height:520px;margin-inline:auto;--opvs-agent-radius:16px;` and `agent_meta.surface="inline"`, `form_factor="widget"`.
- **concierge** — `surface="concierge"`, no layout box (it floats), `agent_meta.surface="concierge"`, `form_factor="concierge"`.
- **headless** — `<opvs-agent headless data-flow-id="{{ flow_id }}"></opvs-agent>` (no style at all), `agent_meta.surface="inline"`, `form_factor="headless"`.

## Skinning — tokens INLINE, never the `css` column (the #1 trap)

The web-component runtime **bypasses** `content_components.css` (renderer `tags.ts`). A CSS string in
the `css` column is silently ignored. The skin is the `--opvs-agent-*` token preset baked into the
element's inline `style`:

| token | controls | baseline (brand-inherit) |
|---|---|---|
| `--opvs-agent-primary` | accent | `var(--primary,#eebf01)` |
| `--opvs-agent-bg` | page background | `var(--surface,#0A0A0B)` |
| `--opvs-agent-surface` | panel | `var(--surface-elevated,#111113)` |
| `--opvs-agent-surface-2` | secondary surface | `var(--subtle,#1A1A1D)` |
| `--opvs-agent-text` | body text | `var(--body-text,#e5e5e5)` |
| `--opvs-agent-radius` | corner radius | — (widget: 16px) |
| `--opvs-agent-font-body` | body font | `var(--font-body,system-ui,sans-serif)` |
| `--opvs-agent-font-heading` | heading font | `var(--font-heading,var(--font-body,…))` |

Leave a token at its `var(--brand, …)` baseline → the tenant's theme wins (true brand-inherit).
Override with a raw value (`#0b5`, `18px`, `'Inter',sans-serif`) → that wins. Deeper restyle:
`::part(panel|launcher|message|send-button)` from the light DOM. Full token/part/event reference:
`apps/opvs-agent/CUSTOMIZATION.md` (also https://docs.spideriq.ai/docs/site-builder/agent-embed).

## Gotchas

- **`form_factor` ≠ `surface`.** `form_factor` is marketplace-local discovery; `surface` is the
  runtime binding. Set them consistently — section→flow, widget→inline, concierge→concierge,
  headless→inline. The MCP tool does this for you.
- **The `css` column does nothing** for an agent component — skin via inline `--opvs-agent-*` tokens.
- **`dependencies` is the allowlist KEY `opvs-agent`**, not a CDN URL — the validator matches on key.
- **Component ≠ live conversation.** Rendering succeeds (shadow host present) before the agent talks;
  the conversation needs the OPVS hire + a bound origin on the flow (see `agent-embed.md`).
- **Visual-check on `dom.shadow_hosts`, NOT `body_text_preview`** — the agent lives in shadow DOM.
