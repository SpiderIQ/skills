#!/usr/bin/env bash
# verify-tenant-scope.sh
#
# Mandatory pre-flight for any SpiderPublish mutation. Confirms three things:
#   1. A spideriq.json exists in cwd or any parent (Phase 11+12 Lock 3)
#   2. The PAT in ~/.spideriq/credentials.json scopes to the SAME client_id
#      as spideriq.json names (Phase 11+12 Lock 1)
#   3. The SpiderIQ API recognizes the PAT (Lock 1 server-side check)
#
# Output is one line of structured JSON. Paste it into the conversation
# before the next destructive call. If `match` is false, STOP — don't mutate.
#
# Exit codes:
#   0  match — safe to proceed
#   1  mismatch — token client_id != spideriq.json project_id
#   2  no spideriq.json found in cwd / parents
#   3  no PAT configured (run `spideriq use <project>` first)
#   4  spideriq CLI not installed
#
# Why this exists: text-based "remember to check scope" advice is skipped under
# ship pressure. Running this script + pasting its output makes the check
# auditable and unmissable. Pattern adopted from HeyGen's Hyperframes
# (commit 190f1ec: "language-only enforcement is selectively interpretable
# by the agent under ship pressure").

set -eo pipefail

# --- 0. CLI installed? ---
if ! command -v spideriq >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
  printf '{"ok":false,"reason":"spideriq CLI not found; install: npm i -g @spideriq/cli --registry https://npm.spideriq.ai","exit":4}\n'
  exit 4
fi

SPIDERIQ_CMD="spideriq"
if ! command -v spideriq >/dev/null 2>&1; then
  SPIDERIQ_CMD="npx -y @spideriq/cli"
fi

# --- 1. Walk up from cwd looking for spideriq.json ---
dir="$PWD"
project_json=""
while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
  if [ -f "$dir/spideriq.json" ]; then
    project_json="$dir/spideriq.json"
    break
  fi
  dir="$(dirname "$dir")"
done

if [ -z "$project_json" ]; then
  printf '{"ok":false,"reason":"no spideriq.json found in cwd or parents — run: spideriq use <project>","searched_from":"%s","exit":2}\n' "$PWD"
  exit 2
fi

project_id=$(python3 -c "import json,sys; print(json.load(open('$project_json')).get('project_id',''))" 2>/dev/null || echo "")
if [ -z "$project_id" ]; then
  printf '{"ok":false,"reason":"spideriq.json missing project_id field","path":"%s","exit":2}\n' "$project_json"
  exit 2
fi

# --- 2. PAT configured? ---
credentials="$HOME/.spideriq/credentials.json"
if [ ! -f "$credentials" ]; then
  printf '{"ok":false,"reason":"no PAT — run: spideriq auth request --email <admin>","exit":3}\n'
  exit 3
fi

# --- 3. whoami: client_id the PAT scopes to ---
whoami_json=$($SPIDERIQ_CMD whoami --json 2>/dev/null || echo "{}")
token_client_id=$(printf '%s' "$whoami_json" | python3 -c "import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get('client_id') or d.get('project_id') or '')
except Exception:
    print('')" 2>/dev/null)

if [ -z "$token_client_id" ]; then
  printf '{"ok":false,"reason":"spideriq whoami returned no client_id — PAT may be invalid or expired","exit":3}\n'
  exit 3
fi

# --- 4. Match? ---
if [ "$token_client_id" = "$project_id" ]; then
  printf '{"ok":true,"project_id":"%s","spideriq_json":"%s","verified_at":"%s","exit":0}\n' \
    "$project_id" "$project_json" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  exit 0
else
  printf '{"ok":false,"reason":"MISMATCH — token scope does not match spideriq.json","token_client_id":"%s","spideriq_json_project_id":"%s","spideriq_json":"%s","exit":1}\n' \
    "$token_client_id" "$project_id" "$project_json"
  exit 1
fi
