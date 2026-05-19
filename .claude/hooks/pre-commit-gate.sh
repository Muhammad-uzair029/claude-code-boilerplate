#!/usr/bin/env bash
# Pre-commit quality gate. Wired into Claude Code PreToolUse on Bash.
# Blocks `git commit` if staged diff contains secrets or critical issues.
#
# Hook protocol:
#   stdin  = JSON payload { tool_name, tool_input: { command, ... }, ... }
#   exit 0 = allow tool call
#   exit 2 = block tool call (stderr surfaces back to the model)
#   else   = non-blocking error (logged, tool proceeds)

set -uo pipefail

# Read stdin payload (Claude Code hook envelope)
PAYLOAD="$(cat)"

# Extract tool name + command (require jq; fall back to grep if absent)
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty')"
  COMMAND="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty')"
else
  TOOL_NAME="$(printf '%s' "$PAYLOAD" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')"
  COMMAND="$(printf '%s' "$PAYLOAD" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi

# Only gate Bash tool calls that look like `git commit`
[[ "$TOOL_NAME" != "Bash" ]] && exit 0
[[ "$COMMAND" != *"git commit"* ]] && exit 0

# If the dev explicitly passes --no-verify, respect it (still warn).
if [[ "$COMMAND" == *"--no-verify"* ]]; then
  echo "[pre-commit-gate] --no-verify set; skipping quality gate." >&2
  exit 0
fi

# Find repo root; bail if not in a git repo
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0

STAGED_FILES="$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)"
[[ -z "$STAGED_FILES" ]] && exit 0  # nothing staged, let the commit fail naturally

FAILED=0
REPORT=""

# ── 1. SECRET SCAN ────────────────────────────────────────────────────────────
DIFF_ADDED="$(git diff --cached --unified=0 | grep -E '^\+' | grep -v '^\+\+\+')"

SECRET_HITS=""
add_secret() {
  SECRET_HITS+="    - $1"$'\n'
}

# AWS access key ID
echo "$DIFF_ADDED" | grep -E 'AKIA[0-9A-Z]{16}' >/dev/null && add_secret "AWS access key (AKIA...)"
# GitHub PAT / OAuth tokens
echo "$DIFF_ADDED" | grep -E 'gh[pousr]_[A-Za-z0-9_]{36,}' >/dev/null && add_secret "GitHub token (gh*_...)"
# Stripe live keys
echo "$DIFF_ADDED" | grep -E 'sk_live_[A-Za-z0-9]{24,}' >/dev/null && add_secret "Stripe live secret key"
echo "$DIFF_ADDED" | grep -E 'rk_live_[A-Za-z0-9]{24,}' >/dev/null && add_secret "Stripe live restricted key"
# Slack tokens
echo "$DIFF_ADDED" | grep -E 'xox[abprs]-[A-Za-z0-9-]{10,}' >/dev/null && add_secret "Slack token (xox.-...)"
# OpenAI keys
echo "$DIFF_ADDED" | grep -E 'sk-[A-Za-z0-9]{32,}' | grep -vE 'sk-ant-' >/dev/null && add_secret "OpenAI-style key (sk-...)"
# Anthropic keys
echo "$DIFF_ADDED" | grep -E 'sk-ant-[A-Za-z0-9_-]{50,}' >/dev/null && add_secret "Anthropic key (sk-ant-...)"
# Private keys
echo "$DIFF_ADDED" | grep -E -- '-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----' >/dev/null && add_secret "Private key block"
# GCP service account
echo "$DIFF_ADDED" | grep -E '"type"[[:space:]]*:[[:space:]]*"service_account"' >/dev/null && add_secret "GCP service-account JSON"
# DB URLs with creds
echo "$DIFF_ADDED" | grep -E '(postgres|postgresql|mysql|mongodb)://[^:[:space:]]+:[^@[:space:]]+@' >/dev/null && add_secret "Database URL with embedded credentials"
# Staged .env file (excluding example/template)
ENV_HIT="$(echo "$STAGED_FILES" | grep -E '(^|/)\.env(\..*)?$' | grep -vE '\.(example|template|sample)$' || true)"
[[ -n "$ENV_HIT" ]] && add_secret ".env file staged: $(echo "$ENV_HIT" | tr '\n' ' ')"

if [[ -n "$SECRET_HITS" ]]; then
  FAILED=1
  REPORT+=$'\n[BLOCK] Secrets detected in staged diff:\n'"$SECRET_HITS"
fi

# ── 2. LINT (advisory in script, gate decides at the end) ─────────────────────
# We intentionally keep lint/typecheck/test out of the blocking path to avoid
# 10-minute commit hangs. Run `pre-merge-check` skill manually for the full gate.
# Secret-scan + obvious debug-leftover scan are fast enough to block on.

# ── 3. DEBUG LEFTOVERS ────────────────────────────────────────────────────────
DEBUG_HITS=""
echo "$DIFF_ADDED" | grep -E '(^|[^A-Za-z0-9_])(debugger|console\.log|console\.debug)[^A-Za-z0-9_]' >/dev/null \
  && DEBUG_HITS+=$'    - JS debug leftovers (console.log/debugger)\n'
echo "$DIFF_ADDED" | grep -E '^\+.*\b(breakpoint\(\)|pdb\.set_trace\(\)|import pdb)\b' >/dev/null \
  && DEBUG_HITS+=$'    - Python debug leftovers (pdb / breakpoint())\n'

if [[ -n "$DEBUG_HITS" ]]; then
  FAILED=1
  REPORT+=$'\n[BLOCK] Debug statements in staged diff:\n'"$DEBUG_HITS"
fi

# ── 4. DECISION ───────────────────────────────────────────────────────────────
if [[ "$FAILED" -eq 1 ]]; then
  {
    echo "================================================================"
    echo "  pre-commit-gate: COMMIT BLOCKED"
    echo "================================================================"
    echo "$REPORT"
    echo ""
    echo "Fix the issues above, re-stage, and commit again."
    echo "To bypass intentionally (e.g. for a fixture): include --no-verify."
    echo "================================================================"
  } >&2
  exit 2
fi

exit 0
