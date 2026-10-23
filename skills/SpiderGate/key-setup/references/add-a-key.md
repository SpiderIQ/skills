# Reference — add a key

A key reaches the vault one of two ways: the owner pastes a FREE key to you and
you call `addKey`, or the owner adds it in the dashboard from a link you give.
The provider guide decides which.

## Paste or link

`getProviderGuide(provider)` → read `guide[0]`:

| `kind` | `add_method` | You do |
|---|---|---|
| `free` | `paste` | Send them to `signup_url`; take the pasted key → `addKey` |
| `payg`, `enterprise`, `media` | `paste` | **Link only.** Give the dashboard link; do not take the key |
| `subscription`, `lease_only` | `login_link` | **Link only.** A browser sign-in (ChatGPT/Codex, Gemini CLI, Claude …). Never ask for a password |
| any | `never` | It cannot be added. Quote `terms_note` |

Links: the setup page `https://app.spideriq.ai/dashboard/gate/setup?step=<n>&provider=<p>`
(step 3 free, 2 subscription, 5 paid) — or `next.add_url` when the status names
this provider — and the vault page `https://app.spideriq.ai/dashboard/gate/vault`.

Why a paid key is link-only: a key pasted in chat is copied into the chat
provider's log and the agent host's transcript before any tool sees it. A free
key there costs little. A money-bearing key there can be spent by whoever reads
the transcript.

## Steps (free key)

1. `getProviderGuide` → confirm `kind: free`, `add_method: paste`. Say the
   `minutes`, what `needs` asks for (email, phone check on their page, card)
   and the `steps`. Give `signup_url`.
2. The owner pastes the key.
3. `addKey` with `{provider_name, credentials: {api_key, …required extra_fields}}`.
4. Answer by reference: "Saved your Groq key; it serves 20 models." Then tell
   them to delete the message that carried the key, and repeat `terms_note`.
5. `getOnboardingStatus` → the new `next`.

## WRONG → RIGHT

**WRONG — echoing the key**
```
"Added your Groq key gsk_live_AB…0123."
```
**RIGHT — by reference only**
```
"Saved your Groq key. It passed Groq's check and serves 20 models.
 Please delete the message with the key in it."
```

**WRONG — taking a paid key because the owner pasted it**
```
addKey(provider_name: "openai", credentials: {api_key: "sk-…"})
```
**RIGHT — refuse, link, and ask them to delete it**
```
"OpenAI keys cost money, so they're added in the dashboard:
 https://app.spideriq.ai/dashboard/gate/setup?step=5&provider=openai
 Please delete the message with the key in it."
```

## extra_fields

Some providers need more than a key. The guide lists them in `extra_fields`
(`{name, label, required}`), e.g. Cloudflare's `account_id`. Put each in
`credentials` beside `api_key`. A missing required one is refused before the
vault is called. (A `base_url` field belongs to coding-plan keys, which are
paid — the dashboard sets it.)

## Gotchas

- **422** — the provider refused the key, or a field is wrong. Nothing was
  saved. The key is redacted in the answer; say the reason, not the key.
- **403** — the PAT lacks `gate:vault:write` (a brand owner ticks "Add provider
  keys" when minting the agent key in Gate → Keys), or the caller is not the
  brand owner. Give the link.
- **429** — too many attempts. Wait a minute.
- `checked: true` in the MCP tool's answer means the provider has a live key
  check; `false` means it was saved unchecked.

## Verify

`getOnboardingStatus` → `connected` lists the provider with its `models` count.
