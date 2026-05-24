#!/usr/bin/env python3
"""
dry-run-then-confirm.py

Wraps the SpiderPublish Phase 11+12 two-phase confirm flow for destructive
operations. Call once with --description and the target URL; the script:

  1. Calls the URL with ?dry_run=true → captures the preview + confirm_token
  2. Pretty-prints the preview to stderr (so the agent can read it before
     committing)
  3. Either auto-consumes the token (--auto) or pauses for stdin "y"
  4. Calls the URL with ?confirm_token=cft_... to actually mutate
  5. Maps 410 / 409 / 403 envelopes to clear failure messages

Why this exists: Phase 11+12 is OPT-IN but on production tenants always
opt-in. The two-call pattern is error-prone (token expiry, replay, scope
mismatch). One wrapper script makes the entire flow auditable + atomic.

Pattern from HeyGen's Hyperframes (commit 190f1ec): when an agent skips a
prose-only rule under pressure, ship a script.

Usage:

  ./dry-run-then-confirm.py \\
      --url https://spideriq.ai/api/v1/dashboard/projects/$PID/content/deploy \\
      --method POST \\
      --description "Deploy demo.spideriq.ai to production" \\
      --body '{}' \\
      --auto

Exit codes:
  0   mutation succeeded
  1   dry_run call failed (network / 4xx other than the gate)
  2   confirm call failed
  10  token expired (410) — re-run dry_run
  11  token already consumed (409) — re-run dry_run
  12  token mismatch (403) — client/action/snapshot drift
"""

from __future__ import annotations
import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def _hit(url: str, method: str, body: str | None, token: str | None) -> tuple[int, dict]:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = body.encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        try:
            payload = json.loads(e.read().decode("utf-8") or "{}")
        except Exception:
            payload = {"error": {"code": "DECODE_FAIL", "message": str(e)}}
        return e.code, payload


def _pat() -> str:
    cred = os.path.expanduser("~/.spideriq/credentials.json")
    if os.path.exists(cred):
        with open(cred) as f:
            d = json.load(f)
        return d.get("default", {}).get("token", "")
    return os.environ.get("SPIDERIQ_TOKEN", "")


def main() -> int:
    ap = argparse.ArgumentParser(description="Phase 11+12 dry_run → confirm wrapper")
    ap.add_argument("--url", required=True, help="Endpoint URL (path-scoped /dashboard/projects/{pid}/...)")
    ap.add_argument("--method", default="POST", choices=("POST", "PATCH", "PUT", "DELETE"))
    ap.add_argument("--body", default="{}", help="JSON body string")
    ap.add_argument("--description", required=True, help="Human-readable description of the mutation")
    ap.add_argument("--auto", action="store_true", help="Auto-consume the confirm_token (skip stdin prompt)")
    ap.add_argument("--token", default=None, help="PAT (overrides credentials file)")
    args = ap.parse_args()

    token = args.token or _pat()
    if not token:
        print('{"ok":false,"reason":"no PAT — set SPIDERIQ_TOKEN or run: spideriq auth request"}', file=sys.stderr)
        return 1

    # --- Phase A: dry_run ---
    sep = "&" if "?" in args.url else "?"
    dry_url = f"{args.url}{sep}dry_run=true"
    print(f"[dry-run] {args.description}", file=sys.stderr)
    print(f"[dry-run] {args.method} {dry_url}", file=sys.stderr)
    status, dry = _hit(dry_url, args.method, args.body, token)
    if status >= 400:
        print(json.dumps({"phase": "dry_run", "status": status, "body": dry}, indent=2), file=sys.stderr)
        return 1

    confirm_token = dry.get("confirm_token") or dry.get("preview", {}).get("confirm_token")
    expires_at = dry.get("expires_at") or dry.get("preview", {}).get("expires_at")
    preview = dry.get("preview") or dry.get("changes") or dry

    print("\n=== PREVIEW ===", file=sys.stderr)
    print(json.dumps(preview, indent=2, default=str)[:4000], file=sys.stderr)
    print(f"\nconfirm_token: {confirm_token}", file=sys.stderr)
    print(f"expires_at:    {expires_at}", file=sys.stderr)

    if not confirm_token:
        print("[error] dry_run returned no confirm_token — endpoint may not be gated", file=sys.stderr)
        return 1

    # --- Phase B: confirm ---
    if not args.auto:
        print('\n[gate] Type "y" + Enter to confirm, anything else to abort:', file=sys.stderr)
        choice = sys.stdin.readline().strip().lower()
        if choice != "y":
            print('[abort] confirm_token discarded; no mutation', file=sys.stderr)
            return 0

    confirm_url = f"{args.url}{sep}confirm_token={confirm_token}"
    print(f"\n[confirm] {args.method} {confirm_url}", file=sys.stderr)
    status, result = _hit(confirm_url, args.method, args.body, token)

    # Map common error envelopes
    if status == 410:
        print(json.dumps({"phase": "confirm", "status": 410, "reason": "confirm_token expired (5min TTL) — re-run dry_run", "body": result}, indent=2))
        return 10
    if status == 409:
        print(json.dumps({"phase": "confirm", "status": 409, "reason": "confirm_token already consumed — re-run dry_run", "body": result}, indent=2))
        return 11
    if status == 403:
        print(json.dumps({"phase": "confirm", "status": 403, "reason": "mismatch (client/action/resource changed since dry_run) — re-run dry_run", "body": result}, indent=2))
        return 12
    if status >= 400:
        print(json.dumps({"phase": "confirm", "status": status, "body": result}, indent=2))
        return 2

    print(json.dumps({"ok": True, "status": status, "result": result}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
