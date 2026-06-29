## mail-admin

The Email Admin control plane. 12 tools to stand up and operate cold-outreach
mailboxes on a provider org (Zoho EU first): connect an org to a brand, provision
mailboxes, enable IMAP, set/rotate passwords, register them into SpiderMail so the
data plane can poll/send, health-check with a real IMAP+SMTP login, run the full
provision→link chain in one call, and — as a deliberate opt-in — add a registered
mailbox to the brand's Smartlead account as an outreach sender.

This is the privileged **control** plane (org-admin actions over a provider's
API), super_admin / `X-Admin-Key` only and fully audited — distinct from
SpiderMail (the data plane that reads/sends mail) and from the integrations/vault
surface (which stores the provider OAuth token). Provisioning consumes paid
license seats; a full org returns a clean 409. The mailbox list is a live
provider read (~20s cold, ~90s cached). Smartlead is never auto-chained.
