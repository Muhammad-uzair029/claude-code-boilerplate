# softaims-boilerplate plugins

Each skill from `.claude/skills/` is wrapped here as a standalone plugin. The team installs them from the in-repo marketplace at `.claude-plugin/marketplace.json`.

## Layout

```
plugins/
  <plugin-name>/
    .claude-plugin/plugin.json   # plugin manifest
    skills/<plugin-name>/        # the skill (SKILL.md + any assets)
```

## Plugins

| Plugin | What it does |
|---|---|
| `generate-docs` | Writes feature docs from recent git changes |
| `git-push` | Diff review → Conventional Commit → push staged only |
| `null-safety-scan` | Null/undefined/None audit on staged TS/JS/Python |
| `pr-open` | Opens GitHub PR with auto-filled title + checklist |
| `pre-merge-check` | Parallel lint + typecheck + tests, block on fail |
| `react-native-optimization-and-architecture` | RN/Expo performance + architecture rules |
| `security-audit` | 42-rule OWASP gate + pen-test report |
| `security-scan` | Staged-diff secrets + dep vuln scan |
| `system-design` | Cross-stack design audit (RN ↔ NestJS ↔ Python AI) |
| `team-pulse` | Daily/weekly team activity digest |

## Install for the team

From the repo root:

```bash
# Add this repo as a local marketplace
/plugin marketplace add .

# Install a single plugin
/plugin install generate-docs@softaims-boilerplate

# Or install all of them
for p in generate-docs git-push null-safety-scan pr-open pre-merge-check \
         react-native-optimization-and-architecture security-audit \
         security-scan system-design team-pulse; do
  /plugin install "$p@softaims-boilerplate"
done
```

After pushing to GitHub, the team can install directly from there:

```bash
/plugin marketplace add Softaims/claude-code-boilerplate
/plugin install <plugin-name>@softaims-boilerplate
```

## Adding a new plugin

1. Create `plugins/<name>/skills/<name>/SKILL.md` (with frontmatter).
2. Create `plugins/<name>/.claude-plugin/plugin.json` (name, version, description, author, category).
3. Add an entry to `.claude-plugin/marketplace.json`.
4. Commit and push.

## Note on the source skills

These plugins **copy** the skills currently in `.claude/skills/`. Both copies will appear in `/skills` until one is removed. Pick one source of truth before merging — most likely the plugin copies, then delete `.claude/skills/` from the repo.
