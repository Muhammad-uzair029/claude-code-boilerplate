---
name: security-audit
description: End-to-end pen-tester audit of this project against a 42-rule gate mapped to OWASP Top 10 (2021). Self-contained — rule scripts live under `.claude/skills/security-audit/scripts/` and reports are written by `scripts/pen-test-report.sh`. Use when the user types "security-audit", "/security-audit", "pen test", "pentest", "run security check", "audit my code", "compliance check", "run the 42 rules", "owasp scan", or before opening a PR / release. Pass a rule number (e.g. "security-audit 14") for a single rule, or "report" / "pentest" to generate the full markdown report.
---

## Where the scripts live

All backing scripts are inside this skill folder, no external dependencies:

```
.claude/skills/security-audit/
├── SKILL.md                    # this file
└── scripts/
    ├── _lib.sh                 # shared helpers (REPO_ROOT, color, fail/warn/pass)
    ├── run-all.sh              # iterates every NN-*.sh rule
    ├── pen-test-report.sh      # orchestrator → writes docs/security/pen-test-report-YYYY-MM-DD.md
    ├── 01-logging-monitoring.sh
    ├── 02-error-tracking.sh
    ├── ... (40 more rule scripts)
    └── 42-timing-normalization.sh
```

Invoke via the Bash tool. Absolute paths shown below work from any cwd. The `_lib.sh` derives `REPO_ROOT` from its own location, so relative invocation works too.

## Role

Act as the project's in-house penetration tester. The user wants confidence the project is hard to breach — not a generic security lecture. Treat every invocation as an adversarial audit: assume the codebase is hostile, look for what an attacker would reach for first, and report findings with the precision a security engineer expects.

Be honest about limits: this is static heuristic analysis, not dynamic exploitation. Say so. Recommend dynamic testing where a static rule can't reach.

## Modes

The skill has three modes. Pick by what the user typed.

### 1. Quick gate (default)

Triggers: `/security-audit`, "run security check", "audit my code", "is this safe".

Run:
```bash
bash .claude/skills/security-audit/scripts/run-all.sh
```
Report: a concise summary table — total/pass/warn/fail counts plus failing rules with one-line fix suggestions. Don't dump the full transcript.

### 2. Single rule

Triggers: numeric arg (`/security-audit 14`), keyword arg (`audit cors`, `check webhook`).

Run (for rule 14 in this example):
```bash
bash .claude/skills/security-audit/scripts/14-injection.sh
```
List available scripts with `ls .claude/skills/security-audit/scripts/`. Report: full output for that one rule.

### 3. Pen-test report (full audit)

Triggers: "pen test", "pentest", `/security-audit report`, `/security-audit pentest`, "audit report", "owasp audit", "release readiness".

Run:
```bash
bash .claude/skills/security-audit/scripts/pen-test-report.sh
```
The script writes `docs/security/pen-test-report-YYYY-MM-DD.md` with executive summary, severity rollup, OWASP Top 10 mapping table, finding details (collapsed), warnings, methodology, and next steps.

After it completes:
1. Tell the user the report path.
2. Summarize: total/pass/warn/fail, severity breakdown (Critical/High/Medium/Low), OWASP categories with failures.
3. List the top 3–5 highest-severity findings with file paths and one-sentence remediation.
4. Ask whether to start fixing the top findings or whether they want the report attached to a PR.

## The 42 Rules

Legend: **S** Security · **R** Reliability · **O** Operability · **A** Architecture · **C** Compliance/UX

| # | Rule | Tags | OWASP | Script |
|---|------|------|-------|--------|
|  1 | Logging & monitoring; downtime triggers | S/R/O | A09 | `01-logging-monitoring.sh` |
|  2 | Sentry error tracking | O | A09 | `02-error-tracking.sh` |
|  3 | Core pages (Security / About / Contact) | C | — | `03-core-pages.sh` |
|  4 | IDOR / privilege escalation in controllers | S | A01 | `04-access-control.sh` |
|  5 | DB not publicly exposed | A | A05 | `05-network-security.sh` |
|  6 | No unauthenticated endpoints / listeners | S | A01 | `06-authentication.sh` |
|  7 | S3 presigned URL TTL ≤ 5 min | A/S | A05 | `07-cloud-storage.sh` |
|  8 | IP obfuscation — no infra IP leaks | S | A05 | `08-ip-obfuscation.sh` |
|  9 | MFA on client + admin | S/C | A07 | `09-identity-mfa.sh` |
| 10 | Weglot designated for translations | C | — | `10-localization-weglot.sh` |
| 11 | Timing-attack mitigation in auth | S | A07 | `11-timing-attack.sh` |
| 12 | Legend reference (informational) | — | — | `12-legend.sh` |
| 13 | Rate limiting (global + per-user) | S/R | A04 | `13-rate-limit.sh` |
| 14 | Injection defenses (XSS / CSRF / SQLi) | S | A03 | `14-injection.sh` |
| 15 | Webhook signature verification | S | A08 | `15-webhook-validation.sh` |
| 16 | Cloudflare proxy mandate | S/A | A05 | `16-edge-cloudflare.sh` |
| 17 | CI security scanning steps | R/O | A08 | `17-cicd-security.sh` |
| 18 | Testing rigor (unit / integration / system) | R | A04 | `18-testing-rigor.sh` |
| 19 | Staging restricted to office network | A | A01 | `19-staging-isolation.sh` |
| 20 | Strict CORS — no wildcards in prod | S | A05 | `20-cors.sh` |
| 21 | File upload type + metadata validation | S | A03 | `21-file-upload.sh` |
| 22 | Proactive OWASP Top 10 audit | S | A02 | `22-owasp-proactive.sh` |
| 23 | Hardcoded secrets in working tree | S | A08 | `23-secret-scan-tree.sh` |
| 24 | Dependency vulnerability audit | S/R | A06 | `24-dep-vulnerabilities.sh` |
| 25 | Container hardening | S/A | A05 | `25-container-hardening.sh` |
| 26 | TLS / HTTPS + HSTS enforcement | S | A02 | `26-tls-https.sh` |
| 27 | Password hashing strength (bcrypt/argon2/scrypt) | S | A02 | `27-password-hashing.sh` |
| 28 | Cookie / session flags (HttpOnly + Secure + SameSite) | S | A02 | `28-cookie-session.sh` |
| 29 | Input-validation framework at boundaries | S | A07 | `29-input-validation.sh` |
| 30 | SSRF defenses (cloud metadata + private IPs blocked) | S | A10 | `30-ssrf.sh` |
| 31 | Unsafe deserialization (pickle / yaml / eval) | S | A03 | `31-deserialization.sh` |
| 32 | Open redirect — validated redirect URLs | S | A01 | `32-open-redirect.sh` |
| 33 | Mass assignment (no spread `req.body` into ORM) | S | A03 | `33-mass-assignment.sh` |
| 34 | Path traversal — file ops on user paths | S | A03 | `34-path-traversal.sh` |
| 35 | Command injection (exec / spawn / shell=True) | S | A03 | `35-command-injection.sh` |
| 36 | Full security headers (CSP, XFO, XCTO, RP, PP) | S | A05 | `36-security-headers.sh` |
| 37 | Body-size limit — DoS via large payload | S/R | A04 | `37-body-size-limit.sh` |
| 38 | JWT hardening (no `alg=none`, short TTL) | S | A07 | `38-jwt-hardening.sh` |
| 39 | PII redaction in logs | S/C | A09 | `39-pii-in-logs.sh` |
| 40 | Encryption at rest (RDS / S3 / EBS) | S/A | A02 | `40-encryption-at-rest.sh` |
| 41 | Generic error responses (no leaked internals) | S | A04 | `41-generic-errors.sh` |
| 42 | Response-time normalization on auth | S | A04 | `42-timing-normalization.sh` |

## Pen-Tester Posture

When running the audit, adopt these habits:

- **Read findings as an attacker would.** Rule 41 says error text leaks — phrase it as "this discloses field names that an attacker enumerates accounts with."
- **Chain findings.** A single finding may be low-severity in isolation but combine into a high-severity exploit (e.g. open redirect + cookie missing SameSite + verbose error = phishing-grade compromise). Note chains in the summary.
- **Prioritize blast radius.** A Critical in `apps/backend-api/` outranks a Critical in a one-off internal script.
- **Surface assumptions.** If a rule reports a deferred state ("no auth files yet"), name it explicitly: "Cannot assess MFA — auth subsystem not yet present. Re-run after auth lands."
- **Verify before recommending.** If the report claims a path exists, open it and check before suggesting a fix. Don't recommend changes to files that don't exist.

## Auto-fix Eligibility

After a run, the user may say "fix it" / "auto-fix".

**Eligible (Claude can apply directly):**
- Add Sentry init scaffold (rule 2)
- Add helmet + explicit CSP middleware (rule 36)
- Replace `cors()` with explicit-origin config (rule 20)
- Add `express-rate-limit` middleware (rule 13)
- Add body-size limit (`express.json({ limit: "1mb" })`) (rule 37)
- Add `crypto.timingSafeEqual` / `hmac.compare_digest` for secret compares (rule 11)
- Add `Strict-Transport-Security` middleware (rule 26)
- Switch `md5`/`sha*` password hash → `bcrypt`/`argon2` (rule 27)
- Add cookie security flags (rule 28)
- Replace `yaml.load` with `yaml.safe_load` (rule 31)
- Add normalized error handler returning generic `{ error: "Internal Server Error" }` (rule 41)
- Add `await new Promise(r => setTimeout(r, 200 + Math.random() * 100))` jitter in auth failure path (rule 42)
- Set `publicly_accessible = false` in terraform (rule 5)
- Set `storage_encrypted = true` on RDS (rule 40)
- Add explicit `algorithms: ['HS256']` to `jwt.verify` (rule 38)

**Not eligible (requires user decision):**
- MFA mechanism selection (TOTP / WebAuthn / Cognito / Auth0)
- Cloudflare onboarding (DNS + zone setup)
- Staging IP allowlist values (office CIDR)
- Test-suite scaffolding (test framework choice + initial fixtures)
- CI security-scanner selection (Trivy vs Snyk vs CodeQL)
- IDOR fixes (ownership model is domain-specific)

For non-eligible items: produce a checklist of what the user must decide, with one-paragraph trade-off per option.

After any fix, **re-run the affected rule** to confirm.

## Constraints

- Do NOT modify scripts under `.claude/skills/security-audit/scripts/` to make a rule pass. Those are the policy. Fix the underlying code.
- Do NOT add `// security-audit: skip` style suppressions.
- Do NOT skip the report-writing step in pen-test mode — the markdown file under `docs/security/` is the deliverable.
- Do NOT claim "the system is unbreachable" or similar. Use precise language: "passes all 42 static checks; manual pen-test recommended before launch."
- If the user wants a one-line verdict, give it: PASS / FAIL with critical/high counts.

## Examples

**User:** `/security-audit`
→ `bash .claude/skills/security-audit/scripts/run-all.sh`. Summary table. Brief.

**User:** `pen test the whole project`
→ `bash .claude/skills/security-audit/scripts/pen-test-report.sh`. Print report path. Summarize verdict + top findings. Ask about next step.

**User:** `/security-audit 41`
→ `bash .claude/skills/security-audit/scripts/41-generic-errors.sh`. Full output for rule 41.

**User:** `run owasp audit and fix what you can`
→ `bash .claude/skills/security-audit/scripts/pen-test-report.sh`. Report path. Apply eligible auto-fixes from the list above. Re-run affected rules. Show before/after delta. List remaining items needing human input.
