## integrations

Third-party integration management at the brand level. 11 tools covering connector discovery, configuration, OAuth flows, and status monitoring.

### What this skill does

- **Discovery** — `list_available_integrations` returns every connector SpiderIQ supports (Slack, Google Workspace, GitHub, HubSpot, Salesforce, etc.). `get_integration_info` returns the auth requirements, scopes needed, and capability surface for one specific integration.
- **Installed integrations** — `list_installed_integrations`, `get_installed_integration`. What's wired up on the active brand right now, with status (`active`, `expired`, `revoked`, `error`).
- **Configuration** — `configure_integration`, `update_integration`. For API-key-based integrations, write the key. For OAuth, kick off the flow.
- **OAuth flows** — `start_oauth`, `complete_oauth`. SpiderIQ-managed OAuth handshake — start returns a redirect URL the agent passes back to a human; complete consumes the callback code.
- **Status + diagnostics** — `check_integration_health`, `refresh_integration`. Verify a connector is still working; force a token refresh.
- **Removal** — `remove_integration`. Disconnect a connector. Two-step preview/confirm by default.

### Brand-level vs user-level

Integrations live at the brand level — every agent on the brand can use them, every agent's calls go through the same connection. This is different from `auth` skill's OAuth methods which operate at the user level (your Google account vs the brand's Google account).

### Typical workflows

- **Onboarding a new brand** — agent provisions every required integration in sequence (Google Workspace OAuth, Slack webhook, GitHub PAT).
- **Periodic health check** — agent runs `check_integration_health` against all installed integrations weekly, flags expirations.
- **Token rotation** — when a connector reports `expired`, agent kicks off `refresh_integration` (or restarts the OAuth flow if the refresh token is gone).
