# Read the model's schema, then pre-flight — undeclared params vanish

**What happens.** SpiderGate media generation is *schema-aware*: every model row
carries an `inputs` map declaring exactly which params it accepts (`prompt`,
`aspect_ratio`, `guidance_scale`, `seed`, `voice`, `speed`, …), with each param's
type / enum / min–max. The endpoint forwards **only** declared keys to the provider —
`declared = set(descriptor.inputs)` — and **silently drops** anything else (SF-16.1b).
No error. The generation succeeds; it just ignored the params it didn't recognize.

**Why it bites.** Agents carry habits across models:

- OpenAI-image reflexes on a fal model: `size` / `quality` / `cfg_scale` → all dropped
  (fal declares `aspect_ratio` / `guidance_scale`, no `quality`). The image renders,
  but at the wrong shape and default guidance — and you paid for it.
- `input` on a TTS model that declares `text` → dropped → no text → 400.
- A dropped `seed` means the result is **not reproducible**, even though you "set" it.

**The discipline (two steps, non-negotiable).**

1. **Discover before you generate.** `gate_media_models` → read the target model's
   `inputs`. That map is the contract.
2. **Make it a check, not a hope.** Run the pre-flight and paste its report:
   ```
   node scripts/validate-media-params.mjs --model fal/flux-dev --params '{...}'
   →  each param HONORED / DROPPED / OUT-OF-ENUM / OUT-OF-RANGE / MISSING-REQ
   →  exits non-zero if anything is wrong — fix BEFORE the billed call.
   ```
   This is the difference between *claiming* schema-awareness and *proving* it. A prose
   "remember to check the schema" is skippable under ship pressure; a script that exits 1
   and names `cfg_scale — DROPPED` is not.

**Sibling silent traps on this surface** (each also a MUST/WARN in the skill):

- **`billed_usd: 0` is BYOK, not free.** Generation uses the brand's own provider key;
  BYOK is billed monthly by key-count, not per request. Don't report "free."
- **Video is synchronous and slow.** The provider is polled server-side (up to ~20 min
  for veo); a multi-minute call is normal, not a hang. Don't retry a running request —
  you'll pay twice.
- **A 200 isn't proof.** The deliverable is the stored URL; fetch it and confirm
  `content-type: image|video|audio/*` (`verify-media-result.mjs`) before reporting success.

**Provenance.** SF-17 (schema-aware media generation for agents), built on the SF-16
settings-schema engine. The drop-undeclared behavior is SF-16.1b
(`media_generation.py`); the Bearer surface is `app/api/v1/gate/media.py`.
