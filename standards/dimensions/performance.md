# Performance

## Principle

Performance is designed in, not optimized later — choose the right algorithm and data access pattern from the start.

## Criteria

- [ ] Algorithms are O(n) or O(n log n) — no quadratic or worse as data grows
- [ ] No N+1 query patterns — batch database queries instead of per-item fetches
- [ ] Long-running operations don't block the event loop or main thread
- [ ] Database queries use appropriate indexes — no full table scans on common operations
- [ ] Bulk operations use batch inserts/updates — not individual row operations in a loop
- [ ] External API calls are batched or parallelized where possible
- [ ] Caching applied at high-traffic, low-change-frequency access points — with explicit invalidation strategy
- [ ] Pagination on all queries that could return unbounded result sets
- [ ] File uploads and large data processing use streaming — not loading everything into memory

## Common Violations

- Nested loops that produce O(n²) behavior on collections that grow with usage
- Loading all records then filtering in application code instead of using database WHERE clauses
- Per-item API calls in a loop instead of batch endpoints
- No pagination — SELECT * FROM large_table returned to the client
- Synchronous file processing blocking request handlers
- Cache with no invalidation — stale data served indefinitely
- String concatenation in a loop instead of using a builder/buffer

## Language-Specific Guidance

**Python:**
- Use `asyncio` for I/O-bound parallelism, `concurrent.futures` for CPU-bound
- Use SQLAlchemy's `selectinload` or `joinedload` to prevent N+1 queries
- Use `itertools` and generators for memory-efficient processing of large datasets
- Use `COPY` or `executemany` for bulk database inserts

**TypeScript:**
- Use `Promise.all()` for parallel independent async operations
- Use database query builders with `.include()` or `.join()` to prevent N+1
- Use streams (`ReadableStream`, Node streams) for large file processing
- Use `DataLoader` pattern for batching in GraphQL

**Go:**
- Use goroutines with `errgroup` for concurrent operations
- Use `pgx.CopyFrom` for bulk PostgreSQL inserts
- Use `io.Reader`/`io.Writer` interfaces for streaming — don't buffer entire files
- Use `sync.Pool` for frequently allocated objects

## Opt-Out Justification

- Projects where data volumes are inherently small and bounded (< 1000 records)
- Internal tools with known, limited user counts where performance isn't a concern
