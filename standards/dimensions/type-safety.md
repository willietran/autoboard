# Type Safety

## Principle

Use the strongest type system available in your language — escape hatches are violations unless justified in a comment.

## Criteria

- [ ] Strict type checking enabled and passing (TypeScript `strict: true`, Python `mypy --strict`, etc.)
- [ ] No `any`/`Any`/`interface{}` escape hatches without a comment explaining why
- [ ] No `type: ignore` / `@ts-ignore` / `nolint` without a comment explaining what's being suppressed and why
- [ ] Function signatures have explicit parameter and return types — no implicit `any`
- [ ] Domain types used for domain concepts — not raw strings/numbers for IDs, amounts, dates
- [ ] Null/optional values handled explicitly — no runtime null pointer exceptions
- [ ] Exhaustive pattern matching on unions/enums — compiler catches missing cases
- [ ] Generic types used where they add safety — not `any[]` or `List[Any]` for typed collections
- [ ] Runtime validation at system boundaries (API inputs, config, external data) matches declared types
- [ ] Third-party library types properly typed — not bypassed with `any` casts

## Common Violations

- Service layer functions accepting `session: Any, experiment: Any` to avoid importing types
- `# type: ignore` on every Celery/library call instead of writing proper stubs
- `as any` to silence TypeScript errors instead of fixing the actual type mismatch
- Using `string` for everything (user IDs, experiment IDs, API keys) — no domain types
- Pydantic models with `extra="allow"` that accept arbitrary unexpected fields
- Switch/match statements without exhaustiveness checks — new enum values silently fall through

## Language-Specific Guidance

**Python:**
- Enable `mypy --strict` or `pyright strict` in CI
- Use `Mapped[T]` (SQLAlchemy 2.0+) for ORM types
- Use `Pydantic` with `extra="forbid"` for input validation
- Use `typing.NewType` for domain-specific IDs: `UserId = NewType("UserId", str)`
- Use `@overload` for functions with variant return types
- When library typing is poor, write a small stub file — don't scatter `type: ignore`

**TypeScript:**
- Enable `strict: true` in tsconfig — this includes `noImplicitAny`, `strictNullChecks`, etc.
- Use branded types for domain concepts: `type UserId = string & { __brand: "UserId" }`
- Use discriminated unions over type assertions
- Use `satisfies` operator for type-safe object literals
- Use `z.infer<typeof schema>` with Zod to derive types from validation schemas

**Go:**
- Define named types for domain concepts: `type UserID string`
- Use generics (Go 1.18+) for type-safe collections and utilities
- Avoid `interface{}` / `any` — use specific interfaces
- Use exhaustive switch with `default: panic("unhandled case")` for enums

## Opt-Out Justification

- Rapid prototypes where type infrastructure isn't worth the investment
- Scripts that interact primarily with untyped external data (shell scripting, log processing)
- Languages without meaningful type systems (vanilla JS without TypeScript, bash)
