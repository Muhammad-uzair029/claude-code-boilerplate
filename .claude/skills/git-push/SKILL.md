---
name: git-push
description: Reviews staged files for edge cases and null-safety issues, generates a meaningful Conventional Commit message from the diff, asks the developer for confirmation, then commits and pushes ONLY the already-staged files. Use when the user types "git-push", "/git-push", "push my code", or asks to commit-and-push staged changes.
---

## Objective
Save the developer the cognitive overhead of naming commits and running push commands. The skill inspects only what is staged, performs a lightweight safety review, drafts a clear commit message, gets explicit confirmation, then ships it.

## Hard Rules
- **NEVER use `git add .` or `git add -A`.** Only the files the developer has already staged get committed and pushed. If nothing is staged, stop and tell the user.
- **NEVER `--force` push.** If push is rejected, surface the error and stop.
- **NEVER skip hooks** (`--no-verify`) unless the user explicitly asks.
- **ALWAYS confirm before pushing.** Even if the user said "just push it" earlier in the session, re-confirm per invocation since each push is a separate intent.
- **NEVER commit secrets.** If the staged diff contains `.env`, credentials, API keys, tokens, or private keys — abort and warn.
- Follow Conventional Commits: `type(scope): subject` — subject ≤ 50 chars, imperative mood.

## Execution Steps

### 1. Verify repo state
Run in parallel:
- `git rev-parse --is-inside-work-tree` — confirm git repo
- `git status --short` — see what's staged vs unstaged
- `git diff --cached --stat` — staged file summary
- `git branch --show-current` — current branch name
- `git log -5 --oneline` — recent commit style reference

If nothing is staged, stop. Tell the user: "No staged files. Stage with `git add <file>` first."

### 2. Safety review on staged diff
Run `git diff --cached` and scan for:
- **Secrets:** API keys, tokens, passwords, private keys, `.env` content, AWS/GCP creds
- **Null safety:** New property access without optional chaining where the source could be null/undefined
- **Edge cases:** Unhandled empty arrays, division by zero, missing error catches on async calls, off-by-one in loops
- **Obvious bugs:** Unused awaits, swallowed errors (`catch {}`), hardcoded test values, leftover `console.log`/`debugger`/`TODO:fix`
- **Breaking changes:** API signature changes, removed exports, schema migrations without rollback

Report findings in a short block:
```
Safety check:
- [file:line] — issue — suggested fix
```
If critical issues (secrets, obvious bugs) — stop and ask the user how to proceed.
If minor issues — list them but allow user to proceed.
If clean — say "No issues found."

### 3. Draft the commit message
Based on the staged diff content (not file names alone):
- **Type:** `feat` (new feature), `fix` (bug), `refactor`, `chore`, `docs`, `test`, `style`, `perf`, `build`, `ci`
- **Scope:** workspace or module (e.g., `frontend-ui`, `backend-api`, `auth`)
- **Subject:** imperative, ≤ 50 chars, no trailing period
- **Body:** only if the *why* isn't obvious from the subject. Wrap at 72 chars.

Match the repo's existing commit style from `git log -5 --oneline`.

### 4. Confirmation gate
Show the developer:
```
Branch: <current-branch>
Files staged: <count>
  - path/to/file1
  - path/to/file2

Commit message:
  <type>(<scope>): <subject>

  <body if present>

Push target: origin/<current-branch>
```
Ask: **"Commit and push? (yes / edit message / cancel)"**

- `yes` → proceed to step 5
- `edit message` → take new message, re-confirm
- `cancel` → abort, leave staged files staged, no commit made

### 5. Commit and push
Run sequentially:
1. `git commit -m "$(cat <<'EOF'
<message>
EOF
)"` — heredoc to preserve formatting
2. `git push origin <current-branch>` — push to tracking branch

If branch has no upstream, use `git push -u origin <current-branch>`.

If push is rejected (non-fast-forward, hook failure, etc.) — surface the full error and stop. Do not retry or force.

### 6. Report
One-line confirmation showing:
- Commit SHA (short)
- Branch pushed to
- Remote URL or PR-create hint if applicable

## Output Style
Match the active session tone. Default: terse, fragments OK. Code/commits stay normal-prose.
