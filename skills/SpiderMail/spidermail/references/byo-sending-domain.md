# Bring your own sending domain

*Steps 1–2 of `references/run-a-broadcast.md`.* Read before checking, enrolling,
or explaining why a domain will not verify.

The tenant publishes SPF / DKIM / a tracking CNAME in **their own** DNS zone; we
verify it; on a pass their domain becomes a tenant-scoped source in **their**
pool, sending under **their** provider key. Two calls:

```
  sendCheckDomain   dry-run — stores NOTHING, binds NOTHING, needs NO api key
  sendEnrollDomain  verify + store the key encrypted + bind the source (admin)
```

## The tri-state that decides everything

Each of the three checks comes back with `ok` as **one of three values**:

| `ok` | Means |
|---|---|
| `true` | read and correct |
| `false` | read and wrong or missing |
| `null` | **UNDETERMINABLE** — the resolver could not be read |

**`null` is never a pass.** The top-level `verified` is true **only** when all
three checks are `true`. The failure mode this prevents: reporting "looks fine,
DNS is just slow" on a `null`, sending the user to `sendEnrollDomain`, and
having it refuse — after they think they're done.

Same rule on `provider_tracking.matches` in the enroll response: `null` means
UNVERIFIED, not "fine".

## WRONG / RIGHT

**WRONG** — treating a check as done because nothing said "false":

```
if check.spf.ok is not False:   # ← null slips through
    print("SPF is good")
```

**RIGHT** — the only safe read is the positive one:

```
if check.spf.ok is True:        # explicit
    print("SPF verified")
elif check.spf.ok is False:
    print(f"SPF wrong/missing. Publish: {check.spf.expected}")
else:
    print("SPF could not be determined — re-check, do not proceed")
```

**WRONG** — a generic error when the API told you the exact fix:

> "Domain verification failed. Please check your DNS settings."

**RIGHT** — every failed check carries `expected`, the literal record to publish.
The DKIM one names `<selector>._domainkey.<domain>` specifically:

> DKIM is missing. Publish this TXT record:
> `mailo._domainkey.mg.example.com` → `k=rsa; p=MIGfMA0…`

Hand the user `expected` verbatim. It is the whole point of the endpoint.

## Steps

### 1. Dry-run, iterate, re-check

```
sendCheckDomain {
  domain: "mg.example.com",          # required
  provider: "mailgun",               # default
  dkim_selector: "mailo",            # a SINGLE label, from the provider dashboard
  tracking_domain: "email.mg.example.com"   # defaults to email.<domain>
}
→ { domain, provider, verified: false,
    spf:            { ok, name, detail, expected, observed[] },
    dkim:           { ok, name, detail, expected, observed[] },
    tracking_cname: { ok, name, detail, expected, observed[] } }
```

This deliberately needs **no API key**: a tenant publishes records, checks, fixes
and checks again, and none of that iteration should be gated on handing over a
credential first. Nothing is stored either — loop as needed.

**Rate limit: 20 checks per minute per tenant.** The 429 carries `Retry-After`;
honour it rather than tightening the loop. DNS propagation is minutes, not
seconds — checking every 3 seconds tells you nothing new and burns the budget.

### 2. Enroll (admin, and it writes)

```
sendEnrollDomain {
  mailbox_id: 42,                    # MUST already have a capacity row
  domain: "mg.example.com",
  api_key: "<the tenant's own provider key>",
  api_base: "https://api.eu.mailgun.net",   # REQUIRED for an EU account
  enable_tracking: true              # default
}
→ 201 { client_id, mailbox_id, sending_domain, tracking_domain, provider,
        vault_key_ref: "apiint:106", state: "warming", tracking_enabled: true,
        verification: {…}, provider_tracking: {…}, warnings: [] }
```

Nothing is written unless the DNS verifies. The credential is stored **before**
the source is bound, deliberately: a source bound to a tenant with no stored
credential resolves as "no binding", whose one fallback would put this tenant's
mail on the **platform's** key and domain.

**Rate limit: 10 enrolments per hour per tenant.**

## The four refusals, and what each actually means

| Status | Code | Means | What to tell the user |
|---|---|---|---|
| 422 | (DNS syntax) | `domain` / `tracking_domain` / `dkim_selector` isn't a usable name | quote their input back — the message describes it |
| 422 | `domain_not_verified` | the DNS check failed at enroll time | re-run `sendCheckDomain` and give them `expected` |
| 409 | `source_not_enrolled` | that `mailbox_id` has **no capacity row** | this surface **binds**, it does not provision. Provisioning a sending source (daily cap, timezone, warm-up state) is operator-gated. |
| 409 | `source_owned_by_another_tenant` | the source is already bound elsewhere | not a retry — an ownership conflict |
| 503 | `send_tier_unavailable` | the send tier is not reachable | transient; retry later |

## Three things that surprise people

**Enrolment does not activate the domain.** The returned `state` is reported
**unchanged** — a cold domain comes back `warming` and ramps. There is no "make
it active" call here, by design: skipping warm-up is how a new domain gets
blocked. Read `references/pool-and-reputation.md` for the ramp.

**`enable_tracking: false` means link rewriting is OFF — not "use the default
tracker".** For a BYO source, no tracking domain means links are never rewritten
through a host the tenant doesn't own. That is the *safe* setting. The cost is
real and worth stating: **no click and no open events at all**, so
`sendGetDeliverability` will show engagement it cannot measure, and recipient
sunsetting then protects repliers only. The enroll response says so in
`warnings[]` — pass those through.

**EU Mailgun needs `api_base`.** An EU key against the US host `401`s and the
source is **terminalised** — not retried. If the tenant's Mailgun account is EU,
`api_base: "https://api.eu.mailgun.net"` is mandatory, and it is the single most
expensive field to get wrong on this call.

## Secrets

`api_key` is the tenant's own provider credential. It appears in the **request**
and in **no** response — you get back an opaque `vault_key_ref` (`apiint:<id>`),
never the key. Do not echo it back, do not log it, and do not put it in a
broadcast body: the outbound credential scanner blocks sends containing one, so
the leak becomes a failed job too.

## Verify

1. `sendCheckDomain` → `verified: true`, with all three `ok: true` (not `null`).
2. `sendEnrollDomain` → `201` with a `vault_key_ref`.
3. `sendListSources` → the mailbox now appears with a `sending_domain` set.
   **This is the real proof it joined the pool** — the 201 says it was bound;
   the pool listing says it is there.
4. Read `warnings[]` on the enroll response and pass any through — a tracking
   host that could not be confirmed is reported there, not as an error.
