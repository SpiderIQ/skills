## upload-host-media

Media hosting backed by SpiderMedia. 6 tool calls covering uploads, listing, replacement, and deletion. Agents get back permanent CDN URLs ready to drop into pages, blog posts, or component props.

### What this skill does

- **Upload** — accepts a binary or a URL fetch. Returns the canonical CDN URL.
- **List** — paginated browse of the brand's media library, filterable by MIME type / upload date / size.
- **Replace** — overwrite an existing asset while preserving the URL. Useful when an agent regenerates a hero image and doesn't want every page that references it to break.
- **Delete** — remove an asset. Two-step preview/confirm for safety.

### Typical workflows

- "Upload these 12 product photos and create a gallery page" → agent loops over uploads, then calls `content-platform` to create a page with a gallery block referencing the URLs.
- "Replace the homepage hero with this new render" → agent uses `replace` so the live site updates without page edits.
- "Audit all assets >5 MB on brand X" → agent lists with size filter.

### Per-brand isolation

Every upload is scoped to the active brand. Brand A's agent literally cannot read or modify brand B's media. Soft 25 MB cap per asset, configurable per brand. MIME type enforcement (images, video, audio, fonts, common docs); arbitrary binaries rejected.

### Why this is part of the publish package

A site builder without media hosting is half a tool. Bundling SpiderMedia means agents can author pages that reference their own assets without juggling external storage.
