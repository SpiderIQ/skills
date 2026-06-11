# Pick a task alias

A **task alias** (`spideriq/coding`, `spideriq/fast`, …) tells SpiderGate *what kind
of task* this is, and SpiderGate maps it to an ordered chain of real models, biased
for that task. Sending an alias — instead of a bare model id like `gpt-4o` — buys you
the fallback chain, retries, and cost-bias. **Prefer an alias; pin a model only when
you genuinely need that exact one.**

There are **two deliberately separate families.** Pick the family first, then the task.

## `spideriq/*` — for WORKERS (single-shot, batch, cost-dominated)

Biased toward **free-tier** providers (Groq, Mistral-free, OpenRouter `:free`) because
cost dominates at batch scale. Use for scraping post-processing, extraction, classification,
one-shot transforms.

| Alias | Task | Slot-0 model (today) |
|---|---|---|
| `spideriq/coding` | code gen, debugging | Codex `gpt-5.3-codex` → MiniMax M2.5 |
| `spideriq/extraction` | pull fields from text | Groq Llama 3.1 8B (fastest) |
| `spideriq/classification` | categorize | Groq Llama 3.1 8B |
| `spideriq/summarization` | summarize | Groq Scout 17B |
| `spideriq/translation` | translate | Mistral Small |
| `spideriq/fast` | low-latency utility | Groq Llama 3.1 8B (~813 ms) |
| `spideriq/free` | zero-cost | Groq Llama 3.1 8B |
| `spideriq/chat` | conversational | Groq Llama 3.3 70B |
| `spideriq/research` | long-context analysis | Groq Llama 3.3 70B |
| `spideriq/lead-analysis` | B2B lead analysis, CHAMP scoring | **Mistral Codestral (premium — the PII-safe lane)** |
| `spideriq/creative` | SEO / creative writing | Mistral Codestral |
| `spideriq/vision` | image understanding | Mistral Pixtral |

## `agent/*` — for LIVE conversational agents (multi-turn, uptime-dominated)

Biased toward **subscription primaries** (Codex Pro flat-rate, MiniMax Token Plan)
where multi-turn coherence + uptime beat per-token cost. Use for chat personas,
Telegram/Discord/dashboard agents.

`agent/chat`, `agent/tool-use`, `agent/coding`, `agent/planning`, `agent/creative`,
`agent/vision`, `agent/research`, `agent/fast`. Every `agent/*` alias falls through to
`agent/chat` when its own chain exhausts.

> **There is NO Anthropic model in any `agent/*` alias** — subscription routing is
> ToS-banned. Don't ask the gateway for Claude via an alias.

## Steps

1. **List the live aliases + their chains** (don't trust this table for slot-0 — models
   get re-bound as providers change models):

   ```bash
   curl -s https://spideriq.ai/api/gate/v1/aliases \
     | python3 -c "import json,sys; [print(a['id'], '→', a.get('use_case','')) for a in json.load(sys.stdin)['data']]"
   ```

2. **Pick the family** — batch/worker task → `spideriq/*`; live multi-turn agent → `agent/*`.

3. **Pick the task** — match the verb (extract / classify / summarize / code / chat / analyze).

4. **Apply the HARD-GATE** — does the payload contain PII (names, emails, phones, account
   data)? If yes, you may NOT use `spideriq/fast`, `spideriq/free`, `spideriq/extraction`,
   `spideriq/classification`, or `spideriq/summarization` (free-tier → may train on data).
   Use **`spideriq/lead-analysis`** (premium, PII-safe) or strip the PII first.

5. **Send it** — see [cost-aware-completion.md](cost-aware-completion.md).

## Gotchas

- **Slot-0 drifts.** Providers delist models (Groq dropped all Kimi/Moonshot models in
  2026-04 — see SpiderGate LEARNINGS #33). The alias keeps working (it falls through), but
  don't hard-code "spideriq/coding == model X." Read `spidergate_metadata.provider_model`
  on the response to see what actually answered.
- **A bare model id loses the chain.** `model: "gpt-4o"` pins exactly that model — no
  fallback, no cost-bias. Only pin when you need that specific model's behavior.
- **`spideriq/vision` / `agent/vision`** are the only image-capable aliases. MiniMax has no
  working vision model (200s but ignores the image — LEARNINGS #34); vision routes to Pixtral.
- **Free-tier ≠ free-quality, but free-tier = trainable.** The privacy risk, not the quality,
  is what the HARD-GATE is about.

## Verify

```bash
# Confirm the alias you intend to use exists and see its chain length:
curl -s https://spideriq.ai/api/gate/v1/aliases \
  | python3 -c "import json,sys; d={a['id']:len(a['models']) for a in json.load(sys.stdin)['data']}; print('spideriq/lead-analysis chain:', d.get('spideriq/lead-analysis'))"
# A number ≥1 → the alias is live. Absent → re-check the name.
```
