# Embeddings through the gateway — vectorise text without a raw OpenAI key

SpiderGate exposes an **OpenAI-compatible** `POST /api/gate/v1/embeddings`. Point any
OpenAI client at the gateway, send a SpiderGate **embed alias** (or a raw model id), and you
get back the standard OpenAI embeddings shape — metered + per-key-capped under your brand,
the same as chat. The headline: **you no longer hold a raw `OPENAI_API_KEY`** — one SpiderGate
PAT covers chat AND embeddings, and an admin owns the underlying provider key in the vault.

## The consumption pattern (OpenAI SDK, "openai-compatible" provider)

| Config | Value |
|---|---|
| provider type | `openai` (openai-compatible) |
| `baseUrl` / `base_url` | `https://spideriq.ai/api/gate/v1` |
| `apiKey` | your **per-brand SpiderGate key** — `cli_…:sk_…:secret_…` (a PAT), NOT an `sk-…` OpenAI key |
| `model` | `agent/embed-small` (default lane) · `agent/embed-large` · `agent/embed` |

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://spideriq.ai/api/gate/v1",
    api_key="cli_…:sk_…:secret_…",      # your SpiderGate PAT — no OPENAI_API_KEY anywhere
)

resp = client.embeddings.create(
    model="agent/embed-small",           # → text-embedding-3-small, 1536 dims
    input=["first chunk", "second chunk"],  # single string OR a batch (OpenAI caps at 2048)
)
vectors = [d.embedding for d in resp.data]   # len == len(input), order preserved by .index
```

Raw HTTP equivalent:

```bash
curl -s -X POST "https://spideriq.ai/api/gate/v1/embeddings" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  -H "Content-Type: application/json" \
  -d '{"model": "agent/embed-small", "input": "the quick brown fox"}' \
  | jq '.data[0].embedding | length'   # → 1536
```

## Aliases (a TASK, not a vendor — like chat)

| Alias | Resolves to | Default `dimensions` |
|---|---|---|
| `agent/embed-small` | `text-embedding-3-small` | 1536 |
| `agent/embed-large` | `text-embedding-3-large` | 3072 |
| `agent/embed` | `text-embedding-3-small` (→ small) | 1536 |

Unlike images/TTS/STT (which take only raw OpenAI model names), embeddings **do** carry
SpiderGate aliases — so you stay vendor-agnostic. A raw OpenAI name
(`text-embedding-3-large` / `-small` / `ada-002`) still passes through unchanged.

## Dimensions

`text-embedding-3-*` support output truncation. A **request-supplied `dimensions` always wins**
over the alias default; omit it to take the alias default (1536 small / 3072 large).
`ada-002` ignores `dimensions`.

```python
client.embeddings.create(model="agent/embed-large", input="x", dimensions=1024)  # 1024-wide
```

## WRONG → RIGHT

| WRONG | RIGHT |
|---|---|
| `api_key="sk-proj-…"` (your own OpenAI key) | `api_key="cli_…:sk_…:secret_…"` — the SpiderGate PAT; the OpenAI key lives in the vault |
| `base_url="https://api.openai.com/v1"` | `base_url="https://spideriq.ai/api/gate/v1"` — so it meters + caps + traces |
| one request per text in a loop | pass the whole list as `input=[...]` — one metered batch call |
| assuming `agent/embed` == large | `agent/embed` → **small** (1536); use `agent/embed-large` for 3072 |
| catching the 503 and silently dropping | a `503 no_embeddings_key` means the brand has **no embeddings-capable key** — surface it |

## Gotchas

- **`503 no_embeddings_key`** is fail-loud, not a transient. The brand needs an OpenAI `sk-…`
  key registered with the vault `supports_embeddings` flag ON (Invite Contributor at
  `/dashboard/gate/vault`). There is **no fallback chain** for embeddings — a chat-only OpenAI
  key is deliberately never picked.
- **Metering is automatic.** Every call writes a `gate_request_logs` row with
  `request_kind='embedding'` and meters tokens on the same `spiderGateLlm` meter as chat — it
  shows up in your usage/traces. No extra flag needed.
- **Per-key caps apply.** Embeddings share the daily/minute/spend caps of the selected key, so a
  large batch job can hit the same cap a chat burst would.
- **PII still matters.** Embeddings of client PII are sent to OpenAI like any other call — fine
  for OpenAI's paid tier (not trained on), but treat the *content* with the same care as chat.

## Verify

```bash
# Round-trips and returns 1536 floats for the small alias
curl -s -X POST "https://spideriq.ai/api/gate/v1/embeddings" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H "Content-Type: application/json" \
  -d '{"model":"agent/embed-small","input":"ping"}' \
  | jq '{model, dims: (.data[0].embedding|length), tokens: .usage.total_tokens}'
# → { "model": "text-embedding-3-small", "dims": 1536, "tokens": 1 }
```

If `dims` is 1536 and `model` is `text-embedding-3-small`, the alias resolved and metering ran.

> **No MCP/CLI tool yet** (gap 4) — embeddings are **HTTP-only**. Use the raw endpoint or the
> OpenAI SDK pointed at the gateway. A `gate_embed` tool is a tracked follow-up. See
> [gaps.md](gaps.md).
