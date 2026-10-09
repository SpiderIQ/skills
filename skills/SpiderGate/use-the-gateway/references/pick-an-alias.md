# Pick a task alias

A **task alias** (`spideriq/coding`, `spideriq/fast`, …) tells SpiderGate *what kind
of task* this is, and SpiderGate maps it to a pool of real models chosen for that
task. Each request goes to the least busy slot in the pool: the slots are not a
ranked list. Sending an alias — instead of a bare model id like `gpt-4o` — buys you
the pool, retries, and for most aliases a hand-over to another alias. **Prefer an alias; pin a model only when
you genuinely need that exact one.**

There are **two deliberately separate families.** Pick the family first, then the task.

## `spideriq/*` — for WORKERS (single-shot, batch, cost-dominated)

Biased toward **free-tier** providers (Groq, Mistral-free, Cerebras-free) because
cost dominates at batch scale. Use for scraping post-processing, extraction, classification,
one-shot transforms. (OpenRouter `:free` was retired from this family in 2026-06 — it can't do
tool calls; paid OpenRouter is kept for `spideriq/vision` only.)

| Alias | Task |
|---|---|
| `spideriq/coding` | code gen, debugging |
| `spideriq/extraction` | pull fields from text |
| `spideriq/classification` | categorize |
| `spideriq/summarization` | summarize |
| `spideriq/translation` | translate |
| `spideriq/fast` | low-latency utility |
| `spideriq/free` | zero-cost |
| `spideriq/chat` | conversational |
| `spideriq/research` | long-context analysis |
| `spideriq/lead-analysis` | B2B lead analysis, CHAMP scoring (the designated lane for PII) |
| `spideriq/creative` | SEO / creative writing |
| `spideriq/vision` | image understanding |

This table names no model. The slots behind an alias are edited as providers
change, so read them live (step 1 below).

## `agent/*` — for LIVE conversational agents (multi-turn, uptime-dominated)

Biased toward **subscription primaries** (Codex Pro flat-rate, MiniMax Token Plan)
where multi-turn coherence + uptime beat per-token cost. Use for chat personas,
Telegram/Discord/dashboard agents.

`agent/chat`, `agent/tool-use`, `agent/coding`, `agent/planning`, `agent/creative`,
`agent/vision`, `agent/research`, `agent/fast`. When its own pool cannot serve, an `agent/*`
alias hands over to `agent/chat`, and `agent/chat` to `agent/tool-use`. `agent/vision` has no
hand-over: a pool of text models would answer about an image it never received. The same is
true of `spideriq/vision` and `spideriq/design-vision`.

> **There is NO Anthropic model in any `agent/*` alias** — subscription routing is
> ToS-banned. Don't ask the gateway for Claude via an alias.

## Steps

1. **List the live aliases + the slots behind each** (`models` in each entry; slot order is
   display order, not priority):

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

- **The models behind an alias change.** Providers delist models and slots are edited. The
  alias keeps its name, so don't hard-code "spideriq/coding == model X." Read `model`
  on the response to see what actually answered.
- **A bare model id has no pool.** `model: "gpt-4o"` pins exactly that model — no other
  slot to route to, and no hand-over to another alias. Only pin when you need that specific model's behavior.
- **For one model from the catalog, send its `call_as`, not its `id`.** Every catalog
  row carries `call_as`: the exact `model` string for that row right now, or `null`.
  If it is `null`, the shared pool cannot serve that row now. A Codex row's
  `id` is refused; its `call_as` is `codex/<model_id>`. `listModels` rows carry no
  `call_as`, so read it with the `model-catalog` skill (`listCatalog` / `getModel`).
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
