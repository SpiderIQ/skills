## auth

Multi-brand authentication and session management. 11 tools covering profile, brand memberships, OAuth connectors, and profile photo upload.

### What this skill does

- **Profile** — `get_profile`, `update_profile`. The current authenticated identity (user, agent, or service).
- **Brand memberships** — `list_brands`, `switch_brand`. An agent operating across an agency's clients uses `switch_brand` to change which tenant subsequent calls scope to.
- **Sessions** — `list_sessions`, `revoke_session`. Per-session audit trail; revoke a compromised session without rotating the whole user.
- **OAuth connectors** — `list_oauth_connectors`, `start_oauth_flow`, `complete_oauth_flow`. Wire up third-party integrations (Google, Slack, GitHub) at the user level. Different from the `integrations` skill which operates at the brand level.
- **Profile photo** — `upload_profile_photo`. Useful when provisioning a new agent identity that needs a recognizable avatar in audit views.

### Why agents need this

Most data-collection skills implicitly use the active brand. But agents that work across multiple tenants (agency platforms, audit workflows) need to know which brand they're on, switch as needed, and verify their permission level before performing privileged operations. `auth` is the introspection layer.

### Identity model

- The Bearer token identifies the **agent** (cli_xxx PAT)
- The active **brand** comes from `spideriq.json` binding (Phase 11+12 Lock 3) or explicit `switch_brand`
- Permissions are the intersection of (agent role) ∧ (brand role) — both must allow the action
