## opvs-admin

The OPVS agent platform's own admin surface. 37 methods covering gateway configuration, cron scheduling, skills management, channel bindings, and gateway operations. By far the most powerful skill in the catalog — install with care.

### What this skill does

- **Gateway config** — read/write the OPVS gateway's configuration (model defaults, agent permissions, rate limits).
- **Cron** — schedule recurring agent tasks. List existing crons, create new ones, pause/resume, delete.
- **Skills management** — list installed skills on the gateway, enable/disable, reload after a deploy.
- **Channels** — manage the agent's connected messaging channels (Slack, Telegram, Discord, etc.). Bind, unbind, configure routing.
- **Gateway operations** — restart, drain, health checks. Used during planned maintenance.

### Server-side gating

37 methods is a lot, and not every brand admin should be able to call all of them. SpiderIQ enforces role-based access on the server: super-admin-only methods (e.g. cross-tenant gateway config) refuse if the calling agent's brand role isn't admin enough. The package install provides the surface; the server provides the gate.

### When to call

- Provisioning new agents (cron schedules, channel bindings)
- Maintenance windows (drain → restart)
- Onboarding a new brand (skills enable/disable per the brand's package set)

### When NOT to call

For routine work (sending mail, scraping a site, deploying a page), use the domain-specific skills. opvs-admin is for the platform layer, not the application layer.
