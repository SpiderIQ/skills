---
name: content-platform
version: "1.4.0"
description: >
  Multi-tenant content management — pages, blog posts, docs, navigation menus, site settings, custom domains, and reusable UI components with 4-tier interactivity (static, scoped JS, CDN libraries, React/Vue/Svelte) and automatic Shadow DOM isolation. Content is scoped to a PROJECT (one website) inside the authenticated WORKSPACE (brand/account); omit the project to hit the workspace default, or pass an optional proj_… id (X-Project-Id) to target a specific site. Manage sites with listProjects / createProject.

category: content
requires_auth: true
requires_brand: true
triggers:
  - content page
  - blog post
  - documentation
  - navigation
  - custom domain
  - site settings
  - blog authors
  - content tags
  - blog categories
  - manage posts
  - search posts
  - featured posts
  - ui component
  - shadow dom
  - reusable block
  - interactive component
  - javascript component
  - gsap animation
  - cdn library
  - react component
  - vue component
  - svelte component
  - framework build
  - web component bundle
  - dynamic component
  - data source
  - live collection
  - live data
  - bind data
  - filter posts
client: content-platform
client_version: "1.4.0"
metadata:
  openclaw:
    primaryEnv: OPVS_PAT
---

# content-platform #content #tier3

manage a workspace's own content — pages, blog posts, authors, tags, categories, docs, navigation, domains, settings, deploy, and reusable UI components — scoped to one project (website) inside the workspace

## Workspace vs project (Projects 4c)
A WORKSPACE (cli_… id) is the account/brand; a PROJECT (proj_… id) is one website inside it. Every content method accepts an OPTIONAL `project` (proj_… id) that scopes the call to that site, sent as the X-Project-Id header. Omit it → the workspace's default project (single-site agents keep working unchanged). `listProjects` lists the sites; `createProject` adds one.

/#templates-engine → Liquid template customization and theme management
/#capture-landing-page → screenshot/capture a URL as landing page asset
/#scrape-website-extract-leads → extract data FROM external websites

## Chain
createPost → publishPost (publish when ready)
createAuthor → createPost (assign author to post)
createCategory → createTag → createPost (set up taxonomy before writing)
updateSettings → contentDeploySite (deploy after config changes)
createComponent → publishComponent → use in page blocks via component_slug
createComponent → listComponentVersions (track version history)
listCdnAllowlist → createComponent with dependencies (Tier 3 rich animations)
createComponent with framework → publishComponent → getBuildStatus (poll until success)
getBuildStatus → rebuildComponent (if build failed)
listDataSources → listDataSourceItems (browse sources, then preview the rows before binding)
listDataSources → createComponent kind=dynamic with sources[] → page block (live, filtered data anywhere)

## Pitfalls
- Omitting `project` writes to the workspace DEFAULT project — to build a second site pass project=proj_…, or content lands on the wrong website
- The project arg only accepts proj_… ids — a cli_… value is the workspace, not a project
- Posts need publishPost after createPost — createPost saves as draft
- Categories support hierarchy via parent_id — create parent first
- Search and featured endpoints are public (no auth) — use for reader-facing features
- Always deploy after content changes — contentDeploySite pushes to edge
- Components need publishComponent before they can be used in page blocks
- Component CSS is auto-isolated via Shadow DOM — no need for manual namespacing
- Use props_schema (JSON Schema) so other agents know what data a component accepts
- Component JS (Tier 2) receives root (shadowRoot) and props — use root.querySelector(), never document.querySelector()
- CDN dependencies (Tier 3) must reference keys from the allowlist — check listCdnAllowlist first
- Framework components (Tier 4) build asynchronously on publish — poll getBuildStatus until success
- Tier 4 publish returns 202 (building), not 200 — poll build-status before using in pages
- kind='dynamic' REQUIRES block_type + js_runtime + a non-empty sources[] together — omitting any → 422 (chk_components_kind). Use js_runtime='none' for a pure-Liquid (server-rendered) dynamic component.
- Filters run SERVER-SIDE (the source binding's default_filter, or the listDataSourceItems query) — a client-side Liquid {% if %} only filters rows already fetched, it does NOT re-query the source
- Binding a singleton source (idap.lead) to a list → 422 — use it on a /lp/ dynamic-landing page as `lead`, not via a dynamic component
- idap.* collection sources (countries/cities/streets/businesses) return 501 today (Phase 2) — posts/authors/categories/tags/changelog are live now
- Inside a dynamic component the bound+filtered rows arrive as `items`; the global `{{ posts }}`/`{{ authors }}`/… collections are ALSO available in every component/template (unfiltered) — use `items` for the component's declared binding, the globals for a simple list

## Live Data — collections in every component (Live Data Everywhere)
Live CMS collections are fetched from the API at request time and available to EVERY page template AND component, so you can build any data-driven widget anywhere — recent posts on the homepage, a changelog feed in a footer, authors on a contact page, a filtered card grid. No hardcoding, never stale.

- Available everywhere (as globals): `posts`, `authors`, `categories`, `tags`, `changelog`, plus `lead` on /lp/ dynamic-landing pages only. Each defaults to `[]` when empty, so `{% for %}` is always a safe no-op. A collection is only fetched if a component on the page references it by name (cost gate).
- Use in any template/component: `{% for post in posts %}<a href="/blog/{{ post.slug }}">{{ post.title }}</a>{% endfor %}`, filter with `{% assign featured = posts | where: 'is_featured', true | limit: 3 %}`.
- For a reusable, server-filtered widget, build a kind='dynamic' component (see chain above). Use `listDataSources` to discover source_ids + fields, `listDataSourceItems` to preview rows.

## Methods

- `listProjects()` — List the projects (websites) in the workspace. Use a returned proj_… id as the `project` arg on any content method.
- `createProject(name, slug?)` — Create a new project (website) in the workspace. Subject to the plan's max_deployed_sites cap.
- `listPages(status?, limit?)` — List content pages (including drafts).
- `createPage(title, slug?, blocks?, template?, seo_title?, seo_description?)` — Create a new content page with blocks.
- `getPage(page_id)` — Get a content page by ID (includes blocks, SEO, status).
- `updatePage(page_id, title?, slug?, blocks?, seo_title?, seo_description?)` — Update a content page.
- `deletePage(page_id)` — Archive/delete a content page.
- `publishPage(page_id)` — Publish a draft page (creates a version snapshot).
- `unpublishPage(page_id)` — Revert a published page to draft.
- `listPosts(status?, tag?, limit?)` — List blog posts.
- `createPost(title, slug?, body?, excerpt?, tags?, cover_image?)` — Create a blog post (Tiptap JSON body, metadata, tags).
- `publishPost(post_id)` — Publish a blog post. — publish a draft post — makes it visible on the public site
- `getPost(post_id)` — Get a blog post by ID (includes body, tags, author, status).
- `updatePost(post_id, title?, slug?, body?, excerpt?, tags?, cover_image?, author_id?, category_id?, featured?)` — Update a blog post (title, body, excerpt, tags, author, category, featured).
- `deletePost(post_id)` — Delete a blog post.
- `unpublishPost(post_id)` — Revert a published post to draft.
- `updatePostStatus(post_id, status)` — Update post status (draft, published, archived).
- `searchPosts(q, limit?)` — Search published posts by keyword (public endpoint).
- `featuredPosts(limit?)` — Get featured blog posts (public endpoint).
- `listAuthors()` — List blog authors.
- `createAuthor(full_name, slug?, avatar_url?, bio?, email?, role?, agent_type?, country?, city?)` — Create a blog author profile.
- `getAuthor(author_id)` — Get an author profile by ID.
- `updateAuthor(author_id, full_name?, slug?, avatar_url?, bio?, email?, role?, agent_type?, country?, city?)` — Update an author profile.
- `deleteAuthor(author_id)` — Soft-delete an author profile.
- `listTags()` — List blog tags (includes post count).
- `createTag(name, slug?, description?)` — Create a blog tag.
- `updateTag(tag_id, name?, slug?, description?)` — Update a blog tag.
- `deleteTag(tag_id)` — Delete a blog tag.
- `listCategories()` — List blog categories (supports hierarchy).
- `createCategory(name, slug?, description?, parent_id?, sort_order?)` — Create a blog category (supports hierarchy via parent_id).
- `updateCategory(category_id, name?, slug?, description?, parent_id?, sort_order?)` — Update a blog category.
- `deleteCategory(category_id)` — Delete a blog category.
- `getDocsTree()` — Get documentation tree structure.
- `createDoc(title, slug?, body?, parent_id?)` — Create a documentation page.
- `searchDocs(domain, query, page?, page_size?)` — Docs-as-MCP: full-text keyword search across ANY published docs site by domain (public; no auth). Returns ranked title/path/snippet hits.
- `semanticSearchDocs(domain, query, top_k?)` — Docs-as-MCP: meaning-based (vector) search across a published docs site by domain. Returns the most similar passages with source paths.
- `askDocs(domain, query, top_k?)` — Docs-as-MCP: a grounded, [n]-cited answer over a published docs site by domain. METERED against the site owner's Docs-AI plan + rate-limited; reserve for real questions.
- `getDoc(domain, path)` — Docs-as-MCP: fetch one published doc page by full path (the part after /docs/) from a docs site by domain.
- `getNavigation(location)` — Get navigation menu (header, footer, docs_sidebar).
- `updateNavigation(location, items)` — Update navigation menu items.
- `getSettings()` — Get content settings (site name, SEO defaults, analytics, colors).
- `updateSettings(settings)` — Update content settings.
- `listDomains()` — List custom domains configured for the content site.
- `addDomain(domain)` — Add a custom domain. Requires DNS verification after adding.
- `verifyDomain(domain)` — Verify DNS for a custom domain (checks CNAME/A record).
- `setPrimaryDomain(domain)` — Set a verified domain as the primary domain.
- `deleteDomain(domain)` — Remove a custom domain.
- `listComponents(category?, status?, include_global?, limit?)` — List UI components (reusable blocks with Shadow DOM isolation).
- `createComponent(slug, name, html_template?, css?, js?, dependencies?, framework?, source_code?, description?, version?, category?, props_schema?, default_props?, thumbnail_url?, is_global?, tags?, kind?, block_type?, js_runtime?, sources?)` — Create a component. Tier auto-detected: html only=Tier 1, +js=Tier 2, +dependencies=Tier 3, +framework+source_code=Tier 4. For LIVE DATA: pass kind='dynamic' + block_type + js_runtime + a non-empty sources[] (each: {source_id, role?, default_filter?, default_sort?, default_limit?}) to bind server-filtered collections; the rows render as `items`.
- `getComponent(component_id)` — Get a UI component by ID (includes template, CSS, JS, dependencies, framework, build status).
- `getComponentBySlug(slug, version?)` — Get a UI component by slug (optionally a specific version).
- `updateComponent(component_id, name?, html_template?, css?, js?, dependencies?, framework?, source_code?, description?, category?, props_schema?, default_props?, thumbnail_url?, tags?)` — Update a UI component.
- `deleteComponent(component_id)` — Delete a UI component.
- `publishComponent(component_id)` — Publish a component. Tier 4 returns 202 (async build) — poll getBuildStatus.
- `archiveComponent(component_id)` — Archive a component (removes from active use).
- `listCdnAllowlist()` — List available CDN libraries for Tier 3 (keys, names, URLs, categories).
- `getBuildStatus(component_id)` — Get Tier 4 build status (none, building, success, failed).
- `rebuildComponent(component_id)` — Trigger rebuild for a failed Tier 4 component.
- `listComponentVersions(slug)` — List all versions of a component by slug.
- `listDataSources(parent_id?)` — List every registered content data source for binding kind='dynamic' components, with each source's filterable/sortable fields. v1: posts, authors, categories, tags, changelog. idap.* list → 501 (Phase 2); idap.lead is a singleton (reaches /lp/ as `lead`). Call BEFORE creating a dynamic component.
- `listDataSourceItems(source_id, filter?, sort?, limit?, offset?, fields?)` — Fetch filtered/sorted/paginated rows from one source (the same door a dynamic component binds to) — preview rows before wiring a component. Returns { items, total, source_id }. Filters are SERVER-SIDE. Singleton → 422; idap.* → 501 (Phase 2).
