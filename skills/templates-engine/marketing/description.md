## templates-engine

The styling and deploy layer of SpiderPublish. 13 tool calls covering Liquid template authoring, theme application, preview rendering, and Cloudflare-edge deployment.

### What this skill does

- **Apply a pre-built theme** — `template_apply_theme` swaps the brand's active theme. Bundled themes ship with the platform; tenants can also fork into their own custom theme.
- **Edit Liquid templates** — `template_upsert` writes a per-tenant template override into the brand's KV namespace. The shared Liquid renderer Worker picks up the change within seconds — no per-tenant npm build.
- **Render a preview** — `template_preview` renders any template with mock data and returns HTML. Lets an agent see the output before deploying. The mock-data shape is deterministic so previews are reproducible.
- **Deploy to Cloudflare edge** — `content_deploy_site` ships the manifest to the edge in 2–5 seconds. `content_deploy_status` polls. Two-step preview/confirm by default — `content_deploy_site_preview` returns a diff + `confirm_token`, `content_deploy_site_production` consumes it.
- **Self-discoverable via `template_get_help`** — returns a YAML reference (~2,867 tokens) covering every content type, block type, Liquid filter, and template structure. An agent that's never seen the platform can learn it from one tool call.

### Typical workflows

- "Apply the 'minimal-dark' theme to brand X" → agent calls `template_apply_theme`, then `content_deploy_site`.
- "Preview the homepage with the new hero block before deploying" → agent calls `template_preview` against the staged template.
- "Roll back yesterday's deploy" — version history exposed via `content_deploy_status` history.

### Architecture

Templates live in per-brand Cloudflare KV. A single shared `liquid-renderer` Worker reads templates + live content from the API at request time. Adding a new template doesn't trigger a new Worker deploy — only the brand's KV gets a new entry. Result: 2-5s deploy times regardless of how many brands are on the platform.
