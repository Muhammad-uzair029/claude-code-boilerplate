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

## Cache Discipline

This file lives at the top of the context window — it must stay stable to preserve prompt-cache hits across turns. Volatile workspace details belong in the per-app `CLAUDE.md` under `apps/<workspace>/`. Edit those for local concerns; edit this only for repo-wide policy.
