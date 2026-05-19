#!/usr/bin/env bash
# Git safety gate. Wired into Claude Code PreToolUse on Bash.
# Blocks destructive git operations that can corrupt or destroy the repo.
#
# Hook protocol:
#   stdin  = JSON payload { tool_name, tool_input: { command, ... }, ... }
#   exit 0 = allow tool call
#   exit 2 = block tool call (stderr surfaces back to the model)
#   else   = non-blocking error (logged, tool proceeds)
#
# Blocked patterns:
#   - git push --force / -f / --force-with-lease
#   - git push --delete (or refspec :branch)
#   - git reset --hard
#   - git clean -f / -fd / -fdx
#   - git branch -D / --delete --force
#   - git checkout -- . / git checkout .
#   - git restore (bulk paths)
#   - rm -rf .git (or variations)
#   - git filter-branch / git filter-repo
#   - git update-ref -d
#   - git reflog expire
#   - git gc --prune=now
#   - git tag -d / git push --delete tag
#   - --no-verify on commit or push

set -uo pipefail

PAYLOAD="$(cat)"

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty')"
  COMMAND="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty')"
else
  TOOL_NAME="$(printf '%s' "$PAYLOAD" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')"
  COMMAND="$(printf '%s' "$PAYLOAD" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi

[[ "$TOOL_NAME" != "Bash" ]] && exit 0
[[ -z "$COMMAND" ]] && exit 0

BLOCKED_REASON=""
block() {
  BLOCKED_REASON+="  - $1"$'\n'
}

# Strip heredoc bodies (<<TAG ... TAG, optionally with - or quoted tag).
# Prevents false positives when a destructive pattern appears inside a
# commit message body or other quoted content.
CMD_NO_HEREDOC="$(printf '%s\n' "$COMMAND" | awk '
  in_hd {
    line = $0
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line == tag) { in_hd = 0; tag = ""; next }
    next
  }
  {
    line = $0
    if ((idx = index(line, "<<")) > 0) {
      tail = substr(line, idx + 2)
      if (substr(tail, 1, 1) == "-") tail = substr(tail, 2)
      qc = substr(tail, 1, 1)
      if (qc == "\047" || qc == "\"") tail = substr(tail, 2)
      t = ""
      for (i = 1; i <= length(tail); i++) {
        c = substr(tail, i, 1)
        if (c ~ /[A-Za-z0-9_]/) t = t c
        else break
      }
      if (t != "") {
        tag = t
        in_hd = 1
        line = substr(line, 1, idx - 1)
      }
    }
    print line
  }
')"

# Collapse whitespace and strip quoted strings so a destructive pattern
# inside a commit message ("-m '... rm -rf .git ...'") is ignored.
NORM="$(printf '%s' "$CMD_NO_HEREDOC" | tr -s '[:space:]' ' ' | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"

# ── FORCE PUSH ────────────────────────────────────────────────────────────────
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +push\b.*(--force\b|--force-with-lease\b| -f($| ))'; then
  block "git push --force / -f / --force-with-lease — rewrites remote history, can wipe teammates' work"
fi

# ── REMOTE BRANCH/TAG DELETION ────────────────────────────────────────────────
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +push\b.*--delete\b'; then
  block "git push --delete — deletes remote branch or tag"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +push\b[^|;&]* :[A-Za-z0-9._/-]+'; then
  block "git push :branch — refspec form of remote branch deletion"
fi

# ── LOCAL DESTRUCTION ─────────────────────────────────────────────────────────
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +reset\b.*--hard\b'; then
  block "git reset --hard — discards uncommitted work and rewrites HEAD"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +clean\b.*-[A-Za-z]*f'; then
  block "git clean -f — permanently deletes untracked files"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +branch\b.*( -D\b|--delete +--force\b|--force +--delete\b)'; then
  block "git branch -D — force-deletes a local branch (may lose unmerged commits)"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +checkout\b +(\.|-- +\.|-- +\*)'; then
  block "git checkout . / -- . — bulk discard of working-tree changes"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +restore\b +(\.|--source=[^ ]+ +\.|--worktree +\.)'; then
  block "git restore on bulk paths — discards working-tree changes silently"
fi

# ── REPO ANNIHILATION ─────────────────────────────────────────────────────────
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])rm +-[A-Za-z]*r[A-Za-z]*f?[^|;&]*\.git(/|\b)'; then
  block "rm -rf .git — destroys the entire repository"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])rm +-[A-Za-z]*f?r?f?[^|;&]*\.git(/|\b)'; then
  block "rm with force flag against .git — destroys the entire repository"
fi

# ── HISTORY REWRITE ───────────────────────────────────────────────────────────
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +filter-(branch|repo)\b'; then
  block "git filter-branch / filter-repo — rewrites repository history"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +update-ref\b.* -d\b'; then
  block "git update-ref -d — deletes refs directly"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +reflog\b.*expire\b'; then
  block "git reflog expire — purges reflog, breaks recovery of lost commits"
fi
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +gc\b.*--prune=now\b'; then
  block "git gc --prune=now — immediately discards unreachable objects"
fi

# ── TAG DELETION ──────────────────────────────────────────────────────────────
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +tag\b.* -d\b'; then
  block "git tag -d — deletes a tag (may break releases)"
fi

# ── SKIP HOOKS ────────────────────────────────────────────────────────────────
if echo "$NORM" | grep -Eq '(^|[^A-Za-z0-9_])git +(commit|push|merge|rebase)\b.*--no-verify\b'; then
  block "--no-verify on git commit/push/merge/rebase — bypasses pre-commit hooks (skips quality gates)"
fi

# ── DECISION ──────────────────────────────────────────────────────────────────
if [[ -n "$BLOCKED_REASON" ]]; then
  {
    echo "================================================================"
    echo "  git-safety-gate: COMMAND BLOCKED"
    echo "================================================================"
    echo "  Command: $COMMAND"
    echo ""
    echo "  Reason(s):"
    echo "$BLOCKED_REASON"
    echo "  If this action is intentional and authorized, run it manually"
    echo "  outside Claude Code, or temporarily disable this hook in"
    echo "  .claude/settings.json."
    echo "================================================================"
  } >&2
  exit 2
fi

exit 0
