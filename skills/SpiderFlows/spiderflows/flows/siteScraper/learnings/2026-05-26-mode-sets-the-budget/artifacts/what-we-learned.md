# `mode` drives pages + AI; `max_pages` can't exceed 50

**Starting point, not ground truth — verify against current code.**

## The two ways people get this wrong

1. They set `max_pages: 100` expecting a deep crawl — and get a `422`, because
   `max_pages` is validated **1–50** on both the API (`SpiderSiteJobPayload`) and
   the flow `input_schema`.
2. They rely on `mode` for a page count and are surprised the AI features came (or
   didn't come) along with it.

## How `mode` actually maps

`mode` is a preset that sets **both** the page budget **and** which AI features
run:

| mode | pages | AI it turns on |
|---|---|---|
| `contacts` | 5 | none |
| `compendium` | 10 | none (just the markdown dump) |
| `leads` | 50 | team + company info |
| `full` | 100 | team + company + pain points + lead scoring |

So `full` is the only way to ask for ~100 pages — **that budget lives in the mode
preset, not in `max_pages`** (which tops out at 50). You can't reach 100 by setting
`max_pages`.

## Adjusting within a mode

- `overrides: { "max_pages": 20 }` — change a mode's page count (still ≤ 50).
- `overrides: { "strategies": ["css", "regex"] }` — change extraction strategies.

## Be explicit when it matters

`mode` is the documented primary knob and the cleanest way to pick a profile. But
if a specific outcome matters — a precise page count, a particular AI feature — set
that knob **explicitly** alongside the mode (`max_pages`, `extract_team`,
`extract_company_info`, `compendium.*`). The explicit fields are always read, so
you're never depending on a preset to imply them. Belt and suspenders: pick the
mode for intent, set the knob for certainty.

## Rule of thumb

- Pick `mode` for the job (contacts / compendium / leads / full).
- Need > 50 pages? That's `mode: full` — not `max_pages`.
- Need a guaranteed page count or AI feature? Set it explicitly; don't infer it
  from the mode.
