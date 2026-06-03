# claude-code-boilerplate

Monorepo template optimised for Claude Code prompt caching and split-context agent workflows. Ships with a 42-rule security & compliance gate, an OWASP-mapped pen-test report generator, and 10 reusable Claude Code skills that automate the repetitive parts of day-to-day engineering.

```
claude-code-boilerplate/
├── CLAUDE.md                # project policy + security gate (always in Claude's context)
├── README.md                # this file
├── .claude/
│   ├── skills/              # 10 skills — markdown rules + any supporting scripts
│   │   └── security-audit/
│   │       ├── SKILL.md     # tells Claude how to drive the audit
│   │       └── scripts/     # 42 rule scripts + pen-test-report.sh orchestrator
│   ├── hooks/               # event hooks
│   ├── settings.json        # permissions / env
│   └── team.yaml            # team-pulse config
├── apps/                    # frontend-ui · backend-api · ai-engine (per-app CLAUDE.md each)
└── docs/                    # generated artifacts (security reports, team digests, feature docs)
```

This repo is **Claude-driven**: no Makefile, no `npm run`, no CI harness. Every workflow runs through a skill (or Claude calling a script via the Bash tool).

---

## How skills work

A **skill** is a markdown file under `.claude/skills/<name>/SKILL.md` that tells Claude how to behave when you say a trigger phrase. They are *not* installed packages — they are prompt rules with a frontmatter description. When Claude sees the trigger, it loads the skill content and follows it.

**Invoke a skill** by either:
- Typing `/<skill-name>` in chat (e.g. `/security-audit`).
- Saying one of the trigger phrases listed in the skill's description (e.g. "run security check").

**Common pattern across most skills here:**
1. Skill loads its rules.
2. Claude runs a backing script (e.g. `.claude/skills/security-audit/scripts/run-all.sh`) or a `git`/`gh` command via the Bash tool.
3. Claude reports a summary table — not the full transcript.
4. Claude asks whether to fix, commit, or open a PR.

---

## Skills index

| Skill | One-line purpose | Invoke with |
|---|---|---|
| [security-audit](#security-audit) | 42-rule pen-tester gate + OWASP report | `/security-audit`, "pen test", "run the 42 rules" |
| [security-scan](#security-scan) | Pre-commit secret scan on staged diff | `/security-scan`, "scan for secrets" |
| [pre-merge-check](#pre-merge-check) | Lint + typecheck + tests in parallel | `/pre-merge-check`, "is this ready to merge" |
| [null-safety-scan](#null-safety-scan) | Null/undefined/None audit on staged files | `/null-safety-scan`, "audit nullables" |
| [system-design](#system-design) | End-to-end architecture & race-condition review | `/system-design`, "design review" |
| [git-push](#git-push) | Stage-aware commit-message + push | `/git-push`, "push my code" |
| [pr-open](#pr-open) | Open PR with auto-filled title + checklist | `/pr-open`, "open a PR" |
| [team-pulse](#team-pulse) | Weekly team activity digest | `/team-pulse`, "weekly progress" |
| [generate-docs](#generate-docs) | Feature documentation from recent changes | `/generate-docs` |
| [react-native-optimization-and-architecture](#react-native-optimization-and-architecture) | RN/Expo perf + module guidance | mention React Native / Expo |

---

### security-audit

**What it does** — runs the project's 42-rule security & compliance gate against the working tree and writes an OWASP-mapped pen-test report.

**Triggers** — `/security-audit`, `pen test`, `pentest`, `run security check`, `audit my code`, `owasp scan`, `compliance check`, `is this production ready`.

**Three modes:**

| Phrase | What runs | Output |
|---|---|---|
| `/security-audit` | `scripts/run-all.sh` | Concise summary table in chat |
| `/security-audit 14` (or `audit cors`) | `scripts/14-injection.sh` | Full output for one rule |
| `/security-audit pentest` (or `pen test`) | `scripts/pen-test-report.sh` | Markdown report → `docs/security/pen-test-report-YYYY-MM-DD.md` |

**Direct invocation** (Claude calls these via the Bash tool — you'd only run them yourself if you're at a terminal outside Claude Code):
```bash
bash .claude/skills/security-audit/scripts/run-all.sh                  # all 42 rules
bash .claude/skills/security-audit/scripts/04-access-control.sh        # single rule
bash .claude/skills/security-audit/scripts/pen-test-report.sh          # full audit report
```

See [§ Security audit workflow](#security-audit-workflow) below for the canonical order.

---

### security-scan

**What it does** — scans the **staged diff** (`git diff --cached`) for hardcoded secrets, API keys, AWS/GCP credentials, JWTs, private keys, and `.env` content. Blocks commits that contain high-confidence matches.

**Triggers** — `/security-scan`, `secret check`, `scan for secrets`.

**Difference from rule 23 in security-audit:** rule 23 scans the whole working tree (broader). `security-scan` is the **pre-commit gate** — narrower, faster, blocks accidental pushes.

**Typical use:**
```
stage changes  →  /security-scan  →  pass  →  /git-push
                                  →  fail  →  remove the secret, re-stage
```

---

### pre-merge-check

**What it does** — runs lint + typecheck + tests in parallel across the monorepo. TS/JS uses eslint + tsc + jest/vitest. Python uses ruff + mypy + pytest. Hard-fails on any error.

**Triggers** — `/pre-merge-check`, `is this ready to merge`, `run all checks`.

**Typical use:**
```
finish feature  →  /pre-merge-check  →  green  →  /pr-open
                                     →  red    →  fix, re-run
```

---

### null-safety-scan

**What it does** — flags unguarded property access (`user.profile.name` without checking `user`), missing optional chaining, unchecked function returns, unsafe array/dict access, missing defaults on params.

**Triggers** — `/null-safety-scan`, `check null safety`, `audit nullables`.

**Scope:** staged files only (TS/JS/Python). Run before merging risky logic — auth flows, payment paths, anything where `undefined` lands you in a 500.

---

### system-design

**What it does** — end-to-end architecture auditor for stacks spanning a React Native client, a NestJS backend, and a Python AI service. Traces cross-service contracts, race conditions, concurrency, performance budgets, production readiness, and UI/UX modularity.

**Triggers** — `/system-design`, `design review`, `architecture review`, `race condition check`, `is this production ready`, or mentioning *production*, *scale*, *race condition*, *deadlock*, *flaky behavior*, *latency budget*, *contract drift*, *rollout risk*.

**Use it** when:
- Designing a new cross-service feature.
- Investigating a flaky/intermittent bug that might be a race.
- Reviewing readiness before a release.

It will trace peers (frontend ↔ backend ↔ AI) even when you only share one side.

---

### git-push

**What it does** — reviews staged files for edge cases and null-safety, generates a Conventional Commit message from the diff, asks you to confirm, then commits and pushes **only the already-staged files**. Never stages files you didn't pick.

**Triggers** — `/git-push`, `push my code`, `commit and push staged`.

**Typical use:**
```
git add <files>  →  /git-push  →  confirm message  →  done
```

Pairs naturally with `/security-scan` before, and `/pr-open` after.

---

### pr-open

**What it does** — opens a GitHub PR from the current branch. Auto-fills title, summary, and test-plan checklist by reading the diff against the base branch (`main` by default). Pushes the branch if it isn't already remote.

**Triggers** — `/pr-open`, `open a PR`, `raise a PR`, `create pull request`.

**Typical use:** after `/git-push`, when the branch is ready for review.

---

### team-pulse

**What it does** — aggregates daily or weekly engineering activity across a configured list of repos and team members (commits, PRs opened/merged, reviews) and writes a markdown digest to `docs/team-pulse/` that a lead can paste into Notion/Slack.

**Triggers** — `/team-pulse`, `weekly progress`, `team activity`, `who did what this week`, `team report`.

**Config** — `.claude/team.yaml` (repos + handles).

**Output format** — plain-English Summary + Highlights up top, SHAs only in a bottom "Commit Trail" (client-facing).

---

### generate-docs

**What it does** — analyses recent git changes (or specific files you point at) and writes clear, human-readable feature documentation. Saves to `docs/features/`.

**Triggers** — `/generate-docs`, "document this feature", "write docs for the last change".

**Use after** landing a feature, before handing it to the team / non-engineering stakeholders.

---

### react-native-optimization-and-architecture

**What it does** — applies React Native + Expo best practices: list performance (FlashList, key extraction, getItemLayout), animations (Reanimated worklets, native driver), native modules, memory, navigation, image pipeline, build/CI tips.

**Triggers** — automatically activates when you mention React Native, Expo, mobile performance, native modules, or work inside `apps/frontend-ui/` if it's an RN app.

**Use it** when building or optimising any RN component, especially lists, animations, or anything touching the bridge.

---

## Security audit workflow

The most-used flow in this repo. Mirrors the order documented in `CLAUDE.md`.

### Per-change flow (every commit, every PR)

```
edit code
  → /security-audit NN       # run the rules nearest your diff first
  → /security-audit          # full 42-rule gate before pushing
  → fix any FAIL             # never silence the script; fix the code
  → /security-scan           # block secrets in staged diff
  → /pre-merge-check         # lint + typecheck + tests
  → /git-push                # commit + push
  → /pr-open                 # open PR
```

### Release / audit flow

```
/security-audit pentest                            # full sweep + report
  → open docs/security/pen-test-report-*.md        # OWASP-mapped, severity-ranked
  → triage Critical → High → Medium → Low
  → fix highest-severity first
  → re-run /security-audit NN per fix
  → /security-audit pentest  # final clean report
  → attach report to release / PR
```

### Single-rule debug

```
/security-audit NN
  → read FAIL output
  → fix code (not the script)
  → /security-audit NN       # verify
```

### Why no CI?

This repo is intentionally Claude-only. Skills are the entire driver. If you ever need a CI gate, point a GitHub Action at `bash .claude/skills/security-audit/scripts/run-all.sh` and read the exit code — but that's outside the boilerplate's scope.

### Severity → action

| Verdict | What to do |
|---|---|
| All PASS | Ship it. |
| WARN only | Document the accepted warnings in the PR. Ship. |
| FAIL Low / Medium | Fix in the same PR if cheap. Otherwise ticket + link. |
| FAIL High | Block merge. Fix before continuing. |
| FAIL Critical | Block release. P0. |

### Command reference

The skill drives these from chat. They also work directly via the Bash tool:

```bash
# Per-rule
bash .claude/skills/security-audit/scripts/04-access-control.sh        # rule 04

# Full gate
bash .claude/skills/security-audit/scripts/run-all.sh                  # all 42 rules; non-zero exit on FAIL

# Pen-test report
bash .claude/skills/security-audit/scripts/pen-test-report.sh          # writes docs/security/pen-test-report-YYYY-MM-DD.md
bash .claude/skills/security-audit/scripts/pen-test-report.sh --stdout # also prints to terminal

# Discovery
ls .claude/skills/security-audit/scripts/
```

### The 42 rules + OWASP mapping

See `CLAUDE.md` for the full rule table and the OWASP Top 10 (2021) coverage map. Highlights:

- **A01 Broken Access Control** — rules 4, 6, 19, 32
- **A02 Cryptographic Failures** — rules 22, 26, 27, 28, 40
- **A03 Injection** — rules 14, 21, 31, 33, 34, 35
- **A04 Insecure Design** — rules 13, 18, 37, 41, 42
- **A05 Security Misconfiguration** — rules 5, 7, 8, 16, 20, 25, 36
- **A06 Vulnerable Components** — rule 24
- **A07 Identification & Auth Failures** — rules 9, 11, 29, 38
- **A08 Software & Data Integrity** — rules 15, 17, 23
- **A09 Logging & Monitoring Failures** — rules 1, 2, 39
- **A10 SSRF** — rule 30

---

## Adding a new skill or rule

### New skill

```
.claude/skills/<name>/SKILL.md
```

Frontmatter shape:
```yaml
---
name: <kebab-name>
description: One sentence that names triggers explicitly (e.g. "Use when the user types 'X' or 'Y'…"). Claude matches on these phrases.
---
```

Body = the rules Claude should follow. Be specific about which scripts to run, what to report, and what to do on failure.

### New security rule

1. Add `.claude/skills/security-audit/scripts/NN-<slug>.sh` (next free number; source `_lib.sh`).
2. `chmod +x` the new script.
3. Add a row to the rule table and the OWASP mapping in `CLAUDE.md`.
4. Add a row to the rule table in `.claude/skills/security-audit/SKILL.md`.
5. If it maps to an OWASP category, update `severity_of` / `owasp_of` in `.claude/skills/security-audit/scripts/pen-test-report.sh`.
6. Run `/security-audit pentest` to confirm it appears in the report.

---

## Honest scope

- The security gate is **static heuristic analysis** — grep-based. False positives and false negatives are possible. Every failing finding includes the raw scan output so you can confirm.
- Skills automate the *repetitive* parts of engineering. They do **not** replace code review, manual pen-testing, or thinking before you write code.
- "Unbreachable" doesn't exist. This gate raises the bar. Pair it with quarterly external pen-tests, dependency scanning in CI, runtime WAF rules, and an incident-response playbook.
