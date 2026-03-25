# DRY / Code Reuse

## Principle

Every piece of logic has exactly one authoritative source — duplication is a defect, not a convenience.

## Criteria

- [ ] No logic duplicated across files — if the same pattern appears in 3+ places, it's extracted into a shared module
- [ ] Types, constants, and shared config live in dedicated modules — no ad-hoc inline definitions
- [ ] Framework integration variants (e.g., adapters for different providers) share a common base — not copy-pasted with minor tweaks
- [ ] Shared utilities are named descriptively and colocated with their consumers — not dumped in a `utils/` junk drawer
- [ ] Configuration values defined once and referenced — not hardcoded in multiple locations
- [ ] Test helpers extracted when the same setup/assertion pattern appears in 3+ test files
- [ ] API response shapes, error formats, and validation rules defined once and reused

## Common Violations

- Framework integrations (e.g., `generic.py`, `langchain.py`, `llamaindex.py`) that are 90% identical with copy-pasted send/capture methods
- The same validation logic in both API handler and service layer
- Error response formatting duplicated across every endpoint instead of using shared error middleware
- Config values (timeouts, limits, URLs) hardcoded in multiple files instead of sourced from a config module
- Test files each defining their own mock factories instead of sharing a test helper

## Language-Specific Guidance

**Python:**
- Use base classes or mixins for shared behavior across variants
- Use `__init__.py` re-exports to create clean public APIs for shared modules
- Use `conftest.py` fixtures for shared test setup — not helper functions copied across test files

**TypeScript:**
- Use composition over inheritance for shared behavior
- Use barrel files (`index.ts`) for clean module exports
- Use factory functions for test data — shared in a `testing/` module
- Use middleware for cross-cutting concerns (auth, error handling, logging)

**Go:**
- Use embedded structs for shared fields
- Use interfaces for shared behavior contracts
- Use table-driven tests with shared test case definitions
- Use functional options pattern to avoid config duplication

## Opt-Out Justification

- Small projects (< 500 LOC) where extraction would create more indirection than value
- Prototype code that's expected to be rewritten before shipping
