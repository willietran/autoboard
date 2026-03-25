# Observability

## Principle

If it happens in production, you must be able to see it, trace it, and alert on it — without deploying new code.

## Criteria

- [ ] Structured logging (JSON or key-value) with consistent fields: timestamp, level, request ID, user ID, operation
- [ ] Request ID propagation through the entire request lifecycle — from API entry to DB query to response
- [ ] Health check endpoint that verifies critical dependencies (database, cache, external services)
- [ ] Key business operations logged: not just errors, but important state transitions (user created, experiment promoted, payment processed)
- [ ] Error logging includes enough context to reproduce: request parameters, relevant IDs, stack trace
- [ ] Metrics on critical paths: request latency, error rates, queue depths, cache hit rates
- [ ] Log levels used correctly: ERROR for failures needing attention, WARN for degraded behavior, INFO for business events, DEBUG for development
- [ ] No sensitive data in logs: no passwords, tokens, PII, or full request bodies with sensitive fields
- [ ] Dead letter queues or equivalent for async operations that fail — no silent data loss
- [ ] Alerting-ready: logs and metrics structured so monitoring tools can create meaningful alerts

## Common Violations

- Fire-and-forget background threads that lose errors without any observability
- `print()` or `console.log()` instead of structured logging
- No request ID — errors in logs can't be correlated to specific requests
- Logging everything at INFO level — important events buried in noise
- Health check that returns 200 without actually checking dependencies
- No logging of business events — can answer "is it up?" but not "is it working correctly?"
- Sensitive data in logs: full API keys, user passwords, authentication tokens
- Error logs with no context: `"Error occurred"` with no indication of what, where, or why

## Language-Specific Guidance

**Python:**
- Use `structlog` for structured, context-rich logging
- Use OpenTelemetry for distributed tracing and metrics
- Use middleware to inject request ID into all log entries
- Use `logging.getLogger(__name__)` — not `print()`

**TypeScript:**
- Use `pino` or `winston` with JSON formatting
- Use `cls-hooked` or `AsyncLocalStorage` for request-scoped context
- Use OpenTelemetry JS SDK for tracing
- Use middleware to attach request ID to all logs and response headers

**Go:**
- Use `slog` (stdlib, Go 1.21+) or `zerolog` for structured logging
- Use `context.Context` for request-scoped values (request ID, user ID)
- Use OpenTelemetry Go SDK for tracing and metrics
- Use middleware to inject tracing context

## Opt-Out Justification

- CLI tools or scripts where stdout/stderr is sufficient observability
- Local development tools not deployed to production
- Libraries (observability is the consumer's responsibility)
