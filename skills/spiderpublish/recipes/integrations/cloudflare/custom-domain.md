# recipes/integrations/cloudflare/custom-domain

End-to-end: connect a client's custom domain (e.g. `acme.com`) to their SpiderPublish tenant. Cloudflare for SaaS handles the SSL/TLS + edge routing; SpiderPublish writes the dispatch binding. The recipe covers DNS verification, certificate issuance, and the post-attach visual check.

## When to use

- A tenant is moving from `<slug>.sites.spideriq.ai` to their own domain.
- An agency is white-labelling SpiderPublish — every client gets their own domain.
- Multi-domain tenants (e.g. `acme.com` + `acme.de` + `acme.fr`) pointing at the same SpiderPublish tenant.
- Pattern: "make this domain serve their SpiderPublish site."

## Prerequisites

- Domain control: ability to add DNS records at the registrar level (registrar dashboard OR access to the existing CF zone).
- SpiderPublish PAT scoped to the tenant.
- Cloudflare for SaaS configured in the SpiderPublish dispatch — this is platform infrastructure, already wired; you just consume it.

## The two flavours of domain attach

| Flavour | When | DNS setup |
|---|---|---|
| **CNAME** (preferred for apex-less + subdomains) | Tenant uses `www.acme.com` or `app.acme.com` | One CNAME record pointing at SpiderPublish's CF for SaaS hostname (`<tenant-slug>.cf.spideriq.ai` or similar) |
| **A record** (for apex `acme.com`) | Tenant wants `acme.com` (no www) | Two A records to CF's anycast IPs (provided by the SpiderPublish onboarding step) |

CNAME is operationally simpler and recommended. Push back gently on "I want it on the apex" — the CF for SaaS apex flow involves DNS-CNAME-flattening or registrar-level changes.

## Step 1 — Register the domain in SpiderPublish

This creates the `content_domains` row + triggers CF for SaaS to provision the certificate:

```
content_attach_domain({
  domain:         "www.acme.com",
  is_primary:     true,                       # the canonical domain for SEO + redirects
  redirect_apex:  true                         # 301 acme.com → www.acme.com
})
# → {
#     dry_run: true,                          # safe-default gated
#     preview: {
#       domain: "www.acme.com",
#       cname_target: "<tenant>.cf.spideriq.ai",
#       verification_status: "pending"
#     },
#     confirm_token: "cft_..."
#   }

content_attach_domain({
  domain: "www.acme.com",
  ...,
  confirm_token: "cft_..."
})
# → { success: true, domain: "www.acme.com", verification_status: "pending", cname_target: "..." }
```

## Step 2 — Add the DNS record at the registrar

Give the tenant the exact record to add:

| Type | Name | Value | TTL |
|---|---|---|---|
| `CNAME` | `www` | `<tenant>.cf.spideriq.ai` (from the response above) | Auto / 300 |

For apex (`acme.com` no www):

| Type | Name | Value |
|---|---|---|
| `A` | `@` | `198.51.100.10` (first CF for SaaS anycast IP) |
| `A` | `@` | `198.51.100.11` (second IP) |

Tenants editing their own DNS at the registrar:
- Cloudflare-managed zone: change in the CF dashboard → DNS tab → Add record
- Other (Namecheap, GoDaddy, Route53): registrar's DNS settings panel

## Step 3 — Wait for DNS propagation + CF cert issuance

```
content_domain_status({ domain: "www.acme.com" })
# → {
#     verification_status: "pending" | "verified" | "failed",
#     dns_propagation: { record_found: true, last_checked: "..." },
#     cert_status: { state: "pending_validation" | "active" | "failed" }
#   }
```

Typical timing:
- DNS propagation: 30 seconds (registrar's TTL) to 48 hours (TTL inheritance of upstream resolvers)
- CF certificate issuance: 5-15 minutes after DNS verifies via HTTP-01 challenge

Re-check every 60 seconds; expect `verified` + `cert_status.state == "active"` within 15-20 minutes.

## Step 4 — Test from the edge

Once `verified`, eyeball the domain:

```bash
curl -sI "https://www.acme.com"
# HTTP/2 200
# server: cloudflare
# cf-ray: ...
# strict-transport-security: max-age=...
```

Then the deeper render check:

```
content_visual_check({
  page_url: "https://www.acme.com",
  viewport: "desktop"
})
# → body_text_preview should match the tenant's home page
# → for form-bearing pages: dom.shadow_hosts.includes("spideriq-form") (Rule 62)
```

If you get a 525 / 526 / 522 from CF: the cert isn't valid (yet). Re-check `content_domain_status` and wait.

## Step 5 — Redirect the apex (if applicable)

If you attached `www.acme.com` as primary, ensure `acme.com` 301-redirects to it:

```
content_attach_domain({
  domain:        "acme.com",
  is_primary:    false,
  redirect_to:   "www.acme.com"
})
```

CF for SaaS handles the redirect at edge — no SpiderPublish code involvement.

## Steps — full flow

```python
1. content_attach_domain(domain="www.acme.com", is_primary=True)
                                       # safe-default gated; preview + confirm
2. (send tenant the CNAME instruction)
3. (tenant adds CNAME at registrar)
4. poll content_domain_status until verified + cert active
5. content_visual_check(page_url="https://www.acme.com")
6. (optional) content_attach_domain("acme.com", redirect_to="www.acme.com")
```

## Gotchas

- **CF for SaaS HTTP-01 challenge** requires DNS to be live BEFORE cert issuance. If you create the domain row but the CNAME isn't published, cert stays `pending_validation` forever.
- **Existing CF zone on the domain**: if the registrar's nameservers are already CF's, the customer must add the CNAME inside that CF zone (their DNS UI), NOT delete CF first. Removing CF then re-adding will break their email + other records.
- **CAA records**: a tenant with `CAA 0 issue "letsencrypt.org"` blocks CF's cert provider. Either add CAA for CF (`0 issue "comodoca.com"` and `0 issue "digicert.com"`) or remove the CAA.
- **DNSSEC drift**: domains with DNSSEC enabled at the registrar but no DS record at the parent zone respond intermittently with SERVFAIL. Check `dig +dnssec www.acme.com`.
- **`is_primary: true` matters for SEO.** All non-primary domains 301 to the primary. Set wrong primary = canonical-URL mismatch + crawl waste.
- **DNS propagation lies.** `dig` from your terminal may show the new record; the tenant's ISP cache may still serve the old record for hours. Always sanity-check from an edge probe (CF's DNS-over-HTTPS) or wait 24h.
- **The MCP tool `content_attach_domain` is Phase 11+12 gated** — preview shows you the CNAME target. Don't skip the preview; copy-paste errors on CNAME values are the #1 onboarding failure mode.

## Verify

```
content_domain_status({ domain: "www.acme.com" })
# → { verification_status: "verified", cert_status: { state: "active" } }

content_list_domains()
# → [{ domain: "www.acme.com", is_primary: true, cert_status: "active" }, ...]

# Edge probe
curl -sI "https://www.acme.com" | head -5
# HTTP/2 200
# server: cloudflare
```

## Anti-patterns

- **Telling the tenant "just point your domain at us" without specifying CNAME vs A.** They'll guess wrong and spend a day debugging.
- **Skipping `content_attach_domain` and just adding the DNS record.** CF for SaaS routes by hostname; without the SpiderPublish-side row, the request hits CF but no Worker handles it → 522.
- **Setting two domains as `is_primary: true`.** Only one can be primary per tenant; the system rejects the second. SEO chaos otherwise.
- **Removing the original `.sites.spideriq.ai` URL.** Keep it active as a fallback during DNS transitions; useful for debugging.
- **Trying to issue your own cert via Let's Encrypt.** CF for SaaS handles certs; competing cert lifecycles cause renewal failures.
- **Forgetting the visual-check post-attach.** A 200 from `curl` only proves CF is responding; the visual-check confirms YOUR tenant's pages are rendering (not a stale CF "no Worker bound" 522 page).

## See also

- [`../../content/custom-domain.md`](../../content/custom-domain.md) — generic custom-domain attach flow (this recipe is its Cloudflare-specialised twin with onboarding context)
- [`../../audit/visual-check-a-page.md`](../../audit/visual-check-a-page.md) — verification primitive used in Step 4
- [`../../reference/deploy-protocol.md`](../../reference/deploy-protocol.md) — the safe-default gate on `content_attach_domain`
- [`../../reference/tool-surface.md`](../../reference/tool-surface.md) — the `content_*_domain` tool family
