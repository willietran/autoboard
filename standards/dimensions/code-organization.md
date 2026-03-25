# Code Organization

## Principle

A new contributor should find any piece of functionality by intuition — structure reveals intent.

## Criteria

- [ ] Each file has one clear responsibility — if it does two things, split it
- [ ] Related code colocated: components with their tests, helpers, and styles in the same directory
- [ ] Consistent module structure: each module exports from a clear entry point
- [ ] Predictable naming: files, functions, and variables named so purpose is obvious without reading implementation
- [ ] No junk drawer modules: no catch-all `utils/`, `helpers/`, or `common/` files — each helper has a descriptive name and dedicated file or is colocated with its consumer
- [ ] Clear dependency direction: higher-level modules depend on lower-level, not circular
- [ ] Zero dead code: no commented-out blocks, unused functions, orphaned imports, stale TODOs
- [ ] No debug artifacts: no console.log, print statements, or temporary test values in committed code
- [ ] Comments explain why, not what — the code explains what, comments explain non-obvious decisions
- [ ] Section dividers and consistent formatting aid scanning in larger files

## Common Violations

- `utils.ts` with 40 unrelated functions
- Components, their styles, their tests, and their helpers in four different directory trees
- Circular imports between modules
- Commented-out code "in case we need it later" — that's what version control is for
- Files named by technology (`hooks.ts`, `queries.ts`) instead of domain (`user-auth.ts`, `experiment-results.ts`)
- No consistent pattern — some modules use barrel exports, some don't; some colocate tests, some don't

## Language-Specific Guidance

**Python:**
- Use packages (directories with `__init__.py`) for modules with multiple files
- Re-export public API from `__init__.py` — consumers import from the package, not internal files
- Use `conftest.py` for shared test fixtures colocated with the test directory
- Follow the "one class per file" convention for substantial classes

**TypeScript:**
- Use barrel files (`index.ts`) for clean public module APIs
- Colocate: `Button/index.tsx`, `Button/Button.test.tsx`, `Button/Button.module.css`
- Use path aliases (`@/components`, `@/lib`) for clean imports
- Feature-based directories over type-based (`features/auth/` not `controllers/`, `services/`, `models/`)

**Go:**
- Use package-level organization — each package has a clear domain purpose
- Export only what consumers need — unexported by default
- Use `internal/` for packages that shouldn't be consumed outside the module
- Tests live alongside source: `user.go` and `user_test.go` in the same package

## Opt-Out Justification

- Single-file scripts where organization is inherently simple
- Generated code that shouldn't be manually organized
