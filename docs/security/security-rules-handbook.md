# Security Rules Handbook

**Project:** `claude-code-boilerplate`
**Audience:** Engineering team (developers, reviewers, release captains)
**Purpose:** A single reference that explains every security check enforced in this repository — what it defends against, how the script detects a violation, and how to fix it when it fails.
**Format:** Print-ready. Convert to PDF for distribution.

---

## Table of Contents

0. [Quick Reference Card](#0-quick-reference-card)
1. [How This Gate Works](#1-how-this-gate-works)
2. [The Four Modes of the `security-audit` Skill](#2-the-four-modes-of-the-security-audit-skill)
3. [Workflow Cheat Sheet](#3-workflow-cheat-sheet)
4. [Severity, OWASP Mapping, and the Report](#4-severity-owasp-mapping-and-the-report)
5. [Masking Sensitive Findings](#5-masking-sensitive-findings)
6. [API Response Over-Sharing Audit (`api-mask`)](#6-api-response-over-sharing-audit-api-mask)
7. [The 42 Rules — Detailed Reference](#7-the-42-rules--detailed-reference)
8. [Appendix A — Tag Legend](#appendix-a--tag-legend)
9. [Appendix B — OWASP Top 10 (2021) Coverage Matrix](#appendix-b--owasp-top-10-2021-coverage-matrix)
10. [Appendix C — Limitations & What This Gate Does *Not* Cover](#appendix-c--limitations--what-this-gate-does-not-cover)

---

## 0. Quick Reference Card

> **Print this page.** Pin it next to your monitor. Every other section in this handbook expands on what is summarized here.

### Run commands

| Goal | Command |
|---|---|
| Full 42-rule sweep | `/security-audit` |
| Run one rule (replace `NN`) | `/security-audit NN` |
| API over-sharing audit | `/security-audit api-mask` |
| Dated pen-test report | `/security-audit pentest` |
| Mask a finding before sharing | `bash .claude/skills/security-audit/scripts/mask-findings.sh <path> --apply` |

### Rules at a glance — severity + one-line fix

**Critical (block release):**

| # | Rule | One-line fix |
|---|---|---|
| 04 | Access Control (IDOR) | Always join lookups on `ownerId = currentUser.id` |
| 06 | Auth on every endpoint | Add `@UseGuards` / `Depends(auth)` / signature check on webhooks |
| 14 | XSS / CSRF / SQLi | Parameterized queries + DOMPurify + SameSite cookies |
| 15 | Webhook signatures | `stripe.webhooks.constructEvent(body, sig, secret)` or HMAC |
| 22 | Proactive OWASP | No `md5/sha1` on creds, no `eval`, no disabled TLS, no literal secrets |
| 23 | Secrets in tree | Move to env vars / secret manager; rotate if leaked |
| 27 | Password hashing | `bcrypt.hash(plaintext, 12)` — never `sha256` |
| 30 | SSRF | Validate user URLs: allowlist + reject private IPs |
| 31 | Deserialization | `yaml.safe_load` + no `pickle.loads` on user data |
| 35 | Command injection | `spawn(cmd, [args])` — never string-interpolated `exec` |
| 38 | JWT hardening | Explicit `algorithms: ['HS256']`, short TTL, secret from env |
| 41 | Generic errors | `"Invalid credentials"` — never echo `err.message` |
| 42 | Timing normalization | Run dummy `bcrypt.compare` even when user not found |

**High (block merge):**
01 Logging · 05 Private DB · 07 S3 TTL ≤ 5m · 08 IP obfuscation · 09 MFA · 11 Constant-time compare · 13 Rate limit per-user · 16 Cloudflare proxy · 17 CI security scan · 20 No `*` CORS · 21 Upload MIME/type check · 24 Dep audit clean · 25 Non-root container · 26 HSTS + HTTPS · 28 Cookie flags · 32 Open redirect · 33 Mass assignment · 34 Path traversal · 36 Security headers · 37 Body limit · 40 Encryption at rest

**Medium (fix this sprint):**
02 Sentry · 18 Test layers · 29 Validation lib · 39 PII redaction

**Low (track):**
03 Core pages · 10 Weglot · 12 Legend · 19 Staging allowlist

### Verdict → action

| Result | Do |
|---|---|
| All `PASS` | Ship |
| `WARN` only | Document accepted warnings in PR |
| `FAIL` Low/Med | Fix in PR if cheap; else file ticket |
| `FAIL` High | Block merge |
| `FAIL` Critical | Block release. P0. |

### Before sharing any scan output externally

```
bash .claude/skills/security-audit/scripts/mask-findings.sh <path>           # dry-run
bash .claude/skills/security-audit/scripts/mask-findings.sh <path> --apply   # rewrite
```

Masks: public IPs, AWS account IDs, AKIA keys, JWTs, `sk_`/`sk-` API keys, emails.

---

## 1. How This Gate Works

This repository ships with a **static heuristic security gate** that runs locally via the Claude Code `security-audit` skill. There is no Makefile, no `npm run security`, and no CI harness wiring required. Every check is a self-contained Bash script under:

```
.claude/skills/security-audit/scripts/
  ├── _lib.sh                      # shared helpers (find, grep, pass/fail, color)
  ├── 01-logging-monitoring.sh     # Rule 01
  ├── 02-error-tracking.sh         # Rule 02
  ├── …                            # one script per rule, 01 → 42
  ├── 42-timing-normalization.sh   # Rule 42
  ├── run-all.sh                   # runs every rule, prints summary, exits non-zero on fail
  ├── pen-test-report.sh           # runs everything + writes a dated OWASP-mapped report
  ├── api-mask-audit.sh            # static portion of the response-over-sharing audit
  └── mask-findings.sh             # rewrites IPs / keys / emails / JWTs to safe masks
```

Each rule script follows the same shape:

1. **Source** the shared library (`_lib.sh`) for `pass`, `warn`, `fail`, `header`, `finish`, and the cross-workspace `find` / `grep` helpers.
2. **Declare** `RULE_ID`, `RULE_NAME`, and `RULE_TAGS` (e.g. `S/R/O`).
3. **Print** a header.
4. **Scan** the workspace roots — `apps/`, `infra/`, `terraform/`, `.github/`, plus any root configs the rule cares about — using `grep` + `find`.
5. **Emit** one or more of:
   - `pass` (green check) — heuristic found the safe pattern.
   - `warn` (yellow `!`) — suspicious; review and decide.
   - `fail` (red ✗) — clear violation; **must be fixed**.
6. **Exit** non-zero if any `fail` was raised. `warn` alone exits zero.

### Why static heuristics, not a "real" scanner?

- **Zero install.** Engineers and Claude can run it instantly — no Snyk account, no Docker image, no auth tokens.
- **Tuned to this repo.** It knows our layout (`apps/frontend-ui`, `apps/backend-api`, `apps/ai-engine`).
- **Fast feedback.** Every script finishes in seconds.
- **Auditable.** The check is a few lines of `grep`. You can read it. You can override it. You can extend it.

The trade-off is honest: this is a **heuristic** layer. False positives and false negatives are both possible. The gate raises the bar; it does not replace dependency scanning in CI, dynamic testing (DAST), or an annual external pen-test. See [Appendix C](#appendix-c--limitations--what-this-gate-does-not-cover) for the explicit scope-out.

---

## 2. The Four Modes of the `security-audit` Skill

The skill is the entry point engineers and Claude both use. It has four discrete modes — pick the one that matches the moment.

### Mode 1 — Quick Gate (full 42-rule sweep)

**Trigger:** `/security-audit`, `pre-merge`, "run security check", "owasp scan".
**What it does:** Runs `run-all.sh`, which executes every `NN-*.sh` script in numeric order, aggregates pass/warn/fail counts, and exits non-zero on any failure.
**When to use:** Before opening a PR. Before squash-merging to `main`. Any change touching `apps/`, `infra/`, or `.github/workflows/`.
**Output:** Per-rule lines on stdout, then a summary block listing failed rule IDs.

### Mode 2 — Single-Rule Deep-Dive

**Trigger:** `/security-audit 27`, `/security-audit NN` (any rule number 01–42).
**What it does:** Runs one script in isolation so you can read its findings without scrolling through 41 others.
**When to use:** A specific rule keeps failing; you want a tight edit-run-edit loop. Example: `27` (password hashing) is red → switch from `sha256` to `bcrypt` → re-run `27` → green.

### Mode 3 — API Response Over-Sharing Audit (`api-mask`)

**Trigger:** `/security-audit api-mask`.
**What it does:** Runs `api-mask-audit.sh`, which **does not** make a pass/fail verdict on its own. It outputs four signal sets — sensitive entity fields, controller response shapes, service hydration context, socket emit hints — and the agent layers semantic reasoning on top to produce a CLEAN / LEAKING / PARTIAL classification per endpoint.
**When to use:** Before exposing any new endpoint. After modifying entities or service `.find()` calls. Routinely before a release.
**Output:** Saved to `docs/security/api-mask-audit-YYYY-MM-DD.md` after the agent finishes the semantic pass.

### Mode 4 — Full Pen-Test Report

**Trigger:** `/security-audit pentest`, "pen test", "compliance check".
**What it does:** Runs `pen-test-report.sh` — same 42 rules, but instead of just printing pass/fail, it builds a **markdown report** with:
- Executive summary
- Severity rollup (Critical / High / Medium / Low)
- OWASP Top 10 (2021) coverage table
- Findings table with raw scan output inside collapsible `<details>` blocks
- Methodology + recommended next steps
- Saved to `docs/security/pen-test-report-YYYY-MM-DD.md` and committed.

**When to use:** Pre-launch readiness review. Quarterly audit. When the user asks for an audit. Attach the report to the release PR.

---

## 3. Workflow Cheat Sheet

| Situation | Run | What you get |
|---|---|---|
| Wrote new code, about to commit | `/security-audit` | Full pass/fail across all 42 rules |
| One rule keeps failing | `/security-audit NN` | Just that rule, with line-level output |
| Building / changing API response shapes | `/security-audit api-mask` | Endpoint-level over-sharing report |
| Pre-release, quarterly, or external request | `/security-audit pentest` | OWASP-mapped markdown report under `docs/security/` |
| Need to share a report externally | Run `mask-findings.sh <report>` first | IPs, keys, emails, JWTs masked |

### Order of operations for a normal PR

1. Make the change.
2. Run **`/security-audit NN`** for the rule(s) most affected by your diff (fast feedback).
3. Run **`/security-audit`** for the full sweep before pushing (mandatory).
4. Resolve every `FAIL`. Decide on every `WARN` and document the choice in the PR.
5. Commit, push, open PR.

### Severity-to-action table

| Verdict | What to do |
|---|---|
| All `PASS` | Ship it. Pair with manual review for business-logic flaws static can't see. |
| `WARN` only | Acceptable. Document accepted warnings in the PR description. |
| `FAIL` — Low / Medium | Fix in the same PR if cheap. Otherwise log a ticket and link it. |
| `FAIL` — High | Block merge. Fix before continuing. |
| `FAIL` — Critical | Block release. Treat as P0 — drop other work. |

---

## 4. Severity, OWASP Mapping, and the Report

The pen-test orchestrator (`pen-test-report.sh`) assigns severity per rule using a fixed table, then maps each rule to its primary OWASP Top 10 (2021) category.

### Severity tiers (from the orchestrator)

| Severity | Meaning | Rules |
|---|---|---|
| **Critical** | Direct path to RCE, auth bypass, or data exfiltration. Block release. | 04, 06, 14, 15, 22, 23, 27, 30, 31, 35, 38, 41, 42 |
| **High** | Exploitable under common conditions, or material defense-in-depth gap. | 01, 05, 07, 08, 09, 11, 13, 16, 17, 20, 21, 24, 25, 26, 28, 32, 33, 34, 36, 37, 40 |
| **Medium** | Defense-in-depth or information leak. Schedule for next sprint. | 02, 18, 29, 39 |
| **Low** | Compliance / UX / process hygiene. Track in backlog. | 03, 10, 12, 19 |

### OWASP Top 10 (2021) primary mapping

| OWASP Category | Rules |
|---|---|
| A01 — Broken Access Control | 04, 06, 19, 32 |
| A02 — Cryptographic Failures | 22, 26, 27, 28, 40 |
| A03 — Injection | 14, 21, 31, 33, 34, 35 |
| A04 — Insecure Design | 13, 18, 37, 41, 42 |
| A05 — Security Misconfiguration | 05, 07, 08, 16, 20, 25, 36 |
| A06 — Vulnerable & Outdated Components | 24 |
| A07 — Identification & Authentication Failures | 09, 11, 29, 38 |
| A08 — Software & Data Integrity Failures | 15, 17, 23 |
| A09 — Security Logging & Monitoring Failures | 01, 02, 39 |
| A10 — Server-Side Request Forgery | 30 |

### The verdict logic

After the sweep, the report computes a verdict:

- **`PASS`** — zero `FAIL` results.
- **`PASS (with medium findings)`** — only Medium failures.
- **`FAIL`** — any Critical or High failure.

This single line at the top of the report drives release decisions.

---

## 5. Masking Sensitive Findings

Anything written to `docs/security/` is committable. That means raw scan output may contain real IPs, AWS account IDs, JWTs, API keys, or customer emails — and we do not want those in git history.

### The `mask-findings.sh` script

```
bash .claude/skills/security-audit/scripts/mask-findings.sh <path>           # dry-run; reports hits
bash .claude/skills/security-audit/scripts/mask-findings.sh <path> --apply   # rewrites in place
```

**What it masks:**

| Pattern | Example before | Example after |
|---|---|---|
| Public IPv4 (skips RFC1918, loopback, link-local, multicast) | `54.231.10.42` | `54.231.***.***` |
| AWS account ID (12-digit) | `123456789012` | `***456789012` (last 3 kept for reference) |
| AWS access key ID | `AKIAIOSFODNN7EXAMPLE` | `AKIA***MPLE` |
| JWT (three base64url segments) | `eyJhbGciOi...eyJzdWI...sig` | `eyJ***[jwt-redacted]` |
| Stripe / Anthropic / OpenAI style keys (`sk_live_`, `sk-ant-`, `sk-`) | `sk_live_abc123...` | `sk_live_***` |
| Emails | `alice@acme.com` | `a***@acme.com` |

**Exit codes:**
- `0` — clean (no hits) **or** `--apply` succeeded.
- `1` — dry-run found hits; review then re-run with `--apply`.
- `2` — invalid usage / file not found.

### When to run it

- **Always** before committing anything under `docs/security/`.
- Before pasting a report into Slack, email, or any external system.
- Whenever an engineer screenshots scan output for a ticket.

---

## 6. API Response Over-Sharing Audit (`api-mask`)

The `api-mask-audit.sh` script is the static half of a two-stage audit. It does **not** decide what is leaking — it surfaces every signal an agent needs to make that judgment.

### What it surfaces

1. **Entity fields by sensitivity.** Scans `*.entity.ts`, `*.model.ts`, `*.schema.ts`, and `schema.prisma` files in `apps/backend-api/`. Bucketizes each field into:
   - **SECRET** — `password`, `passwordHash`, `verificationToken`, `accessToken`, `refreshToken`, `sessionToken`, `apiKey`, `privateKey` and their snake_case variants. *Must never leave the server.*
   - **SELF-ONLY** — `email`, `phone`, `stripeCustomerId`, `subscriptionStatus`, `licenseTier`, `organizationId`, `isAdmin`, `isVerified`, `dob`, `address`, `ssn`, `taxId`. *Returnable only to the requester themselves.*
   - **IDENTIFYING** — `firstName`, `lastName`, `fullName`, `address`, `dateOfBirth`. *Limit by role / relationship.*

2. **Controller response patterns.** Flags shapes that suggest an entity is being returned whole:
   - **BARE IDENTIFIER** — `res.json(user)` style — a single non-trivial variable.
   - **SPREAD** — `res.json({ ...entity, extra })` — entity fields merged in.
   - **AWAIT PASSTHROUGH** — `res.json(await service.find(...))` — service result piped straight to client.

3. **Service finds: hydration context.** For each `.find()` / `.findOne()` / `.findUnique()` etc., prints the next 7 lines. **This is the load-bearing signal**: a `find()` that does not hydrate the auth/credential relation **cannot** leak `passwordHash` / `email` / `role` no matter what shape the controller returns. The reading rule is: don't flag based on missing `select` alone — check what relations are pulled.

4. **Socket emit payload hints.** `io.emit()` calls — same over-share risk as HTTP, easier to miss in code review.

### The agent's job

Read the static output, walk the listed files, then produce the semantic table in `docs/security/api-mask-audit-YYYY-MM-DD.md`:

- Match each controller response → service call → entity returned.
- Cross-reference with the route file to know **who can hit each endpoint** (admin? owner? public?).
- Categorize each endpoint as **CLEAN / LEAKING / PARTIAL** and assign **HIGH / MEDIUM / LOW** risk.

**Always run `mask-findings.sh` on the resulting report before committing.**

---

## 7. The 42 Rules — Detailed Reference

Every rule below uses a consistent structure:

- **Tags** — one or more of S (Security), R (Reliability), O (Operability), A (Architecture), C (Compliance/UX).
- **Severity** — Critical / High / Medium / Low (from the report's severity table).
- **OWASP** — primary OWASP Top 10 (2021) category.
- **Threat** — what attack or failure mode this rule defends against, in plain language.
- **What the script checks** — the actual heuristic, in detail.
- **How to pass** — concrete remediation patterns.
- **Run** — the exact shell command.

> ⚠️ **Run command shorthand.** Every script lives under `.claude/skills/security-audit/scripts/`. For brevity, paths below are abbreviated to `scripts/NN-name.sh`. Run from repo root.

---

### Rule 01 — Logging & Monitoring

- **Tags:** S/R/O · **Severity:** High · **OWASP:** A09 — Security Logging & Monitoring Failures
- **Script:** `scripts/01-logging-monitoring.sh`

**Threat.** Without structured logs, you cannot detect breaches, debug production issues, or prove compliance. Without downtime alerting, your first sign of an outage is an angry customer. A09 in OWASP exists because most breaches are dwell-time problems — the attacker had access for weeks because nobody was looking.

**What the script checks.**
1. Counts references to structured loggers across `apps/`, `infra/`, `.github/`, `terraform/`: `winston`, `pino`, `bunyan`, NestJS `Logger`, Python `structlog`, `loguru`, `logging.info/warning/error/debug`. **Zero hits → FAIL.**
2. Counts CloudWatch / CloudTrail integration markers (`CloudWatch`, `CloudTrail`, `aws-sdk.*logs`, `@aws-sdk/client-cloudwatch`). Zero → **WARN** (log shipping may be handled at infra layer).
3. Counts downtime-alerting markers: `/health` or `/healthz` endpoints, `SNS`, `sns:Publish`, `sendDowntimeEmail`, `uptime-robot`, `uptime-kuma`, `statuscake`, `pingdom`. **Zero → FAIL.**

**How to pass.**
- Pick a structured logger per workspace and use it everywhere: `winston` or `pino` for Node, NestJS `Logger`, Python `structlog`. Don't use `console.log` for production paths.
- Expose a `/health` (or `/healthz`) endpoint that returns 200 when dependencies are reachable.
- Wire an uptime monitor (UptimeRobot, Pingdom, StatusCake) to hit `/health` every minute and email/Slack on failure.
- Configure log shipping to CloudWatch (or your provider) at the infra layer; reference the integration in code or Terraform.

---

### Rule 02 — Error Tracking (Sentry)

- **Tags:** O · **Severity:** Medium · **OWASP:** A09
- **Script:** `scripts/02-error-tracking.sh`

**Threat.** Unhandled exceptions silently lose user trust. Without aggregation, you cannot tell whether a deploy caused a regression. Sentry (or equivalent) is the canonical answer.

**What the script checks.**
1. Counts references to `@sentry/`, `sentry_sdk`, `Sentry.init`, `sentry.io`, or the env var `SENTRY_DSN`. **Zero hits → FAIL.**
2. If Sentry is referenced but no `Sentry.init` / `sentry_sdk.init` call site exists → **WARN** (likely imported but never initialized).

**How to pass.**
- `npm install @sentry/node` (or `@sentry/react`, or `pip install sentry-sdk`).
- Call `Sentry.init({ dsn: process.env.SENTRY_DSN, ... })` at the very top of your app entrypoint (`main.ts`, `index.js`, `wsgi.py`).
- Pass `SENTRY_DSN` via env (do **not** hardcode).
- Add release tagging and environment tagging so deploys are distinguishable.

---

### Rule 03 — Core Pages (Security / About / Contact)

- **Tags:** C · **Severity:** Low · **OWASP:** — (compliance)
- **Script:** `scripts/03-core-pages.sh`

**Threat.** Compliance + trust. Missing "Security" / "About Us" / "Contact Us" pages is a credibility red flag and often a hard requirement for SaaS marketplaces (Stripe, Apple, Google).

**What the script checks.** Walks `apps/frontend-ui/`. For each of `security`, `about`, `contact`:
1. Searches for a file at `/security.tsx`, `/security_us.tsx`, `/security-us/...` (and equivalent for `.jsx`, `.ts`, `.js`, `.vue`, `.svelte`, `.html`, `.md`).
2. Falls back to scanning `href` / `to` / `path` attributes pointing at `/security`, `/security-us`, etc.
3. Neither found → **FAIL.** Route reference only (no file yet) → **PASS** with placeholder note.

**How to pass.** Add a stub page or a routed link. Even a placeholder "coming soon" counts; the gate enforces the existence, not the content.

---

### Rule 04 — Access Control (IDOR / Privilege Escalation)

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A01 — Broken Access Control
- **Script:** `scripts/04-access-control.sh`

**Threat.** IDOR (Insecure Direct Object Reference) is one of the highest-impact bugs in modern web apps. `/api/orders/123` returning *anyone's* order because the handler reads `:id` without checking who owns it. A01 is the **#1** OWASP risk for a reason.

**What the script checks.**
1. For every TS / JS / Python source file, looks for handlers reading `params.id`, `params["id"]`, or `request.params`. If found, requires at least one of the following ownership/auth markers in the same file: `userId`, `ownerId`, `currentUser`, `req.user`, `getUser`, `@UseGuards`, `@Auth`, `requireAuth`, `is_owner`, `owner_id`, `tenant_id`. **Missing all of them → FAIL.**
2. Looks for client-side role gates (`role === 'admin'`, `isAdmin === true`) inside `apps/frontend-ui/` — **WARN.** (Server must re-enforce; client checks are UX only.)

**How to pass.**
- Always join the resource lookup on `ownerId = currentUser.id` (or use a Nest guard / FastAPI `Depends(get_owner)`).
- Never trust client-asserted role. If your route is admin-only, decorate it server-side with `@UseGuards(AdminGuard)` or equivalent.

**Example fix:**

```ts
// ❌ FAIL — IDOR
@Get(':id')
async getOrder(@Param('id') id: string) {
  return this.orders.findOne({ where: { id } });
}

// ✅ PASS — ownership check
@Get(':id')
@UseGuards(AuthGuard)
async getOrder(@Param('id') id: string, @CurrentUser() user: User) {
  return this.orders.findOne({ where: { id, ownerId: user.id } });
}
```

---

### Rule 05 — Network Security (DB private)

- **Tags:** A · **Severity:** High · **OWASP:** A05 — Security Misconfiguration
- **Script:** `scripts/05-network-security.sh`

**Threat.** A database with `publicly_accessible = true` is one Shodan search away from a credential-stuffing attack. Even with strong passwords, the surface should not exist.

**What the script checks.**
1. **Terraform / CloudFormation** in `infra/`, `terraform/`, `cloudformation/`: any file containing `publicly_accessible = true` or `PubliclyAccessible: true` → **FAIL.**
2. **docker-compose** at repo root: DB port mappings (`5432`, `3306`, `27017`, `6379`) bound to host → **WARN** (often acceptable in dev, dangerous in shared compose).
3. **`.env*` files**: DB URLs pointing at non-private hosts (`*.amazonaws.com`, `*.com`, `*.net`, `*.io`) → **WARN** (skips `.example` / `.template`).

**How to pass.**
- `publicly_accessible = false` on every `aws_db_instance` / `aws_rds_cluster`.
- Place DBs in a private subnet; connect via a bastion or a VPC peering.
- For dev compose, bind to `127.0.0.1` rather than `0.0.0.0`.

---

### Rule 06 — Authentication (no exposed endpoints)

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A01
- **Script:** `scripts/06-authentication.sh`

**Threat.** A single route handler that forgot its auth guard ships your entire data set. This rule is the gate against shipping accidental public endpoints — including webhook / event listener paths that authenticate by signature.

**What the script checks.** Three sweeps:

1. **NestJS** — `@Public()` decorators not preceded by a comment → **WARN** (confirm the public exposure is intentional).
2. **Express / generic** — files under `routes/`, `controllers/`, `api/`, `handlers/` that define `router.get/post/...` but lack any of these auth markers: `authMiddleware`, `requireAuth`, `passport.authenticate`, `verifyToken`, `@UseGuards`, `isAuthenticated`, `jwtAuth` → **FAIL.**
3. **FastAPI** — files under `routes/`, `api/`, `endpoints/` defining `@app.get/post/...` without `Depends(auth*)` (matched as `Depends(<any_word_containing>auth|user|token|jwt)`) → **FAIL.**
4. **Webhook / listener paths** (`/webhook`, `/webhooks`, `/listener`, `/callback`) that lack signature verification (`verifySignature`, `verify_signature`, `stripe.webhooks.constructEvent`, `hmac`, `HMAC`, `x-signature`, `svix`) → **FAIL.**

**How to pass.**
- Apply your auth middleware globally (`app.use(authMiddleware)`) and explicitly carve out the small set of intentionally-public routes.
- For webhooks, verify the provider's signature header on every call. Reject unsigned payloads.

**Example fix:**

```ts
// ❌ FAIL — no guard
@Controller('reports')
export class ReportsController {
  @Get() async list() { /* ... */ }
}

// ✅ PASS — guard at controller scope
@Controller('reports')
@UseGuards(AuthGuard)
export class ReportsController {
  @Get() async list(@CurrentUser() user: User) { /* ... */ }
}
```

```py
# ❌ FAIL — FastAPI route without Depends(auth)
@router.get("/reports")
async def list_reports():
    return await fetch_reports()

# ✅ PASS
@router.get("/reports")
async def list_reports(user: User = Depends(get_current_user)):
    return await fetch_reports(user.id)
```

---

### Rule 07 — Cloud Storage (S3 presigned TTL ≤ 5 min)

- **Tags:** A/S · **Severity:** High · **OWASP:** A05
- **Script:** `scripts/07-cloud-storage.sh`

**Threat.** Long-lived presigned URLs are the leading cause of "I shared a download link a year ago and now anyone can grab the file." A 5-minute TTL means a leaked URL is dead before it can be scraped.

**What the script checks.**
1. For each TS/JS/Python file referencing `getSignedUrl`, `generate_presigned_url`, `createPresignedPost`, or `@aws-sdk/s3-request-presigner`, looks for `Expires` / `expiresIn` / `ExpiresIn` / `expires_in` numeric values. **Any > 300 → FAIL.**
2. Hardcoded `https://*.s3*.amazonaws.com/` URLs without a presign call nearby → **WARN** (likely bypassing presign).

**How to pass.**
- `getSignedUrl(s3, command, { expiresIn: 300 })` — never more than 300 seconds.
- For multi-part uploads, regenerate URLs per part rather than extending TTL.
- For public-read assets, use Cloudflare-fronted CDN URLs, not raw S3.

---

### Rule 08 — IP Obfuscation

- **Tags:** S · **Severity:** High · **OWASP:** A05
- **Script:** `scripts/08-ip-obfuscation.sh`

**Threat.** Exposing your origin IP defeats the purpose of Cloudflare/CDN proxying — an attacker can DDoS the origin directly. Exposing internal IPs in error messages helps lateral movement.

**What the script checks.**
1. Scans every TS/JS/Python/HTML/JSON/MD file (excluding `node_modules`, `dist`, `build`, `.git`) for public IPv4 literals — explicitly **skipping** RFC1918 (`10.`, `172.16-31.`, `192.168.`), loopback (`127.`), link-local (`169.254.`), multicast (`224.`, `239.`), broadcast (`255.255.`), and TEST-NET (`192.0.2.`, `198.51.100.`, `203.0.113.`).
2. Hits in client-visible files (`apps/frontend-ui/`, `public/`, `static/`, `*.md`) → **FAIL.**
3. Hits in server-side files → **WARN** (confirm they're not echoed to clients).
4. References to identifying headers (`X-Powered-By`, `Server:`, `X-Backend-Server`) → **WARN** (strip in production).

**How to pass.**
- Move all hardcoded IPs to environment variables or config maps.
- Use Cloudflare for all public traffic; expose only the proxy.
- Strip `X-Powered-By` (`app.disable('x-powered-by')` in Express; `Server.Headers.Remove("Server")` in NGINX).

---

### Rule 09 — MFA (client + admin)

- **Tags:** S/C · **Severity:** High · **OWASP:** A07 — Identification & Authentication Failures
- **Script:** `scripts/09-identity-mfa.sh`

**Threat.** Credential stuffing makes single-factor auth a losing game. MFA is the single highest-leverage control for account takeover prevention. Admin accounts without MFA are an existential risk.

**What the script checks.**
1. Counts references to MFA / TOTP / WebAuthn integrations: `otplib`, `speakeasy`, `pyotp`, `@simplewebauthn`, `webauthn`, `2fa`, `two-factor`, `mfa`, `totp`, `cognito.*MFA`, `auth0.*mfa`. **Zero → FAIL.**
2. Files matching `admin.*login` / `loginAdmin` / `adminLogin` that don't reference MFA primitives in the same file → **FAIL.**

**How to pass.**
- Enforce MFA on every admin login path. No exceptions.
- For client accounts, offer MFA at minimum; enforce on sensitive actions (password change, billing, role escalation).
- Prefer WebAuthn over SMS where possible.

---

### Rule 10 — Localization (Weglot)

- **Tags:** C · **Severity:** Low · **OWASP:** — (compliance/UX)
- **Script:** `scripts/10-localization-weglot.sh`

**Threat.** Parallel i18n pipelines drift, mistranslate, and create compliance gaps when serving regulated markets. Weglot is the single source of truth.

**What the script checks.**
1. References to Weglot inside `apps/frontend-ui/` — **zero → FAIL.**
2. Competing i18n libraries (`i18next`, `react-intl`, `formatjs`, `@lingui`) → **WARN.**

**How to pass.** Wire the Weglot SDK / script tag in the frontend entry. If you need a competing library for runtime formatting, document why in the PR.

---

### Rule 11 — Timing-Attack Mitigation in Auth

- **Tags:** S · **Severity:** High · **OWASP:** A07
- **Script:** `scripts/11-timing-attack.sh`

**Threat.** Non-constant-time comparison of secrets leaks them bit-by-bit. An attacker measures response time to guess the first byte of a token, then the second, until they reconstruct it. This is not theoretical — it has been exploited against real production systems.

**What the script checks.** For files matching `*auth*`, `*login*`, `*session*`, `*token*`, `*password*`:
1. Looks for plain `==` / `===` comparisons on identifiers named `password`, `token`, `hash`, `secret`, `api_key` / `api-key`.
2. If found and there's no `timingSafeEqual`, `hmac.compare_digest`, `constant_time`, `safe_compare`, `secureCompare`, or `crypto_subtle` reference in the same file → **FAIL.**

**How to pass.**
- Node: `crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))`.
- Python: `hmac.compare_digest(a, b)`.
- Never `if (token === expected)` for any secret.

---

### Rule 12 — Legend Reference

- **Tags:** — · **Severity:** Low · **OWASP:** —
- **Script:** `scripts/12-legend.sh`

**Threat.** None. This rule is documentation-only — it prints the tag legend (S/R/O/A/C) so engineers reading raw output understand what the tags mean.

**What the script does.** Prints two `info` lines and a `pass`. No scanning.

**How to pass.** Always passes.

---

### Rule 13 — Rate Limiting (global + per-user)

- **Tags:** S/R · **Severity:** High · **OWASP:** A04 — Insecure Design
- **Script:** `scripts/13-rate-limit.sh`

**Threat.** No rate limiting → credential stuffing, scraping, payload-amplification DoS. Per-user rate limiting also blocks abuse from a single logged-in account. IP-only rate limiting is bypassed by any attacker with a botnet or NAT.

**What the script checks.**
1. References to `express-rate-limit`, `rate-limiter-flexible`, `@nestjs/throttler`, `slowapi`, `fastapi-limiter`, `rateLimit(`, `Throttle(`. **Zero → FAIL.**
2. If rate-limit middleware is present but no `keyGenerator` / `key_func` / `keyPrefix` references `req.user`, `userId`, `api_key`, or `sub` → **WARN** (global-only limits are insufficient).

**How to pass.**
- Add `express-rate-limit` (or your stack's equivalent) globally.
- For authenticated routes, configure `keyGenerator: (req) => req.user.id` so each user gets their own bucket.
- Lower the limit on sensitive paths (login, password reset, OTP issuance).

---

### Rule 14 — Injection Defenses (XSS / CSRF / SQLi)

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A03 — Injection
- **Script:** `scripts/14-injection.sh`

**Threat.** SQL injection, XSS, and CSRF together account for a large share of real-world web compromises. This rule is the broad-net defense.

**What the script checks.**
1. **Raw SQL concatenation** — `(SELECT|INSERT|UPDATE|DELETE).*['"]\s*+\s*[varname]` → **FAIL.**
2. **Python f-string SQL** — `execute(f"...")` → **FAIL.**
3. **DOM XSS sinks** — `dangerouslySetInnerHTML`, `.innerHTML =`, `v-html=` without `DOMPurify` / `sanitize` / `bleach` / `escapeHtml` in the same file → **FAIL.**
4. **CSRF** — counts references to `csurf`, `csrf`, `@nestjs/csrf`, `fastapi_csrf_protect`, or `SameSite=Strict`. Zero → **WARN.**

**How to pass.**
- Always use parameterized queries / ORM bindings: `db.query('SELECT * FROM users WHERE id = $1', [id])`, never string concat.
- Sanitize HTML before injecting: `DOMPurify.sanitize(html)`.
- CSRF: use `SameSite=Strict` cookies *and* CSRF tokens on state-changing endpoints.

**Example fix:**

```ts
// ❌ FAIL — SQL injection
const rows = await db.query(`SELECT * FROM users WHERE email = '${email}'`);

// ✅ PASS
const rows = await db.query('SELECT * FROM users WHERE email = $1', [email]);
```

```tsx
// ❌ FAIL — DOM XSS sink
<div dangerouslySetInnerHTML={{ __html: comment.body }} />

// ✅ PASS
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(comment.body) }} />
```

---

### Rule 15 — Webhook Signature Verification

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A08 — Software & Data Integrity Failures
- **Script:** `scripts/15-webhook-validation.sh`

**Threat.** An unverified webhook is an unauthenticated endpoint with side effects. An attacker who learns the URL can mint fake events: forged Stripe payments, fake auth callbacks, spoofed event triggers.

**What the script checks.** For every file containing `/webhook`, `/webhooks`, `/hook`, `/callback`: requires at least one of `verifySignature`, `verify_signature`, `constructEvent`, `svix`, `x-hub-signature`, `x-signature`, `hmac`, `HMAC`, `crypto.createHmac`, `hmac.compare_digest`. Missing → **FAIL.**

**How to pass.**
- Stripe: `stripe.webhooks.constructEvent(rawBody, sig, webhookSecret)`.
- GitHub: verify `X-Hub-Signature-256` with HMAC-SHA256 of the raw body.
- Custom: HMAC the body with a shared secret, compare with `timingSafeEqual` / `hmac.compare_digest`.

**Example fix:**

```ts
// ❌ FAIL — unverified webhook
app.post('/webhooks/stripe', (req, res) => {
  handleEvent(req.body);
  res.sendStatus(200);
});

// ✅ PASS — Stripe-verified
app.post('/webhooks/stripe', express.raw({ type: 'application/json' }), (req, res) => {
  const sig = req.headers['stripe-signature'] as string;
  let event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET!);
  } catch {
    return res.status(400).send('invalid signature');
  }
  handleEvent(event);
  res.sendStatus(200);
});
```

---

### Rule 16 — Cloudflare Proxy Mandate

- **Tags:** S/A · **Severity:** High · **OWASP:** A05
- **Script:** `scripts/16-edge-cloudflare.sh`

**Threat.** Without Cloudflare in front, you have no DDoS protection, no edge WAF, no bot management, and your origin IP is in DNS. This rule enforces the "every public route is proxied" policy.

**What the script checks.**
1. References to `cloudflare`, `CF-Connecting-IP`, `cf-ray`, `cloudflare/wrangler`, `@cloudflare/`, `cloudflare_record`, `proxied = true` in `infra/`, `terraform/`, `.github/`, `apps/`. **Zero → FAIL.**
2. Terraform records with `proxied = false` → **WARN** (verify the route is internal-only).

**How to pass.**
- All public DNS records: `proxied = true` (the orange cloud).
- Internal-only routes: explicit `proxied = false` with a comment explaining.

---

### Rule 17 — CI/CD Security Scanning

- **Tags:** R/O · **Severity:** High · **OWASP:** A08
- **Script:** `scripts/17-cicd-security.sh`

**Threat.** A vulnerability that lands at midnight without scanning will sit in production for weeks. CI scanning is the safety net for "we forgot to run the gate."

**What the script checks.**
1. If `.github/workflows/` does not exist → **FAIL.**
2. Counts references in workflow YAMLs to: `trivy`, `snyk`, `gitleaks`, `trufflehog`, `semgrep`, `codeql`, `dependabot`, `grype`, `bandit`, `safety`, `npm audit`, `pnpm audit`, `pip-audit`. **Zero → FAIL.**

**How to pass.** Add at least one security step per workflow — `trivy` for containers, `gitleaks` for secrets, `codeql` or `semgrep` for SAST, `pnpm audit` / `pip-audit` for dependencies.

---

### Rule 18 — Testing Rigor (unit / integration / system)

- **Tags:** R · **Severity:** Medium · **OWASP:** A04
- **Script:** `scripts/18-testing-rigor.sh`

**Threat.** Untested code is unverified code. The gate enforces all three test layers exist; security flaws often hide between layers (a unit test passes; the integration breaks; the system fails).

**What the script checks.** For each layer (`unit`, `integration`, `system`):
1. Looks for a `__tests__` / `tests` / `test` / `spec` directory containing that layer name.
2. Or files matching `*<layer>*.test.*`, `*<layer>*.spec.*`, `test_<layer>*.py`.
3. None found → **FAIL** for that layer.
4. Also checks for `jest.config.*`, `vitest.config.*`, `pytest.ini`, `pyproject.toml` — none found → **WARN.**

**How to pass.** Maintain a `tests/unit`, `tests/integration`, `tests/system` (or equivalent) structure per workspace.

---

### Rule 19 — Staging Office-Network Only

- **Tags:** A · **Severity:** Low · **OWASP:** A01
- **Script:** `scripts/19-staging-isolation.sh`

**Threat.** Public staging environments are routinely indexed by Google, scraped by bots, and used as an attack surface to find issues that haven't been patched in prod yet.

**What the script checks.** Walks `infra/`, `terraform/`, `.github/`, `apps/`:
1. If "staging" / "stage" is referenced anywhere → `found_staging=1`.
2. If `office_ip`, `office_cidr`, `allowlist`, `allow_list`, `ip_whitelist`, `allowed_ips`, `cidr_blocks` are referenced → `allowlisted=1`.
3. Staging referenced but no allowlist found → **FAIL.**

**How to pass.** Configure the staging WAF / ALB / NGINX to allow only the office CIDR(s) and VPN IPs.

---

### Rule 20 — CORS Strictness

- **Tags:** S · **Severity:** High · **OWASP:** A05
- **Script:** `scripts/20-cors.sh`

**Threat.** `Access-Control-Allow-Origin: *` on a credentialed API turns every browser into an attack tool. CSRF protection is bypassed if any origin can read your responses.

**What the script checks.**
1. Wildcard origins: `Access-Control-Allow-Origin: '*'`, `origin: '*'`, `allow_origins=['*']` → **FAIL.**
2. `cors()` called with no options (defaults to `*`) → **WARN.**

**How to pass.** Explicit origin allowlist. `cors({ origin: ['https://app.softaims.com', 'https://admin.softaims.com'], credentials: true })`. Never `*` in production.

---

### Rule 21 — File Upload Defense

- **Tags:** S · **Severity:** High · **OWASP:** A03
- **Script:** `scripts/21-file-upload.sh`

**Threat.** Uploads that don't validate MIME type let attackers upload web shells, malware, or polyglot files that escalate to RCE. EXIF metadata also leaks PII (GPS coordinates of customers' homes, anyone?).

**What the script checks.** For files using upload libs (`multer`, `formidable`, `busboy`, NestJS `FileInterceptor`, FastAPI `UploadFile`, werkzeug `FileStorage`):
- Requires at least one of `fileFilter`, `mimetype`, `content_type`, `file-type`, `magic-bytes`, `sharp(`, `exiftool`, `exifremove`, `sanitize`, `allowedTypes`, `ALLOWED_MIME`. Missing → **FAIL.**

**How to pass.**
- Validate MIME by magic bytes (not the client-supplied Content-Type).
- Whitelist an explicit set of allowed types.
- Strip EXIF before storing or serving images (`sharp(...).withMetadata({})` or `exiftool -all=`).

---

### Rule 22 — Proactive OWASP Audit

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A02 (broad)
- **Script:** `scripts/22-owasp-proactive.sh`

**Threat.** A grab-bag of common OWASP omissions Claude routinely sees.

**What the script checks.**
1. **Weak hash on credentials** — `md5(password)`, `sha1(secret)`, `sha256(token)` etc. → **FAIL.**
2. **`eval` / `exec`** — any usage outside `node_modules` → **FAIL.**
3. **TLS verify disabled** — `NODE_TLS_REJECT_UNAUTHORIZED=0`, `rejectUnauthorized: false`, `verify=False`, `ssl_verify=False` → **FAIL.**
4. **Hardcoded JWT secret** — `jwt.sign(..., 'literal-string')` not pulled from env → **FAIL.**
5. **Tracked `.env` / `.env.local` / `.env.production`** files with assignments → **WARN.**
6. **Security headers absent** — no `helmet`, `secure-headers`, or `Content-Security-Policy` reference anywhere → **WARN.**

**How to pass.** Fix each finding individually. This rule is broad on purpose; treat it as a tripwire for hygiene drift.

**Example fixes:**

```ts
// ❌ FAIL — weak hash on credential
const hash = crypto.createHash('sha256').update(password).digest('hex');

// ✅ PASS
const hash = await bcrypt.hash(password, 12);
```

```ts
// ❌ FAIL — disabled TLS verification
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const r = await axios.get(url, { httpsAgent: new https.Agent({ rejectUnauthorized: false }) });

// ✅ PASS — verify everything
const r = await axios.get(url);
```

```ts
// ❌ FAIL — hardcoded JWT secret
const token = jwt.sign(payload, 'supersecret123');

// ✅ PASS
const token = jwt.sign(payload, process.env.JWT_SECRET!, { algorithm: 'HS256' });
```

---

### Rule 23 — Hardcoded Secrets in Working Tree

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A08
- **Script:** `scripts/23-secret-scan-tree.sh`

**Threat.** A secret in git history is a permanent leak. Rotating the key is the easy part; auditing every consumer of that key is the hard part. This rule is the line of defense before secrets land in git.

**What the script checks.** High-confidence regex patterns across `apps/`, `infra/`, `terraform/`, `.github/`:

| Pattern | Matches |
|---|---|
| `AKIA[0-9A-Z]{16}` | AWS access key ID |
| `aws_secret_access_key = [40-char base64]` | AWS secret |
| `gh[pousr]_[A-Za-z0-9_]{36,}` | GitHub token (classic) |
| `github_pat_[A-Za-z0-9_]{82}` | GitHub fine-grained PAT |
| `xox[abprs]-...` | Slack token |
| `sk_live_[A-Za-z0-9]{24,}` | Stripe live key |
| `sk-ant-[A-Za-z0-9-_]{40,}` | Anthropic key |
| `-----BEGIN ... PRIVATE KEY-----` | RSA/DSA/EC/OPENSSH/PGP private key |
| `eyJ...eyJ....` | JWT literal |
| `(postgres|mysql|mongodb)://user:pass@host` | DB URL with creds |

Skips `node_modules`, `dist`, `build`, `.lock`, `.example`, `.template`, `.test.`, `fixtures/`.

Also: assignments to `secret` / `token` / `password` / `api_key` variables with literal values ≥ 24 chars (skipping `process.env`, `os.environ`, `config.get`, `${`, `EXAMPLE`, `PLACEHOLDER`, `xxx`, `<your`).

**Any hit → FAIL.**

**How to pass.**
- Move every secret to env vars or a secret manager (AWS Secrets Manager, 1Password, Vault).
- For tests, use mocks or `.env.example` placeholders.
- If a secret is already committed: **rotate immediately**, then scrub history with `git filter-repo`.

**Example fix:**

```ts
// ❌ FAIL — secret in source
const stripe = new Stripe('sk_live_<REDACTED_EXAMPLE_KEY>');

// ✅ PASS — from env
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
```

```
# .env.example  (committed, no real values)
STRIPE_SECRET_KEY=sk_live_<REDACTED_EXAMPLE_KEY>
JWT_SECRET=replace-with-random-32-byte-string

# .env  (gitignored, real values)
STRIPE_SECRET_KEY=sk_live_actual_value_here
JWT_SECRET=actual_value_here
```

---

### Rule 24 — Dependency Vulnerabilities

- **Tags:** S/R · **Severity:** High · **OWASP:** A06 — Vulnerable & Outdated Components
- **Script:** `scripts/24-dep-vulnerabilities.sh`

**Threat.** A single CVE in a transitive dep can compromise the entire app. Log4Shell, Equifax — these are not edge cases.

**What the script checks.**
1. For every `package.json` (not in `node_modules`): runs `pnpm audit --prod --json` if `pnpm-lock.yaml` exists, else `npm audit --omit=dev --json`. Sums the count of `"high"` + `"critical"` advisories. **Any → FAIL** for that package.
2. For every `requirements.txt` / `requirements-prod.txt`: runs `pip-audit -r <file> --strict` if available, else **WARN** (pip-audit not installed).

**How to pass.**
- Resolve each high/critical advisory: bump the dep, accept the breaking change, or apply a workaround.
- Configure Dependabot or Renovate for auto-PRs.
- Pin via lockfiles; never `^` your way into surprises.

---

### Rule 25 — Container Hardening

- **Tags:** S/A · **Severity:** High · **OWASP:** A05
- **Script:** `scripts/25-container-hardening.sh`

**Threat.** A container running as root with `privileged: true` has the host's full attack surface. `:latest` tags break reproducibility and let upstream surprises ship with your release.

**What the script checks.**

**Dockerfiles:**
1. No `USER` directive → **FAIL** (runs as root).
2. Explicit `USER root` → **FAIL.**
3. `FROM image:latest` → **FAIL.**
4. `FROM image` with no tag → **WARN** (implicit `:latest`).
5. `ADD https://...` → **WARN** (prefer `COPY` + verified download).

**docker-compose:**
6. `privileged: true` → **FAIL.**
7. `network_mode: host` → **FAIL.**
8. `cap_add: SYS_ADMIN` → **FAIL.**

**How to pass.**
- Add `USER appuser` (and create that user earlier in the Dockerfile).
- Pin to a digest (`FROM node:20.11.1-bookworm@sha256:...`) or at minimum a specific version tag.
- Drop privileges. If your container truly needs a capability, name it explicitly and justify it.

---

### Rule 26 — TLS / HTTPS Enforcement

- **Tags:** S · **Severity:** High · **OWASP:** A02
- **Script:** `scripts/26-tls-https.sh`

**Threat.** Plaintext HTTP exposes everything to a MITM. Disabled cert verification turns HTTPS into theater. HSTS prevents downgrade attacks.

**What the script checks.**
1. References to `Strict-Transport-Security` or `hsts(`. **Zero → FAIL.**
2. `http://` URLs targeting public TLDs (`.com`, `.net`, `.io`, `.co`, `.org`, `.cloud`, `.app`, `.dev`) — excluding `localhost`, `127.0.0.1`, `example.com`, `test.com` — **FAIL.**
3. Disabled TLS verification (`NODE_TLS_REJECT_UNAUTHORIZED=0`, `rejectUnauthorized: false`, `verify=False`, `ssl_verify=False`) → **FAIL.**

**How to pass.**
- Always `https://`.
- Set `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload` via Helmet or NGINX.
- Never disable cert verification, even temporarily.

---

### Rule 27 — Password Hashing Strength

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A02
- **Script:** `scripts/27-password-hashing.sh`

**Threat.** `sha256(password)` is crackable by a GPU in seconds. `md5(password)` is crackable in milliseconds. Only memory-hard / adaptive functions (bcrypt, argon2, scrypt) provide actual protection.

**What the script checks.**
1. Counts references to `bcrypt`, `argon2`, `scrypt`, `passlib`, `werkzeug.security.generate_password_hash`. Zero → **WARN** (applies once auth lands).
2. Any of `md5`, `sha1`, `sha224`, `sha256`, `sha384`, `sha512` called on an identifier named `password` / `passwd` / `pwd` → **FAIL.**
3. `bcrypt.hash(..., N)` where N < 10 → **WARN** (use ≥ 12).

**How to pass.**
- Node: `bcrypt.hash(plaintext, 12)`.
- Python: `passlib.hash.argon2.hash(plaintext)` or `werkzeug.security.generate_password_hash(plaintext)`.
- Never roll your own hash chain.

**Example fix:**

```ts
// ❌ FAIL — sha256 on a password
import crypto from 'crypto';
const hash = crypto.createHash('sha256').update(password).digest('hex');

// ✅ PASS — bcrypt
import bcrypt from 'bcrypt';
const hash = await bcrypt.hash(password, 12);
// later, on login:
const ok = await bcrypt.compare(submitted, user.passwordHash);
```

```py
# ❌ FAIL
from hashlib import sha256
hashed = sha256(password.encode()).hexdigest()

# ✅ PASS
from passlib.hash import argon2
hashed = argon2.hash(password)
ok = argon2.verify(submitted, hashed)
```

---

### Rule 28 — Cookie / Session Security

- **Tags:** S · **Severity:** High · **OWASP:** A02
- **Script:** `scripts/28-cookie-session.sh`

**Threat.** Cookies without `HttpOnly` are stealable via XSS. Without `Secure`, they're stealable on plaintext networks. Without `SameSite`, they're CSRF-able.

**What the script checks.** For every file using `res.cookie(`, `setCookie(`, `cookie-session`, `express-session`, FastAPI `Cookie`, or `set_cookie(`:
1. No `httpOnly` / `HttpOnly` / `http_only` reference → **FAIL.**
2. No `secure: true` / `Secure:` / `secure=True` → **WARN** (dev tolerance).
3. No `sameSite` / `SameSite` / `same_site` → **FAIL.**

**How to pass.**
- `res.cookie('session', value, { httpOnly: true, secure: true, sameSite: 'strict', maxAge: 3600000 })`.
- Use a session library (`express-session`, `iron-session`) rather than rolling cookies.

---

### Rule 29 — Input Validation Framework

- **Tags:** S · **Severity:** Medium · **OWASP:** A07
- **Script:** `scripts/29-input-validation.sh`

**Threat.** Trusting request bodies is the universal source of injection bugs, mass assignment, and type confusion. A schema validation layer at every boundary is non-negotiable.

**What the script checks.**
1. Counts references to `zod`, `joi`, `yup`, `class-validator`, `pydantic`, `marshmallow`, FastAPI `Body(`, `ajv`, `@hapi/joi`. **Zero → FAIL.**
2. For handler files (`routes/`, `controllers/`, `handlers/`, `api/`, `endpoints/`) that read `req.body` / `request.json()` without a `parse(`, `safeParse(`, `validate(`, `schema.`, `BaseModel`, `@Body`, or `Body(` nearby → **WARN.**

**How to pass.**
- TS/JS: `const body = MySchema.parse(req.body)` (zod) before touching the data.
- Python: `class CreateUser(BaseModel): ...` and accept `body: CreateUser`.
- Never read `req.body.someField` without a schema in between.

---

### Rule 30 — SSRF Defenses

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A10 — Server-Side Request Forgery
- **Script:** `scripts/30-ssrf.sh`

**Threat.** SSRF lets an attacker pivot from your public app into your private network. Reaching `http://169.254.169.254/latest/meta-data/iam/security-credentials/` is the AWS credential exfiltration playbook.

**What the script checks.**
1. Outbound HTTP calls (`axios`, `fetch`, `requests.get`, `httpx.`, `urllib.request`, `got(`, `node-fetch`) where the URL is user-controlled (built from `req.`, `request.`, `body.`, `params.`, `query.`).
2. If no allowlist / private-IP filter is in the file (`allowlist`, `allow_list`, `whitelist`, `isPrivateIP`, `is_private`, `169.254.169.254`, `metadata.google`, RFC1918 CIDRs) → **FAIL.**
3. Hardcoded references to `169.254.169.254` or `metadata.google.internal` → **WARN** (verify intentional).

**How to pass.**
- Validate user URLs: parse, reject non-HTTPS, reject private/loopback/link-local IPs, optionally allowlist domains.
- Use a library like `ssrf-req-filter` (Node) or `pydantic.HttpUrl` + custom checks (Python).

**Example fix:**

```ts
// ❌ FAIL — fetch any URL the user supplies
const r = await fetch(req.body.url);

// ✅ PASS — validate before fetching
import { URL } from 'url';
import net from 'net';

function assertSafeUrl(raw: string) {
  const u = new URL(raw);
  if (u.protocol !== 'https:') throw new Error('https only');
  const ip = net.isIP(u.hostname) ? u.hostname : null;
  if (ip && isPrivateIp(ip)) throw new Error('private ip blocked');
  if (!ALLOWED_DOMAINS.includes(u.hostname)) throw new Error('domain not allowlisted');
}

assertSafeUrl(req.body.url);
const r = await fetch(req.body.url, { redirect: 'manual' });
```

---

### Rule 31 — Unsafe Deserialization

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A03
- **Script:** `scripts/31-deserialization.sh`

**Threat.** `pickle.loads(untrusted)` is **arbitrary code execution**. `yaml.load(untrusted)` without `SafeLoader` is the same. `eval(JSON.parse(...))` is parody-level dangerous.

**What the script checks.**
1. `pickle.loads(` / `pickle.load(` / `pickle.Unpickler(` → **FAIL.**
2. `yaml.load(` without `SafeLoader` / `safe_load` / `Loader=yaml.SafeLoader` → **FAIL.**
3. `eval(JSON.parse(...))` → **FAIL.**
4. `require('node-serialize')` or `unserialize(` → **FAIL.**

**How to pass.**
- `yaml.safe_load(data)` always.
- Never `pickle` user-supplied data; use `json` instead.
- If you need cross-language structured data, use protobuf / msgpack / json.

**Example fix:**

```py
# ❌ FAIL — RCE via pickle / yaml.load
import pickle, yaml
config = pickle.loads(request.data)
config = yaml.load(request.data)

# ✅ PASS
import json, yaml
config = json.loads(request.data)            # pickle → json
config = yaml.safe_load(request.data)        # yaml.load → safe_load
```

```ts
// ❌ FAIL
const obj = eval('(' + JSON.parse(raw) + ')');

// ✅ PASS
const obj = JSON.parse(raw);
```

---

### Rule 32 — Open Redirect

- **Tags:** S · **Severity:** High · **OWASP:** A01
- **Script:** `scripts/32-open-redirect.sh`

**Threat.** `?next=https://evil.com` chained from your domain bypasses phishing filters and lets attackers impersonate your auth flow.

**What the script checks.** `res.redirect(req.query.next)` / `response.redirect(...)` / `RedirectResponse(...)` patterns where the URL is user-controlled, **and** no validation marker (`allowlist`, `whitelist`, `startsWith('/'`, `isSafeUrl`, `validate_redirect`, `urlparse`) appears nearby → **FAIL.**

**How to pass.** Validate the redirect target: relative paths only, or explicit allowlist of fully-qualified hosts. Reject anything else.

---

### Rule 33 — Mass Assignment

- **Tags:** S · **Severity:** High · **OWASP:** A03
- **Script:** `scripts/33-mass-assignment.sh`

**Threat.** `User.create({ ...req.body })` lets an attacker set `role: 'admin'` or `isVerified: true` simply by including those fields in the request.

**What the script checks.**
1. ORM calls with spread: `.create({ ...req.body })`, `.update({ ...req.body })`, `.save({ ...request.* })`, `.insertOne({ ...req.* })`, `.updateOne(...)` → **FAIL.**
2. Python `Model(**request.json())` / `Model(**body)` / `Model(**payload)` → **FAIL.**

**How to pass.** Always pluck explicit fields: `User.create({ email: body.email, name: body.name })`. Or use a DTO / validator with `additionalProperties: false`.

---

### Rule 34 — Path Traversal

- **Tags:** S · **Severity:** High · **OWASP:** A03
- **Script:** `scripts/34-path-traversal.sh`

**Threat.** `fs.readFile('/uploads/' + req.params.name)` with `name = ../../../etc/passwd` is the classic. Path traversal hands attackers your secrets, source code, or shadow.

**What the script checks.** `fs.readFile`, `fs.createReadStream`, `fs.writeFile`, `fs.unlink`, `path.join`, `open(` called with `req.`, `request.`, `body.`, `params.`, `query.` interpolation, **without** `path.normalize`, `path.resolve(...).startsWith(...)`, `realpath`, `sanitize-filename`, or `basename(` in the file → **FAIL.**

**How to pass.**
- `const safe = path.basename(req.params.name)` to strip directory components.
- `path.resolve(uploadDir, safe).startsWith(uploadDir)` to confirm containment.
- Better: store files by UUID, look up by DB row, never trust user-supplied paths.

---

### Rule 35 — Command Injection

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A03
- **Script:** `scripts/35-command-injection.sh`

**Threat.** `exec('ffmpeg -i ' + req.body.file)` with `file = "; rm -rf /"` is RCE. This is one of the few rules where a single hit means an immediate emergency.

**What the script checks.**
1. Node `child_process.exec(...)`, `execSync(...)`, `spawnSync(...)` with template literal / concatenation containing `req`, `request`, `body`, `params`, `query` → **FAIL.**
2. Python `subprocess.run(..., shell=True)`, `.call(..., shell=True)`, `.Popen(..., shell=True)`, `.check_output(..., shell=True)` → **FAIL.**
3. `os.system(...)` / `os.popen(...)` → **WARN** (prefer `subprocess` with `shell=False`).

**How to pass.**
- Use `spawn(cmd, [arg1, arg2])` — array-form arguments are not shell-interpreted.
- Python: `subprocess.run([cmd, arg1, arg2], shell=False)`.
- If you must use a shell, escape rigorously (`shlex.quote`) — but prefer not to.

**Example fix:**

```ts
// ❌ FAIL — string-interpolated exec → RCE
import { exec } from 'child_process';
exec(`ffmpeg -i ${req.body.file} out.mp4`);

// ✅ PASS — array form, no shell
import { execFile } from 'child_process';
execFile('ffmpeg', ['-i', req.body.file, 'out.mp4']);
```

```py
# ❌ FAIL
import subprocess
subprocess.run(f"ffmpeg -i {user_file} out.mp4", shell=True)

# ✅ PASS
subprocess.run(["ffmpeg", "-i", user_file, "out.mp4"], shell=False)
```

---

### Rule 36 — Security Headers

- **Tags:** S · **Severity:** High · **OWASP:** A05
- **Script:** `scripts/36-security-headers.sh`

**Threat.** Without `Content-Security-Policy`, your XSS damage is unbounded. Without `X-Frame-Options`, you can be clickjacked. Without `X-Content-Type-Options: nosniff`, browsers can misinterpret content.

**What the script checks.** Five headers, each must be referenced somewhere:

| Header | Patterns scanned |
|---|---|
| Content-Security-Policy | `contentSecurityPolicy`, `Content-Security-Policy` |
| X-Frame-Options | `X-Frame-Options`, `frameguard` |
| X-Content-Type-Options | `X-Content-Type-Options`, `noSniff` |
| Referrer-Policy | `Referrer-Policy`, `referrerPolicy` |
| Permissions-Policy | `Permissions-Policy`, `permissionsPolicy`, `featurePolicy` |

Missing any → **FAIL** for that header. `helmet()` with no options → **WARN** (CSP defaults may be too loose).

**How to pass.** Use Helmet with explicit CSP:
```ts
app.use(helmet({
  contentSecurityPolicy: { directives: { defaultSrc: ["'self'"], ... } },
  referrerPolicy: { policy: 'no-referrer' },
  permissionsPolicy: { features: { geolocation: ["'none'"] } }
}));
```

---

### Rule 37 — Body Size Limit

- **Tags:** S/R · **Severity:** High · **OWASP:** A04
- **Script:** `scripts/37-body-size-limit.sh`

**Threat.** A 10 GB JSON body crashes your server (memory exhaustion DoS) or stalls every worker for minutes. The body limit is the first line of defense.

**What the script checks.**
1. References to `express.json({ limit })`, `bodyParser.*limit`, `client_max_body_size` (nginx), `MAX_CONTENT_LENGTH`, `MAX_UPLOAD_SIZE`, `fastify.*bodyLimit`, `multer.*limits`. **Zero → FAIL.**
2. Limit > 50 MB (`limit: '50mb'` and up) → **WARN** (uploads belong on S3, not in the API body).

**How to pass.**
- `express.json({ limit: '1mb' })` for JSON APIs.
- `client_max_body_size 1m;` in NGINX.
- For uploads, use S3 presigned URLs (Rule 07) — the API never holds the bytes.

---

### Rule 38 — JWT Hardening

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A07
- **Script:** `scripts/38-jwt-hardening.sh`

**Threat.** `alg=none` accepted on JWT verify is full auth bypass. Hardcoded secrets are credential leaks. Long-lived tokens turn theft into multi-month compromise.

**What the script checks.** For files referencing `jsonwebtoken`, `jwt.sign|verify|decode`, `PyJWT`, `jose.jwt`:
1. `algorithm = 'none'` or `algorithms = ['none']` → **FAIL.**
2. `jwt.verify(...)` with no `algorithms` / `algorithm` list → **WARN** (alg-confusion risk).
3. `expiresIn` / `exp` > 30 days → **WARN.**
4. `jwt.sign(payload, 'literal-string')` with a hardcoded secret → **FAIL.**

**How to pass.**
- Always explicit: `jwt.verify(token, secret, { algorithms: ['HS256'] })`.
- Access-token TTL ≤ 15 min; refresh-token rotation.
- Secret from env, never literal.

**Example fix:**

```ts
// ❌ FAIL — alg unspecified, long TTL, literal secret
const token = jwt.sign(payload, 'devsecret', { expiresIn: '90d' });
const decoded = jwt.verify(token, 'devsecret');

// ✅ PASS
const token = jwt.sign(payload, process.env.JWT_SECRET!, {
  algorithm: 'HS256',
  expiresIn: '15m',
});
const decoded = jwt.verify(token, process.env.JWT_SECRET!, {
  algorithms: ['HS256'],
});
```

---

### Rule 39 — PII Redaction in Logs

- **Tags:** S/C · **Severity:** Medium · **OWASP:** A09
- **Script:** `scripts/39-pii-in-logs.sh`

**Threat.** PII in logs = PII in CloudWatch = PII in your support engineer's terminal scrollback. Regulators (GDPR, CCPA, HIPAA) treat this as a breach.

**What the script checks.**
1. Log calls (`console.log/info/warn/error/debug`, `logger.*`, `logging.*`) that include identifier names `password`, `passwd`, `ssn`, `social_security`, `credit_card`, `card_number`, `cvv`, `email` → **FAIL.**
2. `console.log(JSON.stringify(user))` / `JSON.stringify(account)` / `JSON.stringify(customer)` → **WARN.**
3. No logger-redaction config (`redact:`, `redact_paths`, `format.redact`, `scrub_pii`, `sanitize`) anywhere → **WARN.**

**How to pass.**
- Configure `pino({ redact: ['password', 'email', 'creditCard'] })` (or winston/structlog equivalent).
- Never `JSON.stringify(user)` — pick the safe fields explicitly.

---

### Rule 40 — Encryption at Rest

- **Tags:** S/A · **Severity:** High · **OWASP:** A02
- **Script:** `scripts/40-encryption-at-rest.sh`

**Threat.** An unencrypted RDS snapshot leaked from a backup is full database exfiltration. Encryption at rest is table stakes; the gate enforces it in IaC.

**What the script checks.** For each Terraform / CloudFormation file in `infra/`, `terraform/`, `cloudformation/`:
1. `aws_db_instance` / `aws_rds_cluster` without `storage_encrypted = true` → **FAIL.**
2. `aws_s3_bucket` without SSE configuration (`server_side_encryption_configuration` or the dedicated resource) → **FAIL.**
3. `aws_ebs_volume` without `encrypted = true` → **FAIL.**

**How to pass.** Explicit encryption on every storage resource:
```hcl
resource "aws_db_instance" "primary" {
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
}
```

---

### Rule 41 — Generic Error Responses

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A04
- **Script:** `scripts/41-generic-errors.sh`

**Threat.** "Email not registered" tells an attacker which addresses are valid (account enumeration). Stack traces leak file paths and library versions. `password too short` confirms a partial credential.

**What the script checks.**
1. Express/Fastify: `res.send(err.message)`, `res.json(err.stack)`, `res.json({ message: err.message })`, `res.send(err.toString())`, `JSON.stringify(error)` in a response → **FAIL.**
2. FastAPI: `HTTPException(detail=str(e))` or `detail=repr(e)` → **FAIL.**
3. Flask/Django: `traceback.format_exc()` returned in a response → **FAIL.** Used elsewhere (logger ok) → **WARN.**
4. Express error middleware (`app.use((err, req, res, next) => ...)`) that echoes `err.message` / `err.stack` → **FAIL.**
5. Hardcoded enumeration-leak strings: `"Password too short"`, `"Password is incorrect"`, `"User not found"`, `"No such user"`, `"Email not registered"`, `"s3_key missing"`, `"Invalid s3 key"` → **FAIL.**
6. NestJS: `throw new BadRequestException(err.message)` / `InternalServerErrorException(err.message)` → **FAIL.**
7. `DEBUG=True`, `debug: true`, `app.debug = True`, `NODE_ENV=development` referenced → **WARN.**

**How to pass.**
- Auth errors are uniform: `"Invalid credentials"`. Always.
- Use a global error handler that returns `{ error: 'InternalServerError', requestId: '...' }`. Log the real error.
- Disable debug pages in production builds.

**Example fix:**

```ts
// ❌ FAIL — enumeration + stack leak
app.post('/login', async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  if (!user) return res.status(404).json({ error: 'User not found' });
  if (!await bcrypt.compare(req.body.password, user.passwordHash))
    return res.status(401).json({ error: 'Password is incorrect' });
  // ...
});

app.use((err, req, res, next) => {
  res.status(500).json({ message: err.message, stack: err.stack });
});

// ✅ PASS — uniform error, generic 500
app.post('/login', async (req, res) => {
  const user = await User.findOne({ email: req.body.email });
  const valid = user && await bcrypt.compare(req.body.password, user.passwordHash);
  if (!valid) return res.status(401).json({ error: 'Invalid credentials' });
  // ...
});

app.use((err, req, res, next) => {
  logger.error({ err, requestId: req.id });
  res.status(500).json({ error: 'InternalServerError', requestId: req.id });
});
```

---

### Rule 42 — Response-Time Normalization (auth)

- **Tags:** S · **Severity:** **Critical** · **OWASP:** A04
- **Script:** `scripts/42-timing-normalization.sh`

**Threat.** "User not found" returns in 5 ms. "Wrong password" takes 200 ms (because bcrypt). An attacker measures and enumerates accounts trivially. This is account enumeration via timing oracle.

**What the script checks.** For every auth-ish file (`*auth*`, `*login*`, `*signin*`, `*session*`, `*password*`) that emits a response (`res.json/send/status`, `jsonify`, `HttpResponse`, `JsonResponse`, `HTTPException`, `UnauthorizedException`):
1. Requires at least one of: `setTimeout(...resolve)`, `await sleep(`, `await asyncio.sleep(`, `time.sleep(`, `delay(`, `randomDelay`, `constantTime`, `timingSafeEqual`, `hmac.compare_digest`. **Missing → FAIL.**
2. If the code does `User.findOne(...) → if (!user) return/throw` without a dummy hash compare → **WARN** (the no-user branch is faster than the wrong-password branch).

**How to pass.**
```ts
const user = await User.findOne({ email });
const fakeHash = '$2b$12$........................';  // pre-generated
const validPassword = await bcrypt.compare(password, user?.passwordHash ?? fakeHash);
if (!user || !validPassword) {
  await randomDelay(50, 150);
  throw new UnauthorizedException('Invalid credentials');
}
```

---

## Appendix A — Tag Legend

| Tag | Meaning |
|---|---|
| **S** | Security — defends against an attacker |
| **R** | Reliability — keeps the system from breaking under load or failure |
| **O** | Operability — makes the system observable and recoverable |
| **A** | Architecture — enforces a structural decision |
| **C** | Compliance / UX — regulatory or trust requirement |

A rule may carry multiple tags (e.g. Rule 13 is `S/R` — both security and reliability).

---

## Appendix B — OWASP Top 10 (2021) Coverage Matrix

| OWASP Category | Description | Rules in this gate |
|---|---|---|
| **A01** | Broken Access Control | 04, 06, 19, 32 |
| **A02** | Cryptographic Failures | 22, 26, 27, 28, 40 |
| **A03** | Injection | 14, 21, 31, 33, 34, 35 |
| **A04** | Insecure Design | 13, 18, 37, 41, 42 |
| **A05** | Security Misconfiguration | 05, 07, 08, 16, 20, 25, 36 |
| **A06** | Vulnerable & Outdated Components | 24 |
| **A07** | Identification & Authentication Failures | 09, 11, 29, 38 |
| **A08** | Software & Data Integrity Failures | 15, 17, 23 |
| **A09** | Security Logging & Monitoring Failures | 01, 02, 39 |
| **A10** | Server-Side Request Forgery (SSRF) | 30 |

---

## Appendix C — Limitations & What This Gate Does *Not* Cover

This gate is honest about its scope. It is **not**:

- **A dynamic scanner.** It does not execute your code, fuzz inputs, or send requests.
- **A business-logic auditor.** Race conditions on shared state, multi-step abuse, and complex authorization flows require human review.
- **A perfect static analyzer.** It uses `grep` heuristics. False positives and false negatives are both possible.
- **A substitute for external pen-testing.** Commission an external pen-test annually and after major architectural changes.
- **A dependency scanner with full graph traversal.** Rule 24 uses `pnpm/npm audit` and `pip-audit` — broad, but not a replacement for Snyk / GitHub Advanced Security / Dependabot at CI level.
- **A runtime defense.** It does not provide a WAF, RASP, or anomaly detection. Cloudflare + WAF rules + Sentry / Datadog cover the runtime layer.

**Pair this gate with:**

1. Dependency scanning in CI (Dependabot, Snyk, or trivy on every PR).
2. SAST in CI (`semgrep`, `codeql`).
3. Secret scanning in CI (`gitleaks`, `trufflehog`).
4. DAST in staging (`zap`, `burp` automation).
5. Quarterly external review.
6. An incident-response playbook — "what happens when a finding becomes a real breach?"

---

_Generated for the `claude-code-boilerplate` security gate. Source rules live under `.claude/skills/security-audit/scripts/`. For workflow and command help, see [`docs/security/README.md`](README.md)._
