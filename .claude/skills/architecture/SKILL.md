---
name: architecture
description: Token-saving execution constraints, dataflow rules for backend-api and ai-engine routing layers, and verbosity controls. Use when designing services, routing, prompts, or inter-app contracts.
---

# Architecture — Token Discipline & Routing

## Scope

All backend and AI work in `apps/backend-api/` and `apps/ai-engine/`, plus inter-app contracts.

## 1. Dataflow Topology

```
client (frontend-ui)
   │  HTTP / WS
   ▼
backend-api  ◄── single ingress, auth, validation, persistence
   │  internal RPC
   ▼
ai-engine    ◄── model calls, retrieval, tool execution
```

- `frontend-ui` **never** calls `ai-engine` directly. Always via `backend-api`.
- `ai-engine` **never** persists user data. State lives in `backend-api`.
- Contracts between layers are typed schemas in a shared `contracts/` namespace. No implicit shapes.

## 2. Routing Layer Rules (ai-engine)

- **Model selection is explicit.** Tier per task: `fast` (haiku-class) → `balanced` (sonnet-class) → `deep` (opus-class). Default to the cheapest tier that meets quality bar.
- **Prompt caching mandatory.** Cache stable system prompts and tool definitions. Volatile context goes last.
- **Tool use over freeform generation** for any structured output. Schemas beat regex parsing.
- **Streaming default ON** for any response > 200 tokens reaching the user.
- **Retries** are bounded (max 2) with exponential backoff. Never silent infinite loops.
- **Fallback chains** are explicit, not magical. Document the fallback model + the failure mode that triggers it.

## 3. Token-Saving Constraints

Forbidden in standard completions (production code paths, not interactive dev):

- Verbose chain-of-thought in output. If thinking is needed, use extended-thinking modes that strip from final output.
- Echoing the user's prompt back before answering.
- Restating the task or summarizing the question.
- "Sure, I'd be happy to help" preambles.
- Trailing summaries ("In summary, I…") when the answer itself was the summary.
- Decorative bullet expansion when a single sentence suffices.

Encouraged:

- Direct answers. Fragments where unambiguous.
- Structured outputs (JSON, table) for machine-consumed responses.
- One-line acknowledgements over paragraph confirmations.

## 4. Backend Service Rules

- **One service = one bounded context.** Auth, billing, content each isolated. No cross-domain database joins.
- **Validation at the boundary.** Inputs validated on ingress, trusted thereafter. Never re-validate internally.
- **Idempotency keys** on any mutation reachable from the client.
- **Observability mandatory.** Every request: trace id, latency, outcome. Logged in structured JSON.
- **No business logic in routes.** Routes parse, call a use-case function, format response. That is all.

## 5. Inter-App Contracts

- Shared types live in `contracts/` (TypeScript) or `contracts.proto` (cross-runtime).
- Breaking changes require a versioned endpoint or schema bump. Never silent reshapes.
- Errors are typed (`{ code, message, details }`), not bare strings.

## 6. Performance Budgets

| Tier            | p50 latency | p95 latency |
| --------------- | ----------- | ----------- |
| HTTP (backend)  | < 100 ms    | < 400 ms    |
| AI fast tier    | < 800 ms    | < 2 s       |
| AI balanced     | < 2 s       | < 6 s       |
| AI deep         | < 6 s       | < 20 s      |

Exceeding budget → optimize or downgrade tier before merging.

## 7. Anti-Patterns

- `ai-engine` calling its own HTTP for retrieval instead of using injected providers.
- `backend-api` calling out to LLMs directly (route through `ai-engine`).
- Stuffing entire datasets into a prompt — use retrieval.
- Logging full prompts/responses to stdout in prod (PII risk + token cost).
- Hidden global mutable state across requests.

## Checklist (run before merging backend/AI changes)

- [ ] Correct layer for the change (backend vs ai-engine)
- [ ] Schemas updated in `contracts/` if cross-app
- [ ] Model tier chosen explicitly with justification
- [ ] Prompt cache structure preserved (stable parts first)
- [ ] No verbose preamble/summary in production prompts
- [ ] Latency within budget
- [ ] Trace + structured log present
