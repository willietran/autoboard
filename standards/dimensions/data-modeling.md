# Data Modeling

## Principle

The database schema is the foundation of the application — it must enforce correctness, not just store data.

## Criteria

- [ ] Schema uses appropriate types — enums over magic strings, timestamps with timezones, proper numeric precision
- [ ] Indexes on columns used in WHERE, JOIN, and ORDER BY clauses — no full table scans on common queries
- [ ] Foreign key constraints enforce referential integrity — no orphaned records
- [ ] NOT NULL on columns that should always have values — nullability is intentional, not default
- [ ] Unique constraints on naturally unique fields (email, slug, API key prefix)
- [ ] Migrations are incremental and reversible — not a single monolithic migration file
- [ ] Soft deletes or audit trails for data that shouldn't be permanently destroyed
- [ ] JSONB/JSON columns used only for genuinely flexible data — not as a schema avoidance mechanism
- [ ] Created/updated timestamps on all mutable entities
- [ ] Concurrency handled: optimistic locking (version column) or pessimistic locking (SELECT FOR UPDATE) where needed

## Common Violations

- Single migration file containing the entire schema — impossible to track changes or roll back
- Magic strings (`status = "active"`) instead of database-level enums or check constraints
- No indexes — queries fast on dev data but glacial in production
- Timestamps without timezone info — silent data corruption across time zones
- JSONB columns used to avoid modeling relationships properly
- No foreign keys — "the application enforces integrity" (it won't, consistently)
- Missing unique constraints — duplicate records discovered in production
- No audit trail — "who changed this and when?" is unanswerable

## Language-Specific Guidance

**Python (SQLAlchemy):**
- Use SQLAlchemy 2.0 `Mapped[T]` syntax for typed columns
- Use Alembic for migrations — one migration per schema change
- Use `server_default` for timestamps, not Python-side defaults
- Use `Enum` type for status columns, not `String`

**TypeScript (Prisma/Drizzle):**
- Use Prisma's `@unique`, `@relation`, and `@default` annotations
- Use Drizzle's typed schema builders for type-safe queries
- Generate migrations from schema changes — don't write SQL by hand
- Use `@updatedAt` for automatic timestamp tracking

**Go (sqlc/GORM):**
- Use `sqlc` for type-safe queries generated from SQL
- Define constraints in SQL migrations, not application code
- Use `pgx` for PostgreSQL with proper type mapping
- Use database-level enums with Go enum types

## Opt-Out Justification

- Projects with no persistent data storage
- Applications using only external APIs/services for data (no local database)
- File-based storage (config files, flat files) where database modeling doesn't apply
