# Add an agent to a foreign React / Vite / Next app (the npm SDK)

The `agent-embed.md` recipe puts an agent on a **SpiderPublish-deployed** site (the loader
`<script>` snippet). This recipe is the **BYOS** path: the client already has their **own** React /
Vite / Next app and wants the **same** hired agent inside it, via npm — not a copy-paste script.

**Read when:** the client says "add the agent to *our* React app / Next.js site / Vite app",
"embed the agent in our own codebase", "use the SDK / npm package", or you're wiring an agent into a
repo that is **not** a SpiderPublish site.

> **The honest split still holds.** The npm packages render the agent **surface** and run the
> browser **handshake** — **zero credentials** ship in them. The live **conversation** runs on
> **OPVS** and lights up only once the client **hires an OPVS agent** (mints the binding) **and**
> the app's origin is bound to that agent. Creating/publishing the `kind='agent'` flow + mounting
> the SDK is live today; don't claim the end-to-end conversation works before the OPVS hire + origin
> bind.

## Prereq: a published `kind='agent'` flow id

The SDK **consumes** a flow — it doesn't create one. First create + publish the agent flow
(`agent_flow_create` → `agent_flow_publish`, see `agent-embed.md`) and grab its `flowId` (`agt_…` or
a flow UUID). That's the only value the app needs.

## Install (point `@spideriq` at the registry)

```bash
echo "@spideriq:registry=https://npm.spideriq.ai" >> .npmrc
npm install @spideriq/agent-react     # pulls @spideriq/agent-core (zero-dep) automatically
```

`@spideriq/agent-react` needs **React ≥ 18** (peer dep; works with 18/19 + Next App Router). No
React? Install `@spideriq/agent-core` directly and use `runAgentHandshake` (Option C).

## Pick the integration by how much UI the client owns

| Client wants | Use | From |
|---|---|---|
| A drop-in panel (inline) or floating bubble (concierge) | `<SpiderAgent>` component | `@spideriq/agent-react` |
| Their own chat UI, our transport + state | `useSpiderAgent()` hook | `@spideriq/agent-react` |
| No React (vanilla / Vue / Svelte) | `runAgentHandshake()` | `@spideriq/agent-core` |
| No build step at all | the loader snippet | see `agent-embed.md` |

### A — `<SpiderAgent>` component

```tsx
import { SpiderAgent } from '@spideriq/agent-react';

<SpiderAgent
  flowId="agt_01H…"
  apiUrl="https://spideriq.ai"
  mode="inline"                          // "inline" (fills host) | "concierge" (floating)
  theme={{ primary: '#e11d48', radius: '12px' }}   // bare key → --opvs-agent-<key>
  onError={(reason) => {/* binding_unavailable | session_failed */}}
/>
```

Required props: `flowId`, `apiUrl`. Optional: `mode` (default `inline`), `theme`, `hideHeaders`,
`title`/`subtitle` (in-card header), `className`/`style`, `onError`, `onReady(el)`. Changing
`flowId`/`apiUrl`/`mode` re-mounts a fresh session; `theme`/`title`/`subtitle` are read at mount
(change them live with a React `key`).

### B — `useSpiderAgent()` hook (headless — client builds the UI)

```tsx
import { useSpiderAgent } from '@spideriq/agent-react';

const { state, ready, error, send, respondToWidget } = useSpiderAgent({
  flowId: 'agt_01H…', apiUrl: 'https://spideriq.ai',
});
// state = { messages, isRunning } | null  ·  send()/respondToWidget() are no-ops before ready
```

Pass `disabled: true` to defer mounting (no session until you flip it).

### C — framework-free `@spideriq/agent-core`

```ts
import { ensureOpvsAgentDefined, runAgentHandshake } from '@spideriq/agent-core';
ensureOpvsAgentDefined();
const el = document.createElement('opvs-agent'); host.appendChild(el);
const h = runAgentHandshake(el, { flowId: 'agt_01H…', apiUrl: 'https://spideriq.ai', origin: location.origin });
// h.destroy() on teardown — aborts in-flight work + closes the SSE. Never throws → failures hit onError.
```

## Next.js / SSR

`@spideriq/agent-react` is SSR-safe: `<SpiderAgent>` renders a plain host `<div>` on the server and
does all DOM/handshake work in `useEffect`. In the App Router, put it in a `'use client'`
component. `renderToString` output is always credential-free.

## Gotchas

- **Surface ≠ conversation.** The component mounting (shadow host present) is NOT the agent talking
  — that needs the OPVS hire + a **bound origin**. For BYOS the bound origin is the client's **own**
  domain (e.g. `https://app.acme.com`), not a `*.sites.spideriq.ai` one. If it renders but never
  streams, the origin bind is the usual miss.
- **The token never touches the DOM (§13a).** The session token lives only in the handshake closure
  + the `EventSource` URL — never a prop, React state, an attribute, or serialized HTML. Don't try
  to read it out; don't put a credential in the binding (any `token`/`secret`/`api_key`-shaped key
  is rejected `422`).
- **Registry line is required.** Without `@spideriq:registry=https://npm.spideriq.ai` in `.npmrc`,
  `npm install @spideriq/agent-react` resolves against public npm and 404s.
- **Not `spiderflows`/`lead-search`.** Those FIND prospects; this embeds an already-hired agent.
- End-user docs (for the client's own devs): `https://docs.spideriq.ai/site-builder/add-agent-to-react-app`.
