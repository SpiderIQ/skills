# recipes/component-rollback

Revert a component to an earlier version's content AND repoint every consuming page — **one tool call**.

## The one-shot path (v2.88.0+)

```
# First find the target version to roll back to
content_list_component_versions(slug="hero")
# → returns all versions with created_at + status

# Then roll back
component_rollback(
  slug="hero",
  target_version="1.4.0",
  dry_run=true
)
```

Returns a confirm_token. Re-run to apply:

```
component_rollback(
  slug="hero",
  target_version="1.4.0",
  confirm_token="cft_..."
)
```

## What happens server-side

The rollback never mutates history — it **creates a new forward version** that copies the target's content, then repoints consuming pages:

1. Fetches `hero@1.4.0` content (the known-good version).
2. Auto-bumps semver from CURRENT published version (so if current is `1.4.3` and bump is `patch`, new is `1.4.4`).
3. Inserts a new published row: `hero@1.4.4` with `1.4.0`'s content.
4. UPDATEs every page's blocks JSONB to pin `1.4.4`.
5. Returns `{component, rollback: {target_version: "1.4.0"}, affected_pages}`.

The audit trail stays intact — you can always see "v1.4.4 was a rollback of v1.4.0" in the component history.

## When to use this

- Your last `component_update_and_propagate` broke something
- A recent `component_update` introduced a regression you didn't catch before publish
- You want to A/B-compare an old version against the current one

## Common variants

### Staged rollback — revert only one page first

```
component_rollback(
  slug="hero",
  target_version="1.4.0",
  pages=["home"],
  dry_run=true
)
```

Other pages keep their current (broken) pin. Verify the home page rollback works, then call again without `pages` to roll to all.

### Fresh semver branch

```
component_rollback(
  slug="hero",
  target_version="1.4.0",
  bump="minor",  # → creates 1.5.0 instead of 1.4.4
  dry_run=true
)
```

Useful when you want a clean minor-version boundary that marks "rollback happened here."

## Gate action is distinct

A confirm_token issued for `component_rollback` CANNOT be consumed against `component_update_and_propagate` and vice versa. Lock 4 prevents cross-use — you can't accidentally apply a forward-update token to a rollback flow.

## No tenant deploy needed

Same as `component_update_and_propagate`: block-level page content renders live via the content API on next request. Run `content_deploy_site_preview` + `content_deploy_site_production` only if you ALSO changed templates/theme/config.

## Files in this skill

- `SKILL.md` — this file
- `schema.yaml` — Tier 2 tool-sequence for MCP consumers

## See also

- [recipes/component-update-and-propagate](../component-update-and-propagate/SKILL.md) — the forward flow
- [LEARNINGS.md → Component editing](../../../LEARNINGS.md#component-editing)
- [SpiderIQ `/content/help` → `rollback_component`](https://spideriq.ai/api/v1/content/help?format=yaml)
