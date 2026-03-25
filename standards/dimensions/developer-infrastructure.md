# Developer Infrastructure

## Principle

Every quality gate that can be automated must be automated — human discipline does not scale, but CI pipelines and enforced tooling do.

## Criteria

- [ ] CI pipeline runs lint, typecheck, build, and tests on every PR — no manual-only checks
- [ ] CI failures block merge — no bypass without explicit override and justification
- [ ] Lint configuration exists and is enforced (errors fail the build, not just warnings)
- [ ] Type checking enabled with strict mode — no implicit any, no unchecked casts at boundaries
- [ ] Build produces zero errors and minimal warnings (warnings suppressed only with justification)
- [ ] Test suite runs in CI with pass/fail threshold — not just "tests exist"
- [ ] Local dev setup documented and reproducible (README, setup script, or Makefile)
- [ ] Environment variables documented with `.env.example` or equivalent template
- [ ] No hardcoded environment-specific values (URLs, ports, keys) in committed code
- [ ] Dependencies pinned via committed lockfile (`package-lock.json`, `yarn.lock`, `Cargo.lock`, `go.sum`)
- [ ] Deployment process documented or scripted — not tribal knowledge

## Common Violations

- CI pipeline exists but doesn't block merge on failure — PRs merged with red checks
- 100+ lint warnings ignored because "we'll fix them later" — warnings accumulate and mask real issues
- Type checking disabled or set to loose mode to avoid fixing errors — defeats the purpose
- No lockfile committed — `npm install` produces different results per machine and in CI
- README says "run npm start" with no mention of required env vars, database setup, or prerequisites
- Lint config overridden per-file to suppress warnings instead of fixing the underlying issue

## Language-Specific Guidance

**TypeScript:**
- Use `strict: true` in tsconfig.json — not individual strict flags cherry-picked
- ESLint with `@typescript-eslint/recommended` or stricter
- Prettier for formatting (removes style debates from code review)
- Use `npm ci` in CI (deterministic installs from lockfile), `npm install` only locally

**Python:**
- Use `ruff` or `flake8` + `black` for linting and formatting
- Use `mypy --strict` or `pyright` for type checking
- Pin dependencies with `pip-compile` (pip-tools), `poetry.lock`, or `uv.lock`
- Use `pytest` with `--tb=short` in CI for readable failure output

**Go:**
- Use `golangci-lint` with a `.golangci.yml` config — not just `go vet`
- Use `go mod tidy` in CI and fail if `go.sum` changes (ensures committed lockfile is current)
- Use `staticcheck` for additional analysis beyond the standard tools

## Opt-Out Justification

- Throwaway prototypes or spikes explicitly marked as non-production code
- Single-developer projects in early exploration phase (pre-first-user), where the overhead of CI setup exceeds the value
