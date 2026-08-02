# Page-grounding — let the embedded agent READ the page it's on

An embedded `kind='agent'` flow can be made **page-aware**: it reads the actual content of the page
a visitor is on and answers grounded in it ("what's on this page?", "summarize this", questions about
the product/article in front of the visitor) instead of chatting blind. Off by default; **opt-in** with
one prop/attribute.

**Read when:** the client asks for the agent to "read / understand / answer about this page", "know
what page the visitor is on", "summarize the current page", or "ground answers in the page content".

> **Prereq:** the agent flow already exists and is embedded (see [`agent-embed.md`](agent-embed.md) for
> the flow + [`add-agent-react-app.md`](add-agent-react-app.md) for the BYOS React path). Page-grounding
> is a **capability toggle on an existing embed**, not a separate flow. It has **no CLI/MCP tool** — it's
> a client-SDK property, not an API call.

## Hosted SpiderPublish pages — automatic, nothing to do

If the agent is mounted on a **hosted SpiderPublish page** (a page/post/doc on the tenant's own site),
page-grounding is **already on**. Every hosted page exposes a `{url}.md` markdown mirror (via
`?format=md` / the `sys-geo-md-mirror` extension), the embed transmits the page URL, and the agent
fetches that mirror itself. Just publish + deploy — the agent can already read its page.

## Foreign / BYOS pages — opt in with `pageContext`

On a **foreign origin** (the client's own React/Vite/Next/HTML app — anything not a hosted SpiderPublish
page) there is no `.md` mirror, so the SDK **captures the page and pushes it**. Turn it on with one
opt-in, in whichever form matches the embed surface:

| Embed surface | How to opt in |
|---|---|
| React SDK (`@spideriq/agent-react`) | `<SpiderAgent … pageContext="#page-content" />` (a CSS selector) or bare `pageContext` (auto) |
| Web component (`<opvs-agent>`) | `page-context="#page-content"` attribute (or `page-context="true"` for auto) |
| Script-tag loader | `data-spiderflow-page-context="#page-content"` on the mount `<div>` |

```tsx
// Recommended — scope to the real content region (the CONTENT gate):
<SpiderAgent
  flowId="…agent flow id…"
  apiUrl="https://spideriq.ai"
  mode="concierge"
  pageContext="#page-content"   // capture this element's subtree only
/>

// Auto — main visible text of the page, no selector:
<SpiderAgent … pageContext />

// Off (default, omit the prop) — the agent shares nothing:
<SpiderAgent … />
```

`pageContext` accepts:
- **`"#selector"`** — capture that element's subtree only (recommended; clean, relevant text, no nav/footer chrome).
- **`true`** (bare `pageContext`) — auto-capture the page's main visible text.
- **omitted** — **off** (default): nothing is captured.

## What actually happens (so you can explain it)

```
 visitor lands on a page
   → the SDK captures the pageContext region  →  visible text → markdown  (≤ 8 KB, forms/passwords/[data-private] stripped)
   → uploads ONCE per page-change (dedup by url)  →  POST /v1/embed/context {token, url, markdown}   (existing session token, 204)
   → OPVS stores it transiently (session-scoped, never persisted) + hints the agent
   → on a question, the agent pulls it via get_page_context() and answers grounded in the page
```

- **Once per page-change**, not per message. SPA navigation (pushState/replaceState/popstate/hash) re-captures automatically, debounced.
- **Augment-only:** page content *adds to* the agent's knowledge base — it never overrides the configured persona/KB.
- **Transient:** stored session-scoped on the host, never persisted.

## Privacy — exactly what leaves the page (say this to the client)

**Never transmitted:**
- Values of any `<form>` field, and every `<input type="password">`.
- Anything inside a `[data-private]` element (the whole subtree).
- Hidden / `aria-hidden` / `display:none` content, `<script>` / `<style>`.

**Sent (only when opted in):** a markdown rendering of the *visible* text in the chosen region, **≤ 8 KB**
(truncated on a line boundary if longer), once per distinct page URL.

**Two independent gates:**
1. **Origin** — capture only ever uploads for an origin registered on the agent's OPVS binding
   (`allowed_origins`, exact match). An unregistered origin is refused (403) — the same allowlist the
   embed already uses. Register the client's origin first (see `add-agent-react-app.md`).
2. **Selector** — the `pageContext` region decides *what*; default is nothing.

The upload is authed with the **existing embed session token** — no new credential, and the token is
**never** placed in the page or the markdown body.

## Help the client prep their DOM (for the best result)

- Wrap the real content in a **stable selector**: `<main id="page-content">…</main>` → `pageContext="#page-content"`. Beats auto — keeps nav/footer/widgets out.
- Mark sensitive blocks: `<section data-private>…</section>` — never captured. (Forms + password fields are auto-stripped; use `data-private` for anything else — account numbers, PII, internal notes.)
- Nothing to do for SPA nav — re-capture is automatic.

## Verify

1. Open the agent on a real content page.
2. Ask *"What's on this page?"* / *"Summarize this page."* → it answers with page specifics (headings, product details from the `pageContext` region), not a generic reply.
3. Privacy sanity: temporarily wrap a block in `data-private`, reload, confirm the agent no longer mentions it.

## Gotchas

- **No tool for this.** `pageContext` is a client SDK prop / web-component attribute / loader data-attr — there is no `agent_flow_*` / CLI verb to "enable page-grounding". Don't look for one.
- **Foreign origin must be registered first**, or the capture upload 403s (transport gate). Same allowlist as the embed session.
- **Off by default** — no `pageContext`, nothing is captured. The agent shares nothing unless the host opts in.
- **Hosted pages don't need it** — the `{url}.md` mirror already grounds a hosted-mounted agent; `pageContext` is the foreign-origin path.
