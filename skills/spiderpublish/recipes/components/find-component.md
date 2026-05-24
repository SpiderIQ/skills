# recipes/components/find-component

Look up a component by slug — one call, no pagination. The "don't paginate" recipe.

## When to use

- You know (or strongly suspect) the slug of the component you want (`sys-hero-split`, `acme-pricing-table`, etc.).
- You're about to insert a component into a page block (`type: "component", component_slug: "..."`) and need its `props_schema` first.
- You want to verify a component exists + is published before depending on it.
- You're discovering what `component_version` is current.

If you don't know any slug + need to browse → see "Browsing when you don't know the slug" below.

## The 1-call path (when you know the slug)

```
content_get_component_by_slug({ slug: "sys-hero-split" })
// → {
//     id, slug, name, version: "1.2.0", kind: "static",
//     html_template, css, js,
//     props_schema: { type: "object", properties: {...}, required: [...] },
//     default_props,
//     dependencies: [],
//     description, category: "hero",
//     status: "published",
//     is_global: true,
//     ...
//   }
```

That's it. One call, returns the whole component including `props_schema` so you know what to pass when you insert.

**Optional version pin** — defaults to latest published:

```
content_get_component_by_slug({ slug: "sys-hero-split", version: "1.1.0" })
```

## Browsing when you don't know the slug

```
content_list_components({
  category: "hero",            # optional filter — one of: hero, cta, faq, pricing, features, testimonials, contact_form, footer, header, gallery, stats, custom
  status: "published",          # optional filter — typically "published" for usable components
  include_global: true,         # include the system-shipped `sys-*` components, not just your tenant's
  limit: 50                     # default 50; max effective ~200 before truncation
})
// → [
//   { id, slug: "sys-hero-split",     name: "Hero — split image+text", category: "hero", version: "1.2.0", status: "published", is_global: true },
//   { id, slug: "sys-hero-centered",  name: "Hero — centered", ... },
//   { id, slug: "acme-hero-portrait", name: "Acme portrait hero", is_global: false, ... }
// ]
```

`is_global: true` = shipped with the platform (system components, prefixed `sys-`). Available to every tenant.
`is_global: false` = your tenant authored it (or another tenant if it's been shared).

Filter chain:
- `category` narrows by domain.
- `include_global: false` if you only want your tenant's authored components.
- `status: "published"` excludes drafts.

Once you've found the right one, grab its `slug` and call `content_get_component_by_slug` for the full record.

## Components vs marketplace sections

There's a related-but-distinct tool: `content_list_marketplace_components` returns components flagged for the marketplace UI (`marketplace_featured`, `marketplace_category`, with thumbnails). Different surface — marketplace is the "browse + insert into a page" UX, while `content_list_components` is the lower-level catalog.

| Tool | Returns | When |
|---|---|---|
| `content_get_component_by_slug` | One component, fully populated | You know the slug |
| `content_list_components` | Tenant + global components catalog | Browsing without slug |
| `content_list_marketplace_components` | Components flagged for marketplace UI (`marketplace_featured`, thumbnails, categories) | Building a marketplace-style picker |
| `marketplace_search` | Free-text search across marketplace catalog | Natural-language discovery |

For agentic flows, `content_get_component_by_slug` is the high-value tool — one call, structured response, no pagination. The other three exist for browse + discovery surfaces.

## Pin a specific version

`content_get_component_by_slug` defaults to the latest published version. To pin:

```
content_get_component_by_slug({ slug: "sys-hero-split", version: "1.1.0" })
```

`content_list_component_versions({ slug })` returns the full version history:

```
content_list_component_versions({ slug: "sys-hero-split" })
// → [
//   { version: "1.2.0", published_at: "2026-05-...", changelog: "..." },
//   { version: "1.1.0", published_at: "2026-04-...", changelog: "..." },
//   { version: "1.0.0", published_at: "2026-03-...", changelog: "..." }
// ]
```

When you insert a component into a page block, you can pin the version:

```
{
  type: "component",
  component_slug: "sys-hero-split",
  component_version: "1.1.0",       // pin; omit for latest published
  data: { /* props per the schema */ }
}
```

Without `component_version`, the renderer uses latest published — meaning a future component update (via `component_update_and_propagate` with semver bump) will roll the page forward. Sometimes desirable, sometimes not — pin if you want stability.

## What you can do with the result

Once you have the component record:

- **Read `props_schema`** to know what `data: {...}` shape your `type: "component"` block should pass.
- **Read `default_props`** for example values.
- **Read `dependencies[]`** to know if the component is Tier 3 (needs allowlisted CDN libs). The renderer auto-injects from `content_cdn_allowlist`.
- **Read `kind`** to know whether the component is `static` / `interactive` / `dynamic` / `extension` — affects hydration.
- **Read `_audit`** (on get) for latent issues (Tier 3 with missing dep, etc).

## Anti-patterns

1. **Paginating `content_list_components({limit: 500})` to "find by slug."** Use `content_get_component_by_slug` — one call, faster, never truncated.
2. **Searching by `name`.** `content_list_components` doesn't filter by name; use `marketplace_search` for free-text, or `category` to narrow.
3. **Assuming `is_global: true` means "always available."** It is, in terms of read access — but you can't `content_publish_component` / `content_delete_component` on a global one unless you're the marketplace authoring brand (`cli_spideriq_templates`). Your tenant can use it; not edit it.
4. **Pinning `component_version` on a fast-evolving component.** If the component author pushes a critical fix, your pinned page misses it. Pin only when you've seen instability OR when you need bug-compatible behaviour.
5. **Inserting a Tier 3 component without checking `dependencies[]`.** The renderer fails silently in dev if a dep doesn't resolve. Check the result of `content_get_component_by_slug` includes `dependencies: ["gsap", ...]` AND each key is in `content_list_cdn_allowlist()`.

## See also

- [`create-component.md`](create-component.md) — author your own Tier 1-4 component
- [`../content/landing-page.md`](../content/landing-page.md) — insert a component into a page block
- [`../reference/tool-surface.md`](../reference/tool-surface.md) — one-shot vs choreography (this recipe is the canonical "use the one-shot")
- [`../reference/block-types.md`](../reference/block-types.md) — `type: "component"` block shape (with top-level `component_slug`)
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
