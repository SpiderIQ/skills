# CLI / MCP gaps — what this skill needs that the tooling lacks

Per the authoring SPEC (user requirement #2): every capability the skill teaches must
map to a real served surface, and any tool the skill *needs* but the CLI/MCP **doesn't
expose** is flagged here, with grep/curl proof. None of the gaps below BLOCK the skill —
every one has a raw-HTTP workaround the references use — so this is a backlog for the
SpiderGate CLI/MCP owners, not a `needs-replan` escalation.

> **Gaps 1 + 2 are now CLOSED** (SpiderGate tools parity S1, 2026-06-11) — published as
> **cli@1.25.0 · mcp@1.31.0 · mcp-gate@1.3.0 · core@1.26.0**. An agent on those versions
> should prefer the CLI / MCP tool; the raw-HTTP examples in the references still work and
> remain the fallback for older clients. Gaps 3 + 4 are still open.

## Gap 1 — ✅ CLOSED — there was NO `gate` CLI command (was HIGH)

**Fixed in `@spideriq/cli@1.25.0`** ([packages/cli/src/commands/gate.ts](../../../../../packages/cli/src/commands/gate.ts)):
`spideriq gate chat` (`-m`/`-p`/`--system`/`--messages-file`/`--max-tokens`/`--temperature`/
`--json`/`--max-cost <usd>`/`--cache`), `spideriq gate models`, `spideriq gate aliases`,
`spideriq gate usage -b <brand> -d <days>`, `spideriq gate health`. The CLI had no gateway
surface before — every other product slice did.

**Fallback (older CLI):** raw HTTP / the OpenAI SDK pointed at `https://spideriq.ai/api/gate/v1`.

## Gap 2 — ✅ CLOSED — MCP `gate_chat` was text-only (was HIGH)

**Fixed in `@spideriq/mcp@1.31.0` / `@spideriq/mcp-gate@1.3.0` / `@spideriq/core@1.26.0`.**
The MCP `gate_chat` inputSchema + `core.gateChat` now forward `temperature`, `max_tokens`,
`top_p`, `stop`, `seed`, `response_format` (JSON mode), `tools`/`tool_choice`, and
`spidergate_options` (`max_cost_usd`, `cache_enabled`, `fallback_models`, …). Before, the
wrapper forwarded only `model`+`messages`, so the gateway's headline value was MCP-unreachable.

**Note:** token-by-token **streaming** is still not exposed through the single-response MCP
tool — for live streaming use the raw HTTP endpoint (`stream: true`) or the OpenAI SDK; see
[stream-and-events.md](stream-and-events.md). The cost-cap / cache / JSON / tool-calling
controls are all now in the tool.

**Fallback (older MCP):** raw HTTP for any cost-capped / cached / streamed / JSON / tool-calling call.
**Original ask (now shipped):** widen `gate_chat`'s inputSchema to pass `temperature`, `max_tokens`, `stream`,
`response_format`, `tools`, `tool_choice`, and a `spidergate_options` object through to
`client.gateChat`.

## Gap 3 — usage/traces require a numeric `brand_id`; no "usage for my PAT" (MEDIUM)

Every analytics tool (`gate_usage`, `gate_traces`, `gate_stats`, `gate_agents`,
`gate_providers`, `gate_trace_detail`, `gate_trace_stats`) **requires** `brand_id`. A
PAT-holding agent often doesn't know its numeric brand id (it knows its `cli_…` workspace
slug + its token).

**Proof** — every analytics tool in `gate.ts` lists `brand_id` in `required`. There is no
`brand_id`-less "usage for the authenticated token" endpoint in `app/api/v1/dashboard_gate.py`
on the PAT path.

**Workaround:** fetch `brand_id` from the dashboard (Gate → Overview) or an admin, pass it
explicitly.
**Wanted:** a `gate_usage` / `gate_traces` variant that resolves `brand_id` from the calling
PAT's `client_id`, so an agent can read *its own* spend without an out-of-band lookup.

## Gap 4 — no MCP/CLI for the multi-modal endpoints (LOW — known/deferred)

`/api/gate/v1/images/generations`, `/audio/speech`, `/audio/transcriptions`, and
`/embeddings` are live (Phase 11) but have **no** MCP tool or CLI command.

**Proof** — no `gate_image*`/`gate_audio*`/`gate_embed*` tools in `gate.ts`; SpiderGate
CLAUDE.md explicitly lists "S7 MCP tools + CLI commands" as a pending deferral.

**Workaround:** raw HTTP with the real OpenAI model name (`dall-e-3`, `tts-1`, `whisper-1`,
`text-embedding-3-large`) — these forward verbatim (no aliases for multi-modal).
**Wanted:** `gate_image_generate`, `gate_audio_speech`, `gate_audio_transcribe`,
`gate_embed` (tracked as SpiderGate Phase 11 S7).

---

**Net:** the skill is fully usable today via HTTP, but the *MCP/CLI agent surface
under-serves the gateway* — the cost-control + streaming + structured-output features that
make SpiderGate worth using over a raw provider are HTTP-only. Closing Gaps 1 + 2 would let
an MCP/CLI agent use the gateway's real value without dropping to curl.
