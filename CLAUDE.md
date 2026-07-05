# Project: claude-code-boilerplate

Monorepo template optimized for Claude Code prompt caching and split-context agent workflows.

## Layout

```
claude-code-boilerplate/
├── .claudeignore            # token-blocker for unread artifacts
├── CLAUDE.md                # this file (global, cache-stable)
├── .claude/skills/          # domain rule packs (SKILL.md per topic)
│   ├── system-design/       # UI/UX modularity + reuse patterns
│   └── architecture/        # backend/AI routing + token discipline
└── apps/                    # split workspaces (local CLAUDE.md each)
    ├── frontend-ui/         # client app
    ├── backend-api/         # service layer
    └── ai-engine/           # model + inference layer
```

## Team Guidelines

- **Composition over duplication.** New UI = compose existing primitives in `apps/frontend-ui` before authoring.
- **Single source of truth per concern.** Auth → backend-api. Inference → ai-engine. Rendering → frontend-ui. No cross-bleed.
- **Type contracts at boundaries.** Inter-app data crosses through versioned schemas, not implicit shapes.
- **Small PRs.** One concern, < 400 LOC where possible. Bundle only when splitting is pure churn.
- **No speculative abstraction.** Extract on third repeat, not the first.

## Script Targets

Each `apps/<workspace>` exposes the same script names so tooling stays uniform:

| Script           | Purpose                              |
| ---------------- | ------------------------------------ |
| `dev`            | Local dev server / watcher           |
| `build`          | Production build                     |
| `test`           | Unit + integration tests             |
| `test:watch`     | Test runner in watch mode            |
| `lint`           | Static analysis                      |
| `typecheck`      | Type validation                      |
| `format`         | Code formatter                       |
| `clean`          | Wipe build artifacts                 |

Root script proxies (run from repo root):
- `pnpm -r <script>` — run across all workspaces
- `pnpm --filter <workspace> <script>` — target one workspace

## Git Workflow

- **Branches:** `feat/<scope>-<short-desc>`, `fix/<scope>-<short-desc>`, `chore/<scope>-<short-desc>`.
- **Commits:** Conventional Commits. Subject ≤ 50 chars. Body only when *why* isn't obvious.
- **Trunk:** `main` is always deployable. PRs squash-merge.
- **Pre-merge gates:** `lint`, `typecheck`, `test` must pass. CI enforces.
- **No force-push** to shared branches. Never bypass hooks (`--no-verify`) without explicit approval.

## Security & Compliance Policy (42-Rule Gate + OWASP Top 10)

Every code change MUST satisfy the 42 rules below. All checks are bundled inside the **`security-audit` skill** — there is no Makefile, npm script, or external CI harness. Backing scripts live at `.claude/skills/security-audit/scripts/NN-*.sh`; the orchestrator that writes an OWASP-mapped pen-test report is `scripts/pen-test-report.sh`. The report lands in `docs/security/pen-test-report-YYYY-MM-DD.md`.

**Before finalizing any code change, Claude MUST run the security-audit skill** (full gate via `run-all.sh`, or a specific rule via `NN-*.sh`). For release-readiness reviews or when the user asks for an audit, run `pen-test-report.sh`.

> ⚠️ "Unbreachable" is aspirational, not a reachable state. This gate is static heuristic analysis. It raises the bar; it does not eliminate risk. Pair it with quarterly external pen-tests, dependency scanning in CI, runtime WAF rules, and an incident-response playbook.

**Legend** — `S` Security · `R` Reliability · `O` Operability · `A` Architecture · `C` Compliance/UX

| # | Rule | Tags | Script |
|---|------|------|--------|
|  1 | Application + endpoint logging; CloudTrail/CloudWatch compatible; downtime email triggers wired. | S/R/O | `sec-01` |
|  2 | Sentry integrated for error-log capture; `Sentry.init` called at boot. | O | `sec-02` |
|  3 | Security, About Us, Contact Us pages exist (real or placeholder). | C | `sec-03` |
|  4 | Controllers scanned for IDOR + privilege-escalation patterns. | S | `sec-04` |
|  5 | DB configuration blocks public exposure (no `publicly_accessible = true`). | A | `sec-05` |
|  6 | No endpoints exposed without authentication — incl. event/notification listeners. | S | `sec-06` |
|  7 | S3 access via AWS presigned URLs with TTL ≤ 300 seconds (5 minutes). | A/S | `sec-07` |
|  8 | Origin/infra IPs masked; never echoed to clients. | S | `sec-08` |
|  9 | MFA enforced for client and admin accounts. | S/C | `sec-09` |
| 10 | Weglot designated for all translations (no parallel i18n pipelines). | C | `sec-10` |
| 11 | Timing-attack mitigations (constant-time compare) inside auth/login. | S | `sec-11` |
| 12 | Adhere to the classification framework above. | — | `sec-12` |
| 13 | Rate Limiting enforced globally AND per-user. | S/R | `sec-13` |
| 14 | Parameterized inputs + sanitization to block XSS, CSRF, SQL Injection. | S | `sec-14` |
| 15 | Every webhook endpoint verifies payload signatures (no unverified endpoints). | S | `sec-15` |
| 16 | Cloudflare proxying mandated for all public-facing web routes. | S/A | `sec-16` |
| 17 | CI pipelines include security-scanning steps (trivy/snyk/codeql/etc.). | R/O | `sec-17` |
| 18 | Unit, integration, and system tests required for logic paths. | R | `sec-18` |
| 19 | Staging restricted to whitelisted office network (IP allowlist). | A | `sec-19` |
| 20 | Strict, explicit CORS policy — no wildcards in production. | S | `sec-20` |
| 21 | File uploads validate type + sanitize metadata. | S | `sec-21` |
| 22 | Proactive OWASP Top 10 audit — flag obvious omissions. | S | `sec-22` |
| 23 | Working-tree scan for hardcoded secrets (broader than staged-diff). | S | `sec-23` |
| 24 | Dependency vulnerability scan (`pnpm/npm audit`, `pip-audit`). | S/R | `sec-24` |
| 25 | Container hardening — non-root USER, pinned tags, no `privileged: true`. | S/A | `sec-25` |
| 26 | TLS / HTTPS — HSTS header, no `http://` to prod hosts, TLS verify on. | S | `sec-26` |
| 27 | Password hashing — bcrypt/argon2/scrypt only; reject md5/sha-* on passwords. | S | `sec-27` |
| 28 | Cookie & session — HttpOnly + Secure + SameSite set wherever cookies issued. | S | `sec-28` |
| 29 | Input validation at boundaries — zod/joi/yup/pydantic/marshmallow/class-validator. | S | `sec-29` |
| 30 | SSRF defenses — block cloud metadata + private IPs on user-driven outbound. | S | `sec-30` |
| 31 | Unsafe deserialization — no `pickle.loads`, `yaml.load` without SafeLoader, `eval(JSON.parse)`. | S | `sec-31` |
| 32 | Open redirect — redirect URLs validated against allowlist / relative-only. | S | `sec-32` |
| 33 | Mass assignment — no spreading `req.body` straight into ORM create/update. | S | `sec-33` |
| 34 | Path traversal — file ops on user-controlled paths must normalize + allowlist. | S | `sec-34` |
| 35 | Command injection — no `exec`/`spawn`/`shell=True` with user input. | S | `sec-35` |
| 36 | Security headers — CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy. | S | `sec-36` |
| 37 | Body size limit — express/fastify/nginx body cap to block payload DoS. | S/R | `sec-37` |
| 38 | JWT hardening — no `alg=none`, explicit algorithms list, short TTL, secret from env. | S | `sec-38` |
| 39 | PII redaction in logs — no email/SSN/CC/password field names in log lines; logger redaction configured. | S/C | `sec-39` |
| 40 | Encryption at rest — RDS `storage_encrypted=true`, S3 SSE, EBS `encrypted=true`. | S/A | `sec-40` |
| 41 | Generic error responses — no exception text, stack traces, or "password too short / s3_key missing" leaked to clients; auth errors are uniform ("Invalid credentials"). | S | `sec-41` |
| 42 | Response-time normalization — auth/login paths use artificial delay or constant-time compare so timing oracles can't distinguish "no such user" from "wrong password". | S | `sec-42` |

### OWASP Top 10 (2021) Coverage

| OWASP category | Rules that cover it |
|---|---|
| A01 Broken Access Control | 4, 6, 19, 32 |
| A02 Cryptographic Failures | 22, 26, 27, 28, 40 |
| A03 Injection | 14, 21, 31, 33, 34, 35 |
| A04 Insecure Design | 13, 18, 37, 41, 42 |
| A05 Security Misconfiguration | 5, 7, 8, 16, 20, 25, 36 |
| A06 Vulnerable & Outdated Components | 24 |
| A07 Identification & Auth Failures | 9, 11, 29, 38 |
| A08 Software & Data Integrity | 15, 17, 23 |
| A09 Security Logging & Monitoring Failures | 1, 2, 39 |
| A10 Server-Side Request Forgery | 30 |

### Security Workflow — order of operations

This project is **Claude-driven**: there is no Makefile, no `npm run`, no CI harness. Everything runs via the `security-audit` skill (or by Claude invoking the underlying scripts directly through the Bash tool). There are **three distinct flows**. Pick the one that matches what you're doing.

#### A · Per-change flow (every PR, every commit)

```
edit code  →  /security-audit NN  →  /security-audit  →  fix fails  →  commit
              (rule(s) you         (full gate)        (re-run until
               touched)                                 clean)
```

1. **`/security-audit NN`** — run the rule(s) closest to the diff first. Fast feedback. Example: changed auth code → `/security-audit 4`, `/security-audit 27`, `/security-audit 42`.
2. **`/security-audit`** — full 42-rule sweep before pushing. Mandatory pre-merge gate.
3. **Fix any `FAIL`.** Never bypass the script; fix the underlying code. `WARN` is advisory — accept or address, document the choice in the PR.
4. **Commit** via `/git-push`.

#### B · Release / audit flow (pre-launch, quarterly, on request)

```
/security-audit pentest  →  open report  →  triage Critical/High  →  fix  →  re-run  →  attach to release
                         (writes docs/      (OWASP-mapped table)
                          security/*.md)
```

1. **`/security-audit pentest`** — runs all 42 rules and writes a dated markdown report under `docs/security/pen-test-report-YYYY-MM-DD.md`.
2. **Read the report.** Executive summary → severity rollup → OWASP Top 10 coverage table → finding details.
3. **Triage in order:** Critical → High → Medium → Low. The report puts them in that order.
4. **Fix the highest-severity findings first**, re-run `/security-audit NN` after each fix to confirm.
5. **Re-run `/security-audit pentest`** for a clean final report. Attach to the release notes / PR.

#### C · Single-rule debug flow

```
/security-audit NN  →  read output  →  fix code  →  /security-audit NN  →  pass
                       (FAIL/WARN     (source code,    (verify)
                        lines)        NOT the script)
```

Use when one rule keeps failing and you want a focused loop. Example: `/security-audit 36` keeps failing → add helmet + explicit CSP middleware → re-run → green.

#### Severity-to-action table

| Verdict | What to do |
|---------|------------|
| All `PASS` | Ship it. Pair with manual review for business-logic flaws static can't see. |
| `WARN` only | Acceptable. Document the accepted warnings in the PR description. |
| `FAIL` Low / Medium | Fix in the same PR if cheap. Otherwise log a ticket and link it. |
| `FAIL` High | Block merge. Fix before continuing. |
| `FAIL` Critical | Block release. Treat as P0 — drop other work. |

### Running the gate — under the hood

The skill calls these scripts via the Bash tool. You can invoke them directly too:

```bash
# Single rule (replace 04 with any 01..42)
bash .claude/skills/security-audit/scripts/04-access-control.sh

# Full gate
bash .claude/skills/security-audit/scripts/run-all.sh

# Pen-test report
bash .claude/skills/security-audit/scripts/pen-test-report.sh
bash .claude/skills/security-audit/scripts/pen-test-report.sh --stdout   # also print

# Discovery
ls .claude/skills/security-audit/scripts/
```

CI is intentionally not wired — this is a Claude-only repo. If you ever need CI gating, wrap `run-all.sh` in a GitHub Action that calls it and reads the exit code.

### Claude's responsibility

- After writing or modifying code in `apps/`, `infra/`, `.github/workflows/`, or any other surface touched by the rules, run the full gate (`bash .claude/skills/security-audit/scripts/run-all.sh`) before declaring the task complete.
- If a rule reports `FAIL`, fix the underlying issue; do not silence the script.
- If a rule reports `WARN`, decide whether it's a real risk; document the decision in the PR if accepted.
- New checks belong in `.claude/skills/security-audit/scripts/NN-<slug>.sh`. Update the rule table in this file and in the skill's `SKILL.md`. If the rule maps to an OWASP category, update `severity_of` / `owasp_of` in `pen-test-report.sh`.

## Quality & Architecture Gates (new skill pack)

Ten skills sit alongside the security stack. They are the lead's daily audit tool — invoke by name, no CI required.

### Code-quality lane
| Skill                  | Purpose                                                                                       |
| ---------------------- | --------------------------------------------------------------------------------------------- |
| `feature-review`       | Merge verdict + regression-risk map + approach critique for a PR / branch / feature name.      |
| `test-coverage-delta`  | New-lines-only coverage report vs base branch.                                                 |
| `complexity-check`     | Cyclomatic / cognitive / length / nesting ceilings per function + file.                        |
| `dead-code-scan`       | Unused exports, unreachable branches, orphan files.                                            |
| `dependency-hygiene`   | Unused / duplicate / outdated / license-risky third-party deps.                                |
| `perf-budget`          | Bundle-size, API p95, RN startup budgets baselined under `docs/perf/`.                         |
| `api-mock-parity`      | MSW / Storybook / JSON fixtures kept in sync with OpenAPI / DTO / pydantic schemas.             |

### Architecture lane
| Skill                  | Purpose                                                                                       |
| ---------------------- | --------------------------------------------------------------------------------------------- |
| `contract-drift-check` | Cross-workspace schema drift (frontend-ui ↔ backend-api ↔ ai-engine).                          |
| `migration-safety`     | DB migration hazards (Prisma / TypeORM / Knex / Alembic / raw SQL).                            |
| `adr-writer`           | Guided one-page Architecture Decision Records under `docs/adr/`.                               |

### Umbrella orchestrator — the evening ritual

- **`feature-audit <PR#|branch|feature-name>`** — one command. Fans out to every relevant sub-skill in parallel (feature-review, security-audit, null-safety-scan, complexity-check, test-coverage-delta, contract-drift-check, api-mock-parity, migration-safety, perf-budget, dead-code-scan, system-design, dependency-hygiene), synthesizes ONE report with ONE verdict under `docs/reviews/feature-audit-<date>-<slug>.md`.
- **`feature-audit --since 24h`** — batch mode for the nightly sweep. One digest row per feature merged today, aggregate rollup at the bottom. This is what the lead pastes into Slack at 7pm.

### When the lead runs what (finer-grained)

- **Every PR (junior work):** `feature-audit <PR#>` (or `feature-review <PR#>` for a lighter run).
- **PR touches shared types / OpenAPI / DTOs:** `contract-drift-check` + `api-mock-parity` (auto-selected by `feature-audit`).
- **PR touches `migrations/` / `prisma/schema.prisma`:** `migration-safety` (auto).
- **PR adds a new lib / architecture pattern:** `adr-writer` (nudge, does not auto-write).
- **PR touches hot paths / bundles:** `perf-budget` (auto).
- **Weekly hygiene sweep:** `dead-code-scan` + `dependency-hygiene` (also auto if deps changed).

Each skill writes a paper trail under `docs/<domain>/` so the lead has an audit history without opening the terminal each time.

## Cache Discipline

This file lives at the top of the context window — it must stay stable to preserve prompt-cache hits across turns. Volatile workspace details belong in the per-app `CLAUDE.md` under `apps/<workspace>/`. Edit those for local concerns; edit this only for repo-wide policy.
