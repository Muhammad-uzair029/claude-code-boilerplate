# Penetration Test Report — claude-code-boilerplate

| | |
|---|---|
| **Date** | 2026-06-02 14:06:20+0500 |
| **Branch** | `feat/security-rules` |
| **Commit** | `b18dac7` |
| **Methodology** | Static heuristic source-code audit (42-rule gate + OWASP Top 10 mapping) |
| **Scope** | `apps/`, `infra/`, `terraform/`, `.github/`, root configs |
| **Verdict** | **FAIL** |

> ⚠️ This is an automated static-analysis pass, not a substitute for an external pen-test.
> It catches misconfigurations and dangerous code patterns. It does **not** exercise the running
> application, fuzz inputs, attempt real exploits, or test business-logic flaws. Pair this gate
> with dynamic testing (DAST), dependency scanning in CI, and an annual external review.

## Executive Summary

- **42** rules evaluated
- **24** passed · **7** passed with warnings · **11** failed
- Failure severity: **0 Critical · 8 High · 3 Medium · 0 Low**

11 rule(s) failed. Top priority: resolve Critical and High findings before next release.

## Severity Legend

| Severity | Meaning |
|---|---|
| Critical | Direct path to RCE, auth bypass, or data exfiltration. Block release. |
| High     | Exploitable under common conditions or material defense-in-depth gap. |
| Medium   | Defense-in-depth or information leak. Schedule for next sprint. |
| Low      | Compliance / UX / process hygiene. Track in backlog. |

## OWASP Top 10 (2021) Coverage

| OWASP | Status | Failing rules | Passing rules |
|---|---|---|---|
| A01:2021 — Broken Access Control | ✅ pass | — | 04 06 19 32  |
| A02:2021 — Cryptographic Failures | ❌ fail | 26  | 22 27 28 40  |
| A03:2021 — Injection | ✅ pass | — | 14 21 31 33 34 35  |
| A04:2021 — Insecure Design | ❌ fail | 13 18 37  | 41 42  |
| A05:2021 — Security Misconfiguration | ❌ fail | 16 36  | 05 07 08 20 25  |
| A06:2021 — Vulnerable & Outdated Components | ✅ pass | — | 24  |
| A07:2021 — Identification & Authentication Failures | ❌ fail | 09 29  | 11 38  |
| A08:2021 — Software & Data Integrity Failures | ❌ fail | 17  | 15 23  |
| A09:2021 — Security Logging & Monitoring Failures | ❌ fail | 01 02  | 39  |
| A10:2021 — Server-Side Request Forgery (SSRF) | ✅ pass | — | 30  |

## Findings

| Rule | Severity | OWASP | Tags | Title |
|---|---|---|---|---|
| 01 | High | A09 | S/R/O | Logging & Monitoring |
| 02 | Medium | A09 | O | Error Tracking |
| 09 | High | A07 | S/C | MFA |
| 13 | High | A04 | S/R | Rate Limiting |
| 16 | High | A05 | S/A | Cloudflare proxy mandate |
| 17 | High | A08 | R/O | CI/CD security scanning |
| 18 | Medium | A04 | R | Testing Rigor |
| 26 | High | A02 | S | TLS / HTTPS enforcement |
| 29 | Medium | A07 | S | Input-validation framework |
| 36 | High | A05 | S | Security headers |
| 37 | High | A04 | S/R | Body size limit |

### Finding Details

#### 01 · Logging & Monitoring — High (A09)

**Tags:** S/R/O  
**Script:** `.claude/bin/01-logging-monitoring.sh`

<details><summary>Scan output</summary>

```
[Rule 01] Logging & Monitoring (S/R/O)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no structured logger usage detected (winston/pino/nest Logger/structlog/loguru). Wire one and emit per-endpoint logs.
  ! no CloudWatch / CloudTrail integration markers found. Confirm log shipping is configured at the infra layer.
  ✗ no downtime alerting markers (health endpoint, SNS, uptime monitor) detected.

Rule 01 FAILED — 2 violation(s), 1 warning(s)
```

</details>

#### 02 · Error Tracking — Medium (A09)

**Tags:** O  
**Script:** `.claude/bin/02-error-tracking.sh`

<details><summary>Scan output</summary>

```
[Rule 02] Error Tracking (Sentry) (O)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ Sentry not integrated. Install @sentry/node|@sentry/react|sentry-sdk and call Sentry.init at app boot.

Rule 02 FAILED — 1 violation(s), 0 warning(s)
```

</details>

#### 09 · MFA — High (A07)

**Tags:** S/C  
**Script:** `.claude/bin/09-identity-mfa.sh`

<details><summary>Scan output</summary>

```
[Rule 09] MFA (client + admin) (S/C)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no MFA/TOTP/WebAuthn integration markers found. Enforce MFA on login (esp. admin).

Rule 09 FAILED — 1 violation(s), 0 warning(s)
```

</details>

#### 13 · Rate Limiting — High (A04)

**Tags:** S/R  
**Script:** `.claude/bin/13-rate-limit.sh`

<details><summary>Scan output</summary>

```
[Rule 13] Rate Limiting (global + per-user) (S/R)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no rate-limiting middleware found (express-rate-limit / @nestjs/throttler / slowapi / fastapi-limiter).

Rule 13 FAILED — 1 violation(s), 0 warning(s)
```

</details>

#### 16 · Cloudflare proxy mandate — High (A05)

**Tags:** S/A  
**Script:** `.claude/bin/16-edge-cloudflare.sh`

<details><summary>Scan output</summary>

```
[Rule 16] Cloudflare proxy mandate (S/A)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no Cloudflare references (config/proxy/headers). All public web routes must sit behind Cloudflare.

Rule 16 FAILED — 1 violation(s), 0 warning(s)
```

</details>

#### 17 · CI/CD security scanning — High (A08)

**Tags:** R/O  
**Script:** `.claude/bin/17-cicd-security.sh`

<details><summary>Scan output</summary>

```
[Rule 17] CI/CD security scanning (R/O)
  ✗ .github/workflows/ missing — no CI to gate.

Rule 17 FAILED — 1 violation(s), 0 warning(s)
```

</details>

#### 18 · Testing Rigor — Medium (A04)

**Tags:** R  
**Script:** `.claude/bin/18-testing-rigor.sh`

<details><summary>Scan output</summary>

```
[Rule 18] Testing Rigor (unit/integration/system) (R)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no unit test files or directories found
  ✗ no integration test files or directories found
  ✗ no system test files or directories found
  ! no jest/vitest/pytest config file located

Rule 18 FAILED — 3 violation(s), 1 warning(s)
```

</details>

#### 26 · TLS / HTTPS enforcement — High (A02)

**Tags:** S  
**Script:** `.claude/bin/26-tls-https.sh`

<details><summary>Scan output</summary>

```
[Rule 26] TLS / HTTPS enforcement (S)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no Strict-Transport-Security / HSTS header configured

Rule 26 FAILED — 1 violation(s), 0 warning(s)
```

</details>

#### 29 · Input-validation framework — Medium (A07)

**Tags:** S  
**Script:** `.claude/bin/29-input-validation.sh`

<details><summary>Scan output</summary>

```
[Rule 29] Input-validation framework (S)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no input-validation library found (zod/joi/yup/pydantic/marshmallow/class-validator)

Rule 29 FAILED — 1 violation(s), 0 warning(s)
```

</details>

#### 36 · Security headers — High (A05)

**Tags:** S  
**Script:** `.claude/bin/36-security-headers.sh`

<details><summary>Scan output</summary>

```
[Rule 36] Security headers (S)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ missing security header config: Content-Security-Policy
  ✗ missing security header config: X-Frame-Options
  ✗ missing security header config: X-Content-Type-Options
  ✗ missing security header config: Referrer-Policy
  ✗ missing security header config: Permissions-Policy

Rule 36 FAILED — 5 violation(s), 0 warning(s)
```

</details>

#### 37 · Body size limit — High (A04)

**Tags:** S/R  
**Script:** `.claude/bin/37-body-size-limit.sh`

<details><summary>Scan output</summary>

```
[Rule 37] Body size limit (S/R)
  · no apps/ or infra/ present yet — template state; rule applies once workspaces land
  ✗ no request-body size limit configured (express.json({limit}), nginx client_max_body_size, multer limits, etc.)

Rule 37 FAILED — 1 violation(s), 0 warning(s)
```

</details>

## Warnings (advisory)

| Rule | Tags | Title |
|---|---|---|
| 03 | C | Core Pages |
| 10 | C | Localization |
| 14 | S | Injection Defenses |
| 19 | A | Staging office-network only |
| 22 | S | Proactive OWASP audit |
| 27 | S | Password hashing strength |
| 39 | S/C | PII redaction in logs |

## Methodology & Limitations

- **Static analysis only.** No requests are sent to a running service. Logic flaws that require
  runtime context (race conditions on shared state, business-logic abuse, deserialization gadgets
  triggered by specific payloads) are out of scope.
- **Heuristic grep-based detection.** False positives and false negatives are possible. Every
  failing finding includes raw scan output so an engineer can confirm.
- **No exploitation attempted.** This report flags dangerous patterns; whether each is reachable
  from an untrusted input must be reviewed manually.
- **OWASP mapping is indicative**, not exhaustive. A single rule may relate to multiple
  categories; the table picks the closest primary fit.

## Recommended Next Steps

1. Resolve every **Critical** and **High** finding above; rerun `make security-all`.
2. Wire the gate into CI: fail the pipeline if `make security-all` exits non-zero (covers rule 17).
3. Add dynamic analysis: dependency scanner (`trivy`/`snyk`/`grype`), SAST (`semgrep`/`codeql`),
   secret scanner (`gitleaks`/`trufflehog`) on every PR.
4. Commission an external pen-test before launch and after major architectural changes.
5. Run a tabletop incident-response drill — "what do we do when a finding becomes a real breach?"

---
_Generated by `.claude/bin/pen-test-report.sh`. Source rules under `.claude/bin/NN-*.sh`._
