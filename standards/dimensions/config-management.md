# Configuration Management

## Principle

Every configurable value has a single, validated source — no magic numbers scattered across the codebase.

## Criteria

- [ ] Centralized config schema that validates all settings at startup — not scattered env var reads
- [ ] All magic numbers (timeouts, limits, thresholds, sizes) defined as named constants in a config module
- [ ] Environment variables validated and typed at application startup — fail fast on missing/invalid config
- [ ] Config layering: defaults → config file → env vars → CLI args (later sources override earlier)
- [ ] Secrets separated from non-secret config — different access patterns, different storage
- [ ] Feature flags and operational tunables changeable without code deployment
- [ ] Config values documented: what each one does, its type, default, and valid range
- [ ] No environment-specific logic in application code — config determines behavior, not `if production`

## Common Violations

- `MAX_TOOL_ROUNDS = 10` hardcoded in source with no override mechanism
- Rate limit `100/min` embedded in middleware, not configurable per-environment
- Cache TTL `86400` as a magic number in application code
- Password minimum length `10` hardcoded in validation logic
- Env vars read with `os.getenv("FOO")` scattered across modules — no centralized access
- Different config patterns in different modules: some use env vars, some use constants, some use config files
- No validation — typo in env var name silently produces `None` at runtime

## Language-Specific Guidance

**Python:**
- Use Pydantic `BaseSettings` for typed, validated config with env var loading
- Define config as a frozen dataclass or Pydantic model — immutable after startup
- Use `python-dotenv` for local dev, but never in production
- Group related settings: `DatabaseConfig`, `AuthConfig`, `RateLimitConfig`

**TypeScript:**
- Use Zod to define and validate config schema at startup
- Use a single `config.ts` that exports typed, validated config objects
- Use `envalid` or similar for env var validation
- Type config as `Readonly<Config>` — no runtime mutations

**Go:**
- Use `envconfig` or `viper` for structured config loading
- Define config as typed structs with validation tags
- Use functional options for optional configuration
- Validate config in `main()` before starting the application

## Opt-Out Justification

- Single-file scripts or CLI tools with 1-2 configurable values where a full config system is overhead
- Libraries that take config as constructor/function arguments (config is the consumer's responsibility)
