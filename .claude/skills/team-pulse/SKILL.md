---
name: team-pulse
description: Aggregates daily or weekly engineering activity across the team — commits, PRs opened/merged, reviews — from a configured list of repos and team members. Outputs a markdown digest saved to docs/team-pulse/ that the lead can paste into Notion/Slack/notes. Use when the user types "team-pulse", "/team-pulse", "weekly progress", "team activity", "who did what this week", or "team report".
---

## Objective
Give the team lead a clear, scannable answer to "what did everyone ship this week" without pinging anyone. Pulls signal from GitHub (the source of truth) into a markdown digest grouped per person.

## Config: `.claude/team.yaml`
The skill expects a config file at `.claude/team.yaml` in the project root. **Only `repos:` is required.** Authors are auto-detected from commit metadata (no roster needed). Schema:

```yaml
# Repos to scan — paste URLs in any of these formats:
#   https://github.com/owner/repo  |  github.com/owner/repo
#   owner/repo                      |  git@github.com:owner/repo.git
repos:
  - https://github.com/softaims/frontend-app
  - https://github.com/softaims/backend-api
  - https://github.com/softaims/ai-engine

defaults:
  window: weekly              # weekly | daily
  output_dir: docs/team-pulse
  group_by: repo              # repo | person | both
```

### URL normalization
Before any `gh` call, strip each repo entry to `owner/repo`:
- `https://github.com/X/Y` → `X/Y`
- `github.com/X/Y` → `X/Y`
- `git@github.com:X/Y.git` → `X/Y`
- `X/Y` → `X/Y` (pass through)
- Trim trailing `.git` and trailing `/`

### Auto-detect authors
The skill always reads authors directly from commit metadata — no roster needed:
- Use `gh api repos/<owner>/<repo>/commits` and group by `author.login`
- Fall back to `commit.author.name` if `author` is null (e.g., commits from users not on GitHub)
- Display name = GitHub login (or commit author name when login is unknown)
- Skip the "Quiet this week" section since there's no explicit roster to compare against

## Hard Rules
- **`gh` CLI required and authenticated.** If not, stop and tell the user to run `gh auth login`.
- **Read-only on remotes.** This skill never writes commits, PRs, or comments. Only `gh api` GET calls + `git log` reads.
- **No PII beyond GitHub handles + commit data.** Don't pull emails or surface secrets that may appear in commit messages — redact strings matching common secret patterns before writing the report.
- **Cache window in mind.** If the user asks for the same window twice in one day, reuse the prior digest file if it exists rather than re-querying.

## Execution Steps

### 1. Load config
Read `.claude/team.yaml`. If missing, ask the user for:
- list of team GitHub logins
- list of repos (owner/name)
- weekly or daily window default

Then write the config and continue.

### 2. Resolve the window
- `daily` — yesterday 00:00 → 23:59 (local time). On Monday, expand to Fri-Sun.
- `weekly` — previous Monday 00:00 → previous Sunday 23:59.
- Custom — accept "since YYYY-MM-DD" or "last 7 days" from the user.

Convert to ISO-8601 (`since`, `until`) for `gh` queries.

### 3. Pull activity per person, per repo (parallel)
For each `(person, repo)` pair, run in parallel:

```bash
# Commits authored
gh api -X GET "repos/<owner>/<repo>/commits" \
  -f author="<login>" -f since="<since>" -f until="<until>" \
  --paginate --jq '.[] | {sha: .sha[0:7], msg: .commit.message | split("\n")[0], date: .commit.author.date}'

# PRs opened in window
gh search prs --author="<login>" --repo="<owner>/<repo>" \
  --created="<since>..<until>" --json number,title,state,url,createdAt,mergedAt

# PRs reviewed in window
gh search prs --reviewed-by="<login>" --repo="<owner>/<repo>" \
  --updated="<since>..<until>" --json number,title,url,updatedAt
```

Throttle: max 10 concurrent `gh` calls. `gh` honors GitHub rate limits automatically.

### 4. Aggregate
For each team member:
- Commits → group by repo, count + first 3 subjects
- PRs opened → list with state badge (🟢 merged, 🟡 open, 🔴 closed-unmerged)
- PRs reviewed → count + titles
- Inferred focus area — derive from changed file paths (`apps/frontend/*` → frontend, etc.) if available via `gh pr view --json files`

### 5. Redact secrets in messages
Before writing, scan each commit message and PR title for:
- API key patterns (`sk-...`, `AKIA...`, `gh[pousr]_...`, `xox.-...`)
- Replace with `[REDACTED]`. Log how many were redacted in the report footer.

### 6. Write the digest
File path: `<output_dir>/<window>-<ISO-date-range>.md`
Example: `docs/team-pulse/weekly-2026-05-12_2026-05-18.md`

Render order depends on `defaults.group_by` from `.claude/team.yaml`:
- `repo`   — only the "By Repo" section
- `person` — only the "By Person" section
- `both`   — both, repo first (default)

Template:
```markdown
# Team Pulse — <Weekly|Daily> · <YYYY-MM-DD> to <YYYY-MM-DD>

_Generated <today>. Repos scanned: <N>. Members tracked: <M>._

## Headline numbers
- Commits: **<total>** across <N> repos
- PRs opened: **<n>** · merged: **<n>** · open: **<n>**
- Reviews given: **<total>**

---

## By Repo

### `softaims/frontend-app`
**Total: 18 commits · 4 PRs (3 merged, 1 open) · 6 reviews**

| Person | Commits | PRs opened | PRs reviewed |
| --- | --- | --- | --- |
| Alice Khan (`alice-dev`)   | 12 | 3 (🟢 2 · 🟡 1) | 2 |
| Bob Singh (`bob-py`)       |  4 | 1 (🟢 1)        | 3 |
| Chi Wang (`chi-ai`)        |  2 | 0               | 1 |

Highlights:
- `a3f1b22` feat(auth): add OAuth callback handler — _alice-dev_
- 🟢 #482 — Add OAuth login flow — _alice-dev_
- 🟢 #488 — Add request logging middleware — _bob-py_

---

### `softaims/backend-api`
**Total: 9 commits · 2 PRs (2 merged) · 3 reviews**

| Person | Commits | PRs opened | PRs reviewed |
| --- | --- | --- | --- |
| Bob Singh (`bob-py`)       |  7 | 2 (🟢 2) | 1 |
| Alice Khan (`alice-dev`)   |  2 | 0        | 2 |

Highlights:
- `f1c9e08` fix(payments): handle stripe timeout retry — _bob-py_
- 🟢 #112 — Add idempotency keys to checkout — _bob-py_

---

_(repeat one section per repo)_

---

## By Person

### Alice Khan (`alice-dev`) — frontend
**Commits (14)** across 2 repos
- `frontend-app` (12): `a3f1b22` feat(auth): add OAuth..., `d8e0c14` fix(form): null-check..., _+ 10 more_
- `backend-api` (2):  `9a44e1c` chore(api): bump shared types

**PRs opened (3)**
- 🟢 #482 — Add OAuth login flow (frontend-app)
- 🟡 #491 — Refactor Button component variants (frontend-app)
- 🟢 #495 — Fix address null safety (frontend-app)

**PRs reviewed (4)** — frontend-app (2), backend-api (2)

---

### Bob Singh (`bob-py`) — backend
...

---

## Quiet this week
- _no one — everyone shipped 🎉_  OR  _Daniyal (`daniyal-x`) — no commits or PRs in window_

## Footer
- Redacted <N> potential secrets from commit messages / PR titles
- Run again: `team-pulse weekly` or `team-pulse since 2026-05-15`
```

### 7. Report
Print to the user:
- File path written
- One-line per-person summary (name + commits + PRs)
- Anyone with zero activity (so lead can check in)

## Usage Examples
- `team-pulse` → use defaults from config (weekly)
- `team-pulse daily` → yesterday only
- `team-pulse since 2026-05-10` → custom window from date to today
- `team-pulse for alice-dev` → single-person digest

## Output Style
Status lines from the skill match active session tone. The digest markdown itself stays normal prose so it's pasteable into Notion / Slack / Confluence without rewriting.
