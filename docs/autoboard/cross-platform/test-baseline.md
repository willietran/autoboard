# Test Baseline

No baseline — `tests/` directory does not yet exist (created by T1). `shellcheck` is not installed.

Pre-existing state:
- `shellcheck`: not found on PATH. Session S1 should note this and either install it or adjust the verify command.
- `tests/test-spawn-session.sh`: does not exist yet (T1 creates it)
- `bin/spawn-session.sh`: exists, current version passes no tests (no test file)
