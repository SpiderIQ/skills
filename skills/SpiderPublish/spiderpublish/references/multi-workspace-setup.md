# reference/multi-workspace-setup

> **REQUIRES — read before you plan.**
> **Package:** n/a — configuration, not tools.
> **Tools:** `get_auth_status` (in every universe) · `list_workspaces`
> Read this when the brand owns MORE THAN ONE client — an agency, a reseller, or
> anyone whose `workspaces[]` has more than one entry.
> **Getting `AMBIGUOUS_TENANT`? Start at *Pin the tenant*, below.**

How to run one agent across many client workspaces without writing to the wrong
one, plus the three host bugs that make a correct config look broken.

## TL;DR

- **One IDE workspace per client is the default.** Pin `SPIDERIQ_WORKSPACE` in
  that workspace's config and the question never comes up again.
- **A wrong-tenant write returns 200.** It is indistinguishable from a correct
  one at every layer you can see. Configuration is the only real defence;
  remembering to pass an argument is not.
- **Three known host bugs produce "broken" from a correct config** — a name
  collision, a sibling server's crash, and an `npx` cache race. All three are
  covered below with their exact error strings.

---

## Which tenant a call touches

Resolved per call, highest wins:

```
  1  explicit    workspace: "cli_…" passed as a tool argument
  2  environment $SPIDERIQ_WORKSPACE
  3  binding     spideriq.json in cwd or an ancestor
  4  sole        exactly one credential stored -> used automatically
  5  refuse      several credentials, nothing names one -> AMBIGUOUS_TENANT
```

Rung 5 is a **feature**. With three clients enrolled and no binding, guessing
would be a coin flip on someone's live website, so the call is refused and hands
back a `retry_with` object. Merge it into your retry.

> **Two different selectors, constantly confused.** `SPIDERIQ_WORKSPACE` /
> `SPIDERIQ_WORKSPACE_CWD` choose the **client** (`cli_…`).
> `SPIDERIQ_PROJECT_ID` chooses the **website** (`proj_…`) inside that client.
> An `AMBIGUOUS_TENANT` error is *always* the first pair — setting a project id
> will not resolve it.

---

## Pattern A — one workspace per client (use this)

```
  ~/clients/
    acme/     .mcp.json  -> SPIDERIQ_WORKSPACE=cli_acme…
    globex/   .mcp.json  -> SPIDERIQ_WORKSPACE=cli_globex…
    initech/  .mcp.json  -> SPIDERIQ_WORKSPACE=cli_initech…
```

```json
"spideriq": {
  "command": "npx",
  "args": ["-y", "@spideriq/mcp@1.80.0"],
  "env": {
    "SPIDERIQ_MCP_MODE": "facade",
    "SPIDERIQ_FORMAT": "yaml",
    "SPIDERIQ_WORKSPACE": "cli_xxxxxxxxxxxx"
  }
}
```

One credential store (`~/.spideriq/credentials.json`) serves all of them — the
env var selects, it does not authenticate. **Blast radius is one client**: a
session that goes wrong cannot reach the other twelve.

**Verify, do not assume.** `get_auth_status({ topic: "tenancy" })` must report
`resolved_via: "environment"` and your `cli_…` as `active_workspace`. If it says
`sole-credential`, the variable never reached the server and you are being
carried by having exactly one credential — which stops being true the day the
next client is enrolled.

### If you keep a `spideriq.json` instead

```json
{ "workspace_id": "cli_xxxxxxxxxxxx", "workspace_name": "Acme" }
```

Only `workspace_id` (and optional `workspace_name` / `project_id` /
`project_name`) are read. Keys like `domain` or `brand_id` are **ignored** — a
file full of them is inert decoration, and a setup guide that says otherwise is
wrong.

⚠️ The file is found by walking up from the **MCP server's** working directory,
which is not always your project. **Antigravity starts servers at `/`**
(confirmed from its own proxy trace), so nothing is ever found and the binding
silently does nothing. Fix by naming the directory:

```json
"SPIDERIQ_WORKSPACE_CWD": "/absolute/path/to/the/project"
```

`resolved_via` must then read `"binding"`. If it still reads `sole-credential`,
the file is not being reached.

---

## Pattern B — one workspace, many clients

Only when the work is genuinely cross-client (a report over all of them, a
migration). Pass rung 1 on **every** call:

```
tool_call({ name: "content_create_page",
            arguments: { workspace: "cli_acme…", title: "…" } })
```

**The failure mode is forgetting once.** There is no error — the write lands on
whichever tenant resolution picked, returns 200, and looks perfect. Under
Pattern A the same slip is impossible, which is the entire reason A is the
default.

If you must work this way: re-run `get_auth_status` between clients, say out
loud which client each batch targets, and never carry a `cli_…` from an earlier
message without re-reading it.

---

## Three host bugs that look like our bugs

Reported by an Antigravity session, 2026-08-14. **We cannot fix these — they are
IDE bugs — but the right config avoids all three.**

### 1. Same server name in global and local config

Hosts read a global config (`~/.gemini/config/mcp_config.json`) **and** the
workspace's `.mcp.json`. Identical keys do not merge or override — both spawn,
then the local one is killed mid-handshake:

```
connection closed: calling "initialize": client is closing: EOF
```

**Fix:** never reuse a key across the two scopes. Global `spiderpublish`, local
`spideriq` — or namespace the local one per client, `spideriq-acme`.

### 2. One broken server disables every server in the file

The lazy loader treats a `.mcp.json` as a single transaction. If **any** server
in it fails to boot — an empty `"OPVS_PAT": ""` is enough — the loader aborts
for the whole file. A perfectly configured `spideriq` then transmits its 9 tools
and they appear in the prompt, but the invocation command is never injected:

```
unknown tool name: call_mcp_tool
```

**This is the most misleading failure in the set: the tools are visible and
uncallable, so it reads as a SpiderIQ problem when the cause is a sibling.**

**Fix:** never leave an env value blank — **omit the whole server entry**
instead. Add servers one at a time and confirm each boots. Fewer servers per
file is genuinely safer here.

> **Two different bugs share the phrase "unknown tool".** They have different
> causes and different fixes:
>
> ```
>   unknown tool <name>            431 tools blew the payload limit; the list
>                                  was silently truncated  ->  FACADE MODE
>
>   unknown tool name: call_mcp_tool
>                                  a sibling server crashed and took the
>                                  loader with it            ->  FIX THE SIBLING
> ```
>
> Read the exact string. Turning on facade mode will not fix the second, and
> fixing a sibling will not fix the first.

### 3. `npx` cache race between concurrent servers

Servers spawn simultaneously. Two `npx` processes resolving `@latest` both hit
the registry and write the shared `~/.npm/_npx` lock:

```
npm error code ECOMPROMISED   (Lock compromised)
```

The server exits 1 before `initialize` is ever sent.

**Fix — two, use both:**

```json
"args": ["-y", "@spideriq/mcp@1.80.0"],          // PIN, don't use @latest
"env": { "npm_config_cache": "/tmp/npm-cache-spideriq" }
```

A pinned version already in cache needs no registry round-trip, so the window
mostly closes; a private cache directory closes the rest. Pinning also makes the
tool surface reproducible — it changes when you change it, not between sessions.

---

## Registry

Put the scope in `.npmrc`, **never** a `--registry=` flag in `args`:

```
@spideriq:registry=https://npm.spideriq.ai
```

A scoped `.npmrc` rule **beats the flag**, so a registry passed in `args` is
silently ignored on a machine that has the scope and resolves nothing on one
that does not. It looks like it works right up until a clean machine.

---

## Verify

Run after any config change, in a **new session** (servers are read at start;
some hosts also cache schemas to disk and need a full restart):

```
get_auth_status({ topic: "tenancy" })
```

| Field | What it must say |
|---|---|
| `active_workspace` | the `cli_…` you intended |
| `resolved_via` | `environment` (Pattern A) or `binding` (spideriq.json) |
| `workspaces[]` | every client you can reach — count them |
| `conflicts` | absent or empty. **Non-empty means a losing candidate names a DIFFERENT tenant** — read `why_ignored` |

`resolved_via: "sole-credential"` with one credential is not a pass. It is
"nothing is configured and there happened to be only one option", and it becomes
`AMBIGUOUS_TENANT` the moment a second client is enrolled.

⚠️ If `get_auth_status` returns only `authenticated` / `client_id` / `scopes`
with no tenancy fields, the package is **stale** — `topic` was added later.
Update before trusting anything above.
