# API Design

## Principle

APIs are contracts — they must be consistent, predictable, and self-documenting through their structure.

## Criteria

- [ ] Consistent response envelope: all endpoints return the same top-level shape (e.g., `{ data, error, meta }`)
- [ ] Appropriate HTTP status codes: 201 for creation, 204 for deletion, 400 for validation errors, 404 for not found, 409 for conflicts
- [ ] Structured error responses with error code, human message, and field-level details for validation errors
- [ ] Pagination on all list endpoints that could return unbounded results
- [ ] Filtering and sorting supported on list endpoints where users need to narrow results
- [ ] Resource naming follows conventions: plural nouns (`/users`), nested resources (`/users/:id/projects`)
- [ ] Versioning strategy defined (URL prefix, header, or content negotiation) — even if only v1 exists
- [ ] Input validation at the API boundary with clear error messages per field
- [ ] Idempotency for mutation endpoints where appropriate (idempotency keys or natural idempotency)
- [ ] Rate limiting with standard headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `Retry-After`)

## Common Violations

- Endpoints returning raw database rows with internal field names exposed to clients
- Mix of 200-for-everything and proper status codes across different endpoints
- List endpoints returning all records with no pagination — works in dev, crashes in production
- Validation errors as a generic 400 with no field-level detail
- Inconsistent naming: `/getUser`, `/users/list`, `/user/:id` in the same API
- No versioning — breaking changes require coordinated client updates
- Error responses with different shapes depending on which middleware/handler caught the error
- Sub-app mounts or middleware workarounds instead of clean route organization

## Language-Specific Guidance

**Python (FastAPI):**
- Use Pydantic response models for consistent serialization
- Use `APIRouter` for route organization — not sub-app mounts
- Use `Depends()` for dependency injection (auth, DB sessions, pagination)
- Use `status` constants, not magic numbers: `status_code=status.HTTP_201_CREATED`

**TypeScript (Express/Fastify):**
- Use a response helper: `res.success(data)`, `res.error(code, message, details)`
- Use route-level validation middleware (Zod, Joi) — not manual parsing in handlers
- Use OpenAPI/Swagger generation from route definitions
- Use error middleware for consistent error response formatting

**Go (stdlib/chi/gin):**
- Use a response struct for consistent JSON shape
- Use middleware for auth, logging, rate limiting — not repeated per handler
- Use `chi.URLParam` or path parameters — not query params for resource identification
- Use `go-playground/validator` for struct validation

## Opt-Out Justification

- Projects with no API layer (CLI tools, libraries, background workers)
- Internal services where the only consumer is another service you control (though consistency still helps)
