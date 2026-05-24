#!/usr/bin/env bash
# find-tool-for-intent.sh
#
# Fuzzy-match a free-text user intent to the right SpiderPublish recipe.
# Saves the agent from loading the full SKILL.md when it already knows what
# the user wants. Output: top 3 candidate recipe paths + one-line goals.
#
# Usage:
#   ./find-tool-for-intent.sh "add a contact form to the home page"
#   ./find-tool-for-intent.sh "delete the old blog post"
#
# How it works:
#   - Reads the decision-tree table from skills/spiderpublish/SKILL.md
#   - Splits the intent into keywords
#   - Scores each table row by keyword overlap (case-insensitive)
#   - Prints top 3 by score
#
# Why this exists: SKILL.md grows. Loading the whole router every time the
# agent needs to remember which recipe to read is wasteful. This script
# does the lookup deterministically in milliseconds and burns ~50 tokens
# vs the ~3000 tokens of the full SKILL.md body.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 \"<user intent in plain English>\"" >&2
  exit 1
fi

INTENT="$*"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="${SKILL_MD:-$SCRIPT_DIR/../skills/spiderpublish/SKILL.md}"

if [ ! -f "$SKILL_MD" ]; then
  echo '{"ok":false,"reason":"SKILL.md not found","path":"'"$SKILL_MD"'"}' >&2
  exit 1
fi

python3 - "$INTENT" "$SKILL_MD" <<'PY'
import sys, re

intent = sys.argv[1].lower()
skill_md = sys.argv[2]

# Tokenize intent (drop short stopwords)
STOPWORDS = {"the","a","an","to","of","on","in","for","with","and","or","my","this","that","is","are","i","you"}
intent_tokens = {t for t in re.findall(r"[a-z]{3,}", intent) if t not in STOPWORDS}

# Parse the decision-tree table: rows like `| description... | recipes/... |`
rows = []
with open(skill_md) as f:
    in_table = False
    for line in f:
        line = line.rstrip()
        if line.startswith("|") and "recipes/" in line:
            cells = [c.strip() for c in line.strip("|").split("|")]
            if len(cells) >= 2:
                desc = cells[0]
                recipe = next((c for c in cells if c.startswith("`recipes/") or "recipes/" in c), "")
                # strip backticks
                recipe = recipe.strip("`")
                if desc and recipe:
                    rows.append((desc, recipe))

# Score rows by keyword overlap
def score(desc: str) -> int:
    desc_tokens = {t for t in re.findall(r"[a-z]{3,}", desc.lower()) if t not in STOPWORDS}
    return len(intent_tokens & desc_tokens)

scored = sorted([(score(desc), desc, recipe) for desc, recipe in rows], key=lambda x: -x[0])
top = [(s, d, r) for s, d, r in scored if s > 0][:3]

import json
if not top:
    print(json.dumps({"ok": True, "intent": sys.argv[1], "matches": [], "hint": "no recipe matched — read full SKILL.md decision tree"}, indent=2))
else:
    print(json.dumps({
        "ok": True,
        "intent": sys.argv[1],
        "matches": [{"score": s, "goal": d, "recipe": r} for s, d, r in top]
    }, indent=2))
PY
