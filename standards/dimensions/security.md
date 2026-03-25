# Security

## Principle

Never trust data that crosses a trust boundary — validate, sanitize, and enforce access control at every system edge.

## Criteria

- [ ] All external input validated server-side at system boundaries (forms, API bodies, query params, URL params, uploads) using schema validation
- [ ] Parameterized queries or ORMs for all database access — no string interpolation into SQL
- [ ] Argument arrays for all subprocess calls — no string interpolation into shell commands
- [ ] Every endpoint and data query verifies the requesting user owns the resource (default-deny)
- [ ] No secrets (API keys, tokens, passwords) in client bundles, logs, error messages, or committed code
- [ ] `.env` gitignored; secrets sourced from environment variables or a secrets manager
- [ ] CORS, CSP, and cookie flags configured explicitly — not left as framework defaults
- [ ] State-changing endpoints protected by CSRF tokens or SameSite cookies
- [ ] Abuse-prone endpoints (auth, payment, upload, registration) rate-limited
- [ ] All HTML output sanitized — no unsanitized dynamic rendering (XSS prevention)
- [ ] Stack traces and debug info suppressed in production error responses
- [ ] Webhook endpoints verify signatures (HMAC or equivalent)
- [ ] SSRF protection on any endpoint that fetches user-provided URLs

## Common Violations

- CORS configured via comma-split env var without validation — fragile and error-prone
- Broad `except Exception` swallowing auth or validation errors, masking security failures
- API keys stored with prefix but full key also logged or returned in error responses
- Rate limiting only on login but not on password reset, registration, or API key creation
- Webhook receivers accepting unsigned payloads "for development convenience"

## Language-Specific Guidance

**Python:**
- Use Pydantic `extra="forbid"` for request validation
- Use SQLAlchemy ORM or parameterized queries — never f-strings in SQL
- Use `subprocess.run(["cmd", "arg"])` — never `shell=True` with user data
- Use `argon2-cffi` or `bcrypt` for password hashing — never SHA/MD5

**TypeScript:**
- Use Zod, Joi, or similar for request body validation
- Use parameterized queries with your ORM (Prisma, Drizzle, Knex)
- Use `helmet` middleware for security headers in Express/Fastify
- Use `DOMPurify` or equivalent for HTML sanitization

**Go:**
- Use `database/sql` with `?` placeholders — never `fmt.Sprintf` for queries
- Use `exec.Command("cmd", "arg1", "arg2")` — never `exec.Command("sh", "-c", userInput)`
- Use `crypto/rand` for tokens — never `math/rand`

## Opt-Out Justification

Security should almost never be disabled. Legitimate exceptions:
- Internal CLI tools with no network exposure and no user input
- Pure data transformation scripts with no I/O boundaries
