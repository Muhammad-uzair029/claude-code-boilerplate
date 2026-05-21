# `system-design` Skill — What It Does and How to Use It

A shareable reference for the team. The skill lives at `.claude/skills/system-design/SKILL.md` in this repo. This document is the human-readable companion — paste it into onboarding docs, share with stakeholders, or refer to it when explaining the gates.

## TL;DR

`system-design` is an end-to-end design auditor. It takes any entry point in our stack — a React Native screen, a NestJS controller, a Python AI handler, or a free-form description of a feature — and produces a structured audit that traces the request across all three services and flags blockers, risks, and advisory issues before merge.

It is **strict by design**. When it finds a blocker, it blocks. Warn-only gates were not the call — our team chose block-on-fail across project hooks.

## When it runs

Trigger phrases:

- `system-design` / `/system-design`
- "design review"
- "architecture review"
- "race condition check"
- "audit my system"
- "is this production ready"

It auto-engages when anyone mentions production, scale, race conditions, deadlocks, flaky behavior, latency budgets, contract drift, or rollout risk — even without an explicit invocation.

## Stack assumption

The skill assumes our standard three-tier shape:

| Workspace            | Stack                     | Owns                                       |
| -------------------- | ------------------------- | ------------------------------------------ |
| `apps/frontend-ui`   | React Native              | Rendering, client state, navigation        |
| `apps/backend-api`   | NestJS                    | Auth, persistence, business rules          |
| `apps/ai-engine`     | Python (FastAPI / worker) | Model calls, retrieval, tool execution     |

Stack-specific deep dives (RN, NestJS, Python AI) live as separate root-level skills. The audit defers to them for stack-internal style and stays focused on the cross-service seams.

If a project deviates from this shape, the audit still runs — the universal principles apply regardless of stack.

## What the audit checks

### Universal principles (every audit)

1. **Single source of truth per concern.** Auth → backend. Inference → AI engine. Rendering → frontend. Crossing the line is a layering violation.
2. **Contracts at boundaries are typed and versioned.** No silent reshapes. Breaking changes get a new version.
3. **Validation at the boundary, not in the middle.** First function to receive untrusted input validates; downstream trusts.
4. **Mutations are idempotent.** Every state-changing endpoint accepts an idempotency key. Double-tap, retry, redelivery — none should double-charge.
5. **State ownership is explicit.** Every piece of state has a named writer, named reader, and named TTL.
6. **Performance budgets are explicit and enforced.** End-to-end p95 budgets are summed across services and treated as merge-blockers if exceeded.
7. **Observability is non-optional.** Trace ID end-to-end. Structured JSON logs. Typed errors `{code, message, details}`.

### Cross-cutting checks (every audit)

- **Race condition taxonomy:** lost update, phantom read, double-submit, stale optimistic UI, out-of-order responses, write-write across services, cache stampede.
- **Retry / replay safety:** what happens if this runs twice? three times?
- **Partial failure:** what if first side succeeds, second fails?
- **Backpressure:** queues bounded? concurrency limits set? DLQs configured?
- **Auth/authz across hops:** every hop re-asserts. No "the backend said so" trust without a signed token.
- **PII and token cost:** no full prompts/responses in logs. Tool use over freeform parsing.

### Production readiness rollout checklist

For any cross-service change:

1. Backward compatibility (mobile clients in the field for weeks).
2. Migration safety (reversible, tested at volume, old-code-reads-new-schema safe).
3. Feature flag with kill switch.
4. Observability wired *before* enabling the feature.
5. Alerting in place.
6. Runbook written — what does on-call check first at 3 a.m.?

### Anti-patterns flagged on sight

Any one of these is a blocker until proven safe:

- Client computing money / authorization
- Backend calling LLMs directly
- AI engine writing user data to its own database
- Optimistic UI with no reconciliation path
- `useEffect` data fetching without cancellation
- `async def` handlers doing CPU-bound work (blocks the event loop)
- Implicit `any` at a service boundary
- Multi-writer caches with no invalidation strategy
- Read-modify-write without transaction or version check
- Queues without DLQ + max-attempt
- Logging full prompts/responses in prod
- Cross-service database joins
- Transactions containing external HTTP calls
- External calls without explicit timeouts
- TypeORM `synchronize: true` outside dev config
- Env var fallbacks that ship a dev default to prod (`?? 'devsecret'`)

### UI/UX modularity (frontend-ui)

When the audit touches the RN app, the original UI layering rules also apply:

- Component layers: `tokens → primitives → composites → patterns → screens` (one-way imports).
- Reuse threshold: extract on the third use, not the first.
- Prop API: single `variant` instead of boolean explosion.
- Tokens only — no raw hex, no magic px.
- Accessibility ≥ WCAG AA: keyboard reachable, focus-visible, labels associated, no color-only meaning.

## What the output looks like

Every audit produces this exact structure. Findings cite `file:line` so reviewers can navigate directly.

```
# System Design Audit — <feature / entry point>

## Map
- Entry: <file:line>
- Peers traced: <file:line per service>
- Direction: client → backend → AI (or whatever applies)
- Contracts crossed: <schema names + file:line>

## Blockers (must fix before merge)
- [BLOCKER] <one-line problem>
  Where: <file:line>
  Why it blocks: <root cause + principle violated>
  Fix: <concrete change, named file/function>

## Risks (fix before production rollout)
- [RISK] ...

## Advisory (worth a follow-up, not blocking)
- [ADVISORY] ...

## Verified clean
- <checks that passed — proves coverage>

## Evidence gaps
- <peer code not provided — name the file or grep that would resolve it>
```

If the audit finds no blockers and no risks, it says so plainly and lists what was verified. **Silence is not a passing grade.**

## How to invoke it

In Claude Code:

```
/system-design
```

Or share the file you want reviewed and ask any of: "design review", "audit this", "is this production ready", "race condition check".

The audit will:

1. Map the request across services (entry point + peers + contracts crossed).
2. Apply the seven universal principles.
3. Run cross-cutting checks (race conditions, idempotency, backpressure, auth, observability).
4. Produce the structured report.

If peer code is missing from the share, the audit will say so explicitly under **Evidence gaps** rather than guess the peer's behavior.

## Team workflow

- **Before opening a PR that touches more than one service:** run `/system-design` against the entry-point file. Treat blockers as merge-blockers.
- **Before merging anything with the word "production" in the description:** run `/system-design` even if the change is single-service. The rollout checklist applies.
- **During incidents:** run `/system-design` on the affected handler to surface the structural issue, not just the immediate cause.

## What this skill is *not*

- Not a linter — that is `pre-merge-check` (lint + typecheck + tests).
- Not a secret scanner — that is `security-scan`.
- Not a null-safety auditor — that is `null-safety-scan`.
- Not a code reviewer for style — that is `coderabbit:code-review`.

`system-design` focuses on the layer above all of those: **structural correctness across services**. It assumes the lint passes, the types check, and the tests run, and asks the questions those tools cannot answer.

## Change log

- **2026-05-21** — Expanded scope from frontend-only UI/UX rules to full-stack audit covering RN + NestJS + Python AI. Added cross-service race-condition taxonomy, production-readiness rollout checklist, and end-to-end performance budgets. UI/UX modularity rules carried forward unchanged.
