---
name: system-design
description: Enforces modular, reusable component UI/UX patterns for the frontend-ui workspace. Use when designing components, layouts, or interaction patterns.
---

# System Design — UI/UX Modularity

## Scope

All UI work inside `apps/frontend-ui/` and any shared design primitives consumed by other apps. Activates on component creation, layout work, design-system edits, accessibility reviews.

## Core Rules

### 1. Component Layers (strict)

```
tokens → primitives → composites → patterns → screens
```

- **tokens** — color, spacing, radius, type ramp, motion. No JSX.
- **primitives** — `<Button>`, `<Input>`, `<Stack>`. One concern. No business logic.
- **composites** — `<FormField>`, `<Card>`. Combine primitives. Still domain-agnostic.
- **patterns** — `<AuthForm>`, `<DataTable>`. Domain-aware, reusable across screens.
- **screens** — route-level. Orchestrate patterns. No styling beyond layout.

A layer may import only from layers below it. Lateral imports inside a layer are allowed.

### 2. Reuse Threshold

- 1 use → inline.
- 2 uses → leave duplicated.
- 3 uses → extract.

Premature extraction is worse than duplication.

### 3. Prop API Discipline

- Required props are positional in intent (semantically core). Optional props are visual variants.
- No boolean explosion. Replace `isPrimary | isSecondary | isDanger` with a single `variant: "primary" | "secondary" | "danger"`.
- Forward unknown props (`...rest`) only on primitives, never composites.
- Children > slots > render-props, in that preference order.

### 4. Styling Rules

- Tokens only. No raw hex, no magic px outside the token file.
- Spacing via the scale (`space.1`, `space.2`, …). No arbitrary `padding: 13px`.
- Responsive = mobile-first. `sm/md/lg/xl` breakpoints. No fixed widths above breakpoint.

### 5. State Ownership

- Local UI state (open/closed, hover) — component-local.
- Cross-component state — lift to nearest common ancestor or a scoped context.
- Server state — never in component state. Use the data-fetching layer.

### 6. Accessibility (non-negotiable)

- Every interactive primitive: keyboard reachable, focus-visible, ARIA role correct.
- Color contrast ≥ WCAG AA on text. Don't rely on color alone for meaning.
- Forms: every input has a `<label>`. Errors associated via `aria-describedby`.

### 7. Naming

- Components: `PascalCase` matching filename.
- Props: `camelCase`, descriptive (`onSubmit`, not `submit`).
- Tokens: `category.scale` (`color.bg.surface`, `space.4`).

## Anti-Patterns (do not ship)

- God components handling fetch + state + render + routing.
- Inline styles for production code (only acceptable in dev playgrounds).
- Copy-pasted component variants instead of a variant prop.
- `any`-typed props, untyped event handlers.
- Wrappers that add no value (`<MyDiv>` = `<div>` with one className).

## Checklist (run before merging UI changes)

- [ ] Component placed in the correct layer
- [ ] Tokens used for all color/spacing/type
- [ ] Variant prop instead of boolean explosion
- [ ] Keyboard + screen-reader verified
- [ ] No duplicated logic against an existing primitive
- [ ] Storybook / preview entry added (if applicable)
