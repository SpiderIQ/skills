# Scripts

Quality gates and token-saving utilities that the `spiderpublish` skill's
`SKILL.md` references via `<HARD-GATE>` blocks. **Run these scripts; paste
the output verbatim into the conversation.** Don't paraphrase — the whole
point is auditable enforcement.

This pattern is borrowed directly from HeyGen's Hyperframes (commit
`190f1ec`): _"language-only enforcement is selectively interpretable by
the agent under ship pressure."_ Three rounds of prose-only rules failed
there. Scripts succeeded.

## Why scripts, not prose

| Prose rule | Script equivalent | Token savings |
|---|---|---|
| "Always verify tenant scope before mutating" | `verify-tenant-scope.sh` | ~600/session (eliminates re-derivation) |
| "Use the Phase 11+12 dry_run flow on prod" | `dry-run-then-confirm.py` | ~1200/mutation (no schema lookup, error envelopes parsed) |
| "Read the decision tree, pick a recipe" | `find-tool-for-intent.sh` | ~6000 (skip full SKILL.md load) |

## Inventory (v0.2.0)

### `verify-tenant-scope.sh`

**When:** before any mutation against the SpiderPublish API.

```bash
./scripts/verify-tenant-scope.sh
# {"ok":true,"project_id":"cli_xxx","spideriq_json":"/path/spideriq.json","verified_at":"..."}
```

Exit 0 → safe to mutate. Exit 1 → MISMATCH; stop. Exit 2 → no `spideriq.json` (run `spideriq use <project>` first). Exit 3 → no PAT.

### `dry-run-then-confirm.py`

**When:** any destructive op against a production tenant (delete, publish, unpublish, apply-theme, deploy, archive, settings update).

```bash
./scripts/dry-run-then-confirm.py \
  --url https://spideriq.ai/api/v1/dashboard/projects/$PID/content/deploy \
  --method POST \
  --description "Deploy demo.spideriq.ai to production" \
  --body '{}' \
  --auto
```

Wraps the two-phase `?dry_run=true` → `?confirm_token=cft_…` flow. Handles 410 (expired), 409 (consumed), 403 (mismatch) with clear messages and distinct exit codes.

### `find-tool-for-intent.sh`

**When:** the user asks for something and you're not sure which recipe to load.

```bash
./scripts/find-tool-for-intent.sh "add a contact form to the home page"
# {"matches": [{"score": 3, "goal": "...", "recipe": "recipes/booking/build-form.md"}, ...]}
```

Returns top 3 recipe candidates by keyword overlap. ~50-token alternative to loading the full SKILL.md body when you already know roughly what the user wants.

## Authoring rules for new scripts

1. **Structured output.** Always emit JSON on stdout. Errors to stderr. Agents need parseable output.
2. **Distinct exit codes.** 0 = success, 1+ = specific failure modes. Codes documented in the script's docstring.
3. **No hidden state.** Scripts shouldn't write outside `/tmp/`. State changes happen through the explicit SpiderPublish API.
4. **Token economy.** A script that saves <100 tokens vs. the alternative isn't worth shipping. Aim for ≥500.
5. **Cross-runtime.** Bash + Python only. No Node, no Deno. Both are present on every supported runtime host.
6. **Document the WHY.** The script's docstring explains the failure mode it prevents. Future contributors need that context to maintain it.

## Pattern source

- HeyGen Hyperframes commit [`190f1ec`](https://github.com/heygen-com/hyperframes/commit/190f1ec) — the original "move enforcement into scripts" pivot
- HeyGen Hyperframes `scripts/` directory — `w2h-verify.mjs`, `lint_source.py`, `contrast-report.mjs`, `animation-map.mjs`
