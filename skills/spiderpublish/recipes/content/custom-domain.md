# recipes/content/custom-domain

Connect a custom domain (e.g. `acme.com`, `blog.acme.com`) to a SpiderPublish tenant. Two onboarding paths — CF-for-SaaS vs in-account-zone — picked by who owns the Cloudflare zone for the domain.

## When to use

- A tenant wants `acme.com` (instead of `acme.sites.spideriq.ai`) to serve their SpiderPublish site.
- You're moving an existing site from a different host to SpiderPublish and need to swap DNS without downtime.
- You're adding a second domain (e.g. `acme.com` + `www.acme.com` + `acme.co.uk`) to one tenant.

This is a **two-step** workflow: (1) register the domain with SpiderPublish, (2) verify DNS. Until verification succeeds, the domain doesn't route traffic.

## Prerequisites

1. **Tenant scope verified.** Run `./scripts/verify-tenant-scope.sh` (exit 0 = safe).
2. **You can change DNS for the domain.** If the tenant owns the registrar / DNS provider, they need to add a CNAME or move the zone. If they can't, this recipe stops at step 1.
3. **Decide the path: in-account vs CF-for-SaaS.** See "The two paths" below.

## The two paths

The choice depends on **who owns the Cloudflare zone for the domain**.

| Path | When | DNS step |
|---|---|---|
| **A — In-account zone** | SpiderIQ owns the Cloudflare zone (rare — only for sub-domains of `spideriq.ai`-adjacent zones we manage) OR you've moved the customer's zone into the SpiderIQ Cloudflare account | A Worker Route is auto-bound on the zone. No DNS change needed beyond pointing the domain at our nameservers. |
| **B — CF-for-SaaS** | The customer owns their Cloudflare zone (most common path for client domains) | Customer adds a CNAME (`acme.com → <something>.spideriq.ai`). SpiderPublish registers the hostname with CF-for-SaaS, which negotiates the TLS cert + edge routing. |

**Don't register both for the same hostname.** It silently produces CF 522s (the edge can't decide which Worker to dispatch to). If you don't know which path applies, ask the SpiderIQ team — they own the call.

Full breakdown: catalog/CLAUDE.md → "Two domain onboarding paths".

## The 4-call path

```
1. content_list_domains             — see what's already registered
2. content_add_domain               — register the new hostname
3. (DNS step OUTSIDE SpiderPublish)  — customer adds the CNAME / moves the zone
4. content_verify_domain            — server checks DNS; on success, the domain serves traffic
```

Optionally: `content_set_primary_domain` after verify, to make this domain the canonical one (the one `form_preview_url` and other URL-builders use as the host).

### 1. List existing domains

```
content_list_domains()
// → [
//   { id, host: "<tenant>.sites.spideriq.ai", is_primary: true, verified_at: "...", verification_method: "auto" },
//   { id, host: "demo.acme.com", is_primary: false, verified_at: null, verification_method: "cname" }
// ]
```

Every tenant starts with `<tenant>.sites.spideriq.ai` (auto-verified). You're adding new entries.

### 2. Register the new domain

```
content_add_domain({ domain: "acme.com" })
// → {
//     id, host: "acme.com",
//     verified_at: null,
//     verification_method: "cname",                 // OR "in_account" depending on path
//     verification_token: "spideriq-verify-...",     // sometimes needed for TXT-record path
//     cname_target: "tenant-cli_xxx.sites.spideriq.ai"   // the CNAME target the customer must add
//   }
```

The response tells you what DNS record the customer needs to add. For Path B (CF-for-SaaS), you'll typically get a `cname_target` to point `acme.com` at. For Path A (in-account zone), there's no DNS change beyond pointing the zone at our nameservers.

**`content_add_domain` is NOT gated.** It mutates immediately. (You can't "add" a domain wrong — it's just a row in `content_domains`; verification is what gates routing.)

### 3. DNS step (customer-side, outside SpiderPublish)

Hand the `cname_target` (or `verification_token` if TXT-based) to the customer:

> "Please go to your DNS provider and add a CNAME record:
> - Name: `acme.com` (or `@` for the apex)
> - Type: `CNAME`
> - Value: `tenant-cli_xxx.sites.spideriq.ai`
> - TTL: 300 (5 min)"

Apex domain caveat: many DNS providers don't allow CNAME on the apex (`acme.com`). Workarounds:
- Cloudflare DNS: CNAME flattening — supported automatically.
- Other providers: use ALIAS or ANAME if available, or a redirect from apex to `www.`.
- If neither works, add `www.acme.com` as the primary and set up an apex-to-www redirect.

DNS propagation: typically <5 min globally; can take up to 48 hours on stale resolvers.

### 4. Verify

```
content_verify_domain({ domain: "acme.com" })
// → { success: true, host: "acme.com", verified_at: "2026-05-24T...", cname_observed: "tenant-cli_xxx.sites.spideriq.ai" }
```

If `success: false`, the response carries why:

| Reason | What to fix |
|---|---|
| `cname_mismatch` | DNS still points at the old host. Wait for propagation (re-check in 5-10 min). |
| `txt_missing` | TXT-based verification — customer hasn't added the `spideriq-verify-...` TXT record yet. |
| `cf_saas_pending` | CF is still negotiating the TLS cert (15-60s typical). Re-check in 30s. |
| `no_authority` | The PAT scope doesn't own this domain. Check tenant binding. |

Verification is idempotent — call it as often as needed until it succeeds.

### 5. (Optional) Set primary

```
content_set_primary_domain({ domain: "acme.com" })
// → { primary: "acme.com", was_primary: "<tenant>.sites.spideriq.ai" }
```

The primary domain is what `form_preview_url` and other URL-builders use as the host. It's also what `content_settings.canonical_url` defaults to for SEO `<link rel="canonical">` tags. Set it once you've verified — otherwise visitors hit the new domain but `<canonical>` still points at the old one.

## Verify (the live test)

After verify + set-primary, in a separate shell:

```bash
curl -sI https://acme.com/
# Should return HTTP/2 200, server: cloudflare, cf-ray: <ray>
```

If you get a 522 or 525, double-check you haven't registered the hostname on both paths (in-account zone AND CF-for-SaaS). One-only.

Visual check on the homepage:

```
content_visual_check({ page_url: "https://acme.com/", viewport: "desktop" })
```

## Remove a domain

```
content_delete_domain({ domain: "old.acme.com" })
// → { success: true, message: "Domain 'old.acme.com' removed" }
```

This unbinds the Worker Route + removes the row. Traffic to the hostname will start hitting the customer's DNS fallback (usually a 404 from their previous host, or NXDOMAIN if the CNAME is also removed).

**Opt-in dry_run** is not currently exposed on delete-domain — the operation is reversible (re-add + re-verify) so the safe-default isn't there. Be careful with primary domains; deleting the primary fails the request (re-assign primary first).

## Apex + www together (the canonical pattern)

For most customers, register BOTH the apex (`acme.com`) and the `www` subdomain (`www.acme.com`). Set the apex as primary. The Liquid renderer's request handler redirects `www.acme.com/<path>` → `acme.com/<path>` (301) when primary is set.

```
content_add_domain({ domain: "acme.com" })
content_add_domain({ domain: "www.acme.com" })
# customer adds CNAMEs for both
content_verify_domain({ domain: "acme.com" })
content_verify_domain({ domain: "www.acme.com" })
content_set_primary_domain({ domain: "acme.com" })
```

## Anti-patterns

1. **Registering the same hostname on both in-account + CF-for-SaaS.** Silent CF 522. Pick ONE path; if you don't know which, ask SpiderIQ ops.
2. **Skipping verification.** A domain row that's `verified_at: null` doesn't route traffic. Customers occasionally add a CNAME and assume it's done — always run `content_verify_domain` and check `success: true`.
3. **Setting primary before verify.** `content_set_primary_domain` requires the domain to be verified. Returns 422 otherwise.
4. **Trying to delete the primary domain.** Re-assign primary to another verified domain first, then delete.
5. **Adding CNAME records when the customer's DNS provider doesn't support CNAME-on-apex.** Use CNAME flattening (Cloudflare DNS), ALIAS / ANAME (other providers), or apex-to-www redirect as fallback.
6. **Assuming "domain verified" means the SITE is live there.** It means CF will route traffic to your tenant — but the tenant's site needs `content_deploy_site_production` to have actual content. Deploy after first domain setup. See [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md).

## See also

- [`apply-theme.md`](apply-theme.md) — apply a theme before pointing real traffic
- [`landing-page.md`](landing-page.md) — make sure the tenant has a published home page before customers land
- [`../reference/deploy-protocol.md`](../reference/deploy-protocol.md) — the deploy that pushes content to the verified domain
- [`../../_shared/auth.md`](../../_shared/auth.md) — PAT auth
- catalog/CLAUDE.md → "Two domain onboarding paths" — canonical internal guide
- catalog/DEPLOYMENT.md — which CF Worker / Dispatcher route serves which hostname (Rule 68: DEPLOYMENT.md wins for routing questions)
