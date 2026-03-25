# Error Handling

## Principle

Errors must be visible, specific, and actionable — never silently swallowed, never generic, never fire-and-forget.

## Criteria

- [ ] Every `catch`/`except` block either logs with context, re-throws, or returns a meaningful error — no empty catch blocks
- [ ] Error messages describe what went wrong AND what was expected, with relevant context (IDs, file paths, values)
- [ ] Functions fail fast with clear errors rather than propagating bad state silently
- [ ] Specific exception types used where they matter — not blanket `Exception`/`Error` catches
- [ ] Background/async operations have error reporting paths — no fire-and-forget without observability
- [ ] HTTP endpoints return appropriate status codes with structured error responses
- [ ] Errors at system boundaries (API calls, DB queries, file I/O) are caught and wrapped with context
- [ ] Retry logic has bounded attempts, backoff, and logs each failure
- [ ] Errors in non-critical paths (logging, analytics, telemetry) don't crash the main flow

## Common Violations

- `except Exception: pass` or `catch (e) {}` — silently swallowing errors
- Fire-and-forget threads/goroutines that lose errors without any observability
- Generic "Something went wrong" error messages with no context for debugging
- SDK/library code that silently drops errors to avoid "bothering" the caller
- Retry loops with no max attempts or backoff — infinite retry on permanent failures
- Catching broad exception types when only specific failures are expected
- `try/except` around entire functions instead of specific operations that can fail

## Language-Specific Guidance

**Python:**
- Use specific exception types: `except ValueError` not `except Exception`
- Use `raise ... from e` to preserve exception chains
- Use `logging.exception()` in catch blocks to include stack traces
- Background tasks: use `concurrent.futures` with error callbacks, or a task queue with DLQ

**TypeScript:**
- Use typed error classes or discriminated unions for error types
- Use `cause` property to chain errors: `new Error("context", { cause: originalError })`
- Async errors: always `.catch()` on promises or use try/catch in async functions
- Express: use error middleware, not try/catch in every handler

**Go:**
- Always check returned errors — never `_ = someFunc()`
- Wrap errors with context: `fmt.Errorf("loading config: %w", err)`
- Use `errors.Is()` and `errors.As()` for type-safe error checking
- Goroutines: send errors through channels or use `errgroup`

## Opt-Out Justification

Error handling should rarely be disabled. Legitimate exceptions:
- Throwaway scripts or one-time data migrations where failure is immediately visible
- Prototype code explicitly marked as non-production
