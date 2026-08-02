# Read usage, cost, and traces

Two scopes of cost visibility:

1. **Per call** — `spidergate_metadata.cost_usd` on the completion response itself
   (see [cost-aware-completion.md](cost-aware-completion.md)). Free, immediate, no extra request.
2. **Aggregate** — the brand-scoped analytics surface under
   `/api/v1/brands/{brand_id}/gate/*` (usage rollups + per-request traces with full
   input/output). These need your **numeric `brand_id`**.

## Steps

1. **Get your `brand_id`.** The analytics endpoints are keyed by the numeric brand id,
   not the `cli_…` workspace slug. If you don't know it, the brand-stats / agents calls
   take it too — get it from your dashboard (Gate → Overview) or your admin. (This is a
   real friction point — see [gaps.md](gaps.md): there is no "usage for the PAT I'm holding"
   convenience endpoint.)

2. **Read aggregate usage / spend:**
   ```bash
   curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/usage?days=7" \
     -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   `days` defaults to 7, max 90. Returns requests + tokens + cost grouped by
   model/provider/day. MCP equivalent: `gate_usage(brand_id, days)`.

3. **List recent traces** (one row per LLM request — timestamp, agent, requested→served
   model, status, latency, tokens, cost):
   ```bash
   curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/traces?status=error&limit=20" \
     -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   Filters: `agent_id`, `model`, `status` (`success`|`error`), `limit`, `offset`. MCP:
   `gate_traces(brand_id, …)`.

4. **Open one trace** for the full span waterfall (auth → route → LLM call → track) and the
   input/output messages:
   ```bash
   curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/traces/$TRACE_ID" \
     -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   MCP: `gate_trace_detail(brand_id, trace_id)`.

5. **Summary stats** (total traces, success/error counts, p95 latency, total cost):
   ```bash
   curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/traces/stats/summary" \
     -H "Authorization: Bearer $SPIDERIQ_PAT"
   ```
   MCP: `gate_trace_stats(brand_id)`.

## Gotchas

- **`client_id` is the identity ground-truth, `brand_id` is the analytics key.** Traces are
  isolated per brand (LangFuse `userId = client_id`); you can only ever read your own brand's
  traces. A wrong `brand_id` returns empty, not another tenant's data.
- **Traces degrade to metadata-only when LangFuse is down.** If the observability backend is
  unreachable, the trace list still returns from `gate_request_logs` (model, tokens, cost,
  latency, status) but **without** the input/output message bodies. A trace with no messages
  isn't a bug — it's the fallback path.
- **No message content in `gate_request_logs`.** The Postgres log table stores metadata only by
  design (storage efficiency); full prompts/responses live in LangFuse. Don't expect to recover a
  prompt from the usage rollup.
- **Per-call cost ≠ sum you'll see instantly in the rollup.** The aggregate is batched; for the
  exact cost of a call you just made, read its `spidergate_metadata.cost_usd` — don't poll `/usage`
  for it.

## Verify

```bash
# A 200 with a data array confirms the analytics surface + your brand_id:
curl -s "https://spideriq.ai/api/v1/brands/$BRAND_ID/gate/traces/stats/summary" \
  -H "Authorization: Bearer $SPIDERIQ_PAT" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('total traces:', d.get('total', d))"
```
