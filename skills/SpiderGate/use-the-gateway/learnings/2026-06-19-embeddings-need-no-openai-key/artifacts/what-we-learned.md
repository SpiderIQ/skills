# Embeddings through SpiderGate need no raw OpenAI key

**What happened.** OPVS (and most agents) kept a direct `OPENAI_API_KEY` solely to call
`text-embedding-3-*`, because the early SpiderGate embeddings endpoint was a thin shim with no
aliases and no metering. EMB.1 closed that gap: embeddings now route through the gateway
exactly like chat, so the raw OpenAI key is no longer needed on the caller side.

**The pattern.** Treat SpiderGate as an OpenAI-compatible provider:

```python
from openai import OpenAI
client = OpenAI(
    base_url="https://spideriq.ai/api/gate/v1",
    api_key="cli_…:sk_…:secret_…",   # SpiderGate PAT, NOT an sk-… key
)
resp = client.embeddings.create(model="agent/embed-small", input=["a", "b"])
```

**Aliases (a task, not a vendor):** `agent/embed-small` → `text-embedding-3-small` (1536),
`agent/embed-large` → `text-embedding-3-large` (3072), `agent/embed` → small. Raw OpenAI names
still pass through. Unlike images/TTS/STT, embeddings *do* carry aliases.

**`dimensions`:** a request value overrides the alias default; omit to take it. `ada-002`
ignores it.

**Metering is automatic + capability-gated.** The endpoint passes `client_id`/`brand_id`/
`integration_id` metadata to `litellm.aembedding`, so `SpiderGateCallback` writes a
`gate_request_logs` row (`request_kind='embedding'`, non-NULL `client_id`) and meters tokens
on the `spiderGateLlm` meter — same usage/traces surface as chat. Key selection filters to
`supports_embeddings=TRUE` OpenAI keys, so a chat-only key is never used.

**No fallback, fail-loud.** If the brand has no embeddings-capable key (vault
`supports_embeddings` flag off / no `sk-…` registered), the call returns `503
no_embeddings_key`. Don't swallow it — register a key via Invite Contributor at
`/dashboard/gate/vault`.

**Still HTTP-only.** There is no `gate_embed` MCP/CLI tool yet (gap 4) — use the raw endpoint
or the OpenAI SDK pointed at the gateway.

> Starting point, not ground truth — verify aliases against `gate_embedding_aliases` and the
> endpoint against `app/api/v1/gate/embeddings.py` before relying on exact dims.
