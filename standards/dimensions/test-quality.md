# Test Quality

## Principle

Tests must cover the most complex and risky code first — not the easiest code to test.

## Criteria

- [ ] Business logic and critical paths have the highest test coverage — not just schema validation or utility functions
- [ ] Every code path tested: happy path, edge cases, error conditions, boundary values
- [ ] Every `if` branch and every error handler has a test exercising it
- [ ] Tests verify specific outcomes (return values, side effects, state changes) — not just "doesn't throw"
- [ ] Boundary conditions tested: 0 items, 1 item, max items, empty strings, null/missing fields
- [ ] Every bug fix includes a regression test that would have caught the bug
- [ ] External dependencies mocked at boundaries — but actual logic tested with real execution
- [ ] Integration tests cover the critical data flow end-to-end (API → service → DB → response)
- [ ] Test names describe the scenario and expected behavior, not the implementation
- [ ] No test files with zero assertions — every test makes a meaningful claim

## Coherence Audit Severity

These findings are **BLOCKING** (will degrade future AI sessions or hurt end users):
- Happy-path-only test coverage — tests exist but cover no error paths, no boundary values, no negative cases
- Missing error path tests for user-facing flows (form validation failures, API error responses, auth failures)
- Shallow browser/integration tests that assert element presence but not behavior (checking a button exists without testing what happens when you click it with invalid data)
- Implementation-mirroring tests that assert the code does what it does rather than what it should do (testing internal state instead of observable behavior)
- Test patterns that future sessions will copy — if the first session writes happy-path-only tests, every subsequent session follows that pattern

These findings are **INFO** (cosmetic even for agents):
- Test file naming style preferences
- Test organization structure (grouping by feature vs by type)
- Minor assertion style differences that don't affect clarity

## Common Violations

- Tests concentrated in easy-to-generate areas (schema validation, utilities) while complex server logic has zero coverage
- Dashboard/frontend with zero tests while backend schemas are heavily tested
- "Tests exist where easiest to generate, absent where they matter most"
- Tests that only cover happy path — no error paths, no boundary values
- Mocking so aggressively that tests verify mock behavior, not real logic
- Integration tests that test the framework, not the application logic
- Test suite that passes but doesn't prevent real bugs from shipping
- Browser tests that check "page loads" and "form exists" without testing error states, loading states, or realistic user flows with invalid input

## Language-Specific Guidance

**Python:**
- Use `pytest` with fixtures for setup/teardown, not `unittest.TestCase`
- Use `pytest.mark.parametrize` for boundary value testing
- Use `factory_boy` or similar for test data factories
- Integration tests: use a test database (SQLite in-memory or testcontainers), not mocks
- Measure coverage with `pytest-cov` — focus on branch coverage, not line coverage

**TypeScript:**
- Use `vitest` or `jest` with descriptive `describe`/`it` blocks
- Use `MSW` for API mocking in frontend tests
- Use `testing-library` for component tests — test behavior, not implementation
- Integration tests: use `supertest` for API testing, `testcontainers` for DB

**Go:**
- Use table-driven tests for comprehensive input coverage
- Use `testify/assert` for readable assertions
- Use `httptest` for HTTP handler testing
- Use interfaces + test doubles for dependency injection, not mocking frameworks

## Opt-Out Justification

- Pure UI prototypes or design explorations where behavior isn't settled
- One-time migration scripts that will be deleted after running
- Generated code (API clients, ORM models) where the generator is tested, not the output
