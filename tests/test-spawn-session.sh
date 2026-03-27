#!/usr/bin/env bash
set -euo pipefail

# Tests for spawn-session.sh cross-platform support.
# Tests the script's testable functions (platform detection, argument building,
# effort mapping) by sourcing the script in test mode.
#
# Usage: bash tests/test-spawn-session.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPAWN_SCRIPT="$REPO_DIR/bin/spawn-session.sh"

PASS=0
FAIL=0
ERRORS=""

# --- Test helpers ---

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS\n  FAIL: $test_name\n    expected: '$expected'\n    actual:   '$actual'"
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS\n  FAIL: $test_name\n    expected to contain: '$needle'\n    actual: '$haystack'"
  fi
}

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS\n  FAIL: $test_name\n    expected NOT to contain: '$needle'\n    actual: '$haystack'"
  fi
}

assert_exit_nonzero() {
  local test_name="$1"
  shift
  local output
  if output=$("$@" 2>&1); then
    FAIL=$((FAIL + 1))
    ERRORS="$ERRORS\n  FAIL: $test_name\n    expected non-zero exit, got 0\n    output: '$output'"
  else
    PASS=$((PASS + 1))
  fi
}

# --- Platform Detection Tests ---

echo "=== Platform Detection ==="

# Test: CLAUDECODE=1 -> detects claude-code
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --detect-platform 2>/dev/null)
assert_eq "CLAUDECODE=1 detects claude-code" "claude-code" "$result"

# Test: CODEX_CI=1 -> detects codex
result=$(CLAUDECODE="" CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --detect-platform 2>/dev/null)
assert_eq "CODEX_CI=1 detects codex" "codex" "$result"

# Test: AUTOBOARD_PLATFORM override
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM=codex bash "$SPAWN_SCRIPT" --detect-platform 2>/dev/null)
assert_eq "AUTOBOARD_PLATFORM=codex overrides env" "codex" "$result"

result=$(CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM=claude-code bash "$SPAWN_SCRIPT" --detect-platform 2>/dev/null)
assert_eq "AUTOBOARD_PLATFORM=claude-code overrides env" "claude-code" "$result"

# Test: Both env vars set -> warns, uses claude-code
output=$(CLAUDECODE=1 CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --detect-platform 2>&1)
assert_contains "Both env vars set: stdout has claude-code" "claude-code" "$output"
assert_contains "Both env vars set: warns on stderr" "WARNING" "$output"

# Test: Neither env var set -> error
assert_exit_nonzero "Neither env var: exits non-zero" \
  env CLAUDECODE="" CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --detect-platform

# Test: Invalid AUTOBOARD_PLATFORM -> error
assert_exit_nonzero "Invalid AUTOBOARD_PLATFORM: exits non-zero" \
  env AUTOBOARD_PLATFORM=invalid bash "$SPAWN_SCRIPT" --detect-platform

# --- Effort Mapping Tests ---

echo "=== Effort Mapping ==="

# Create a temp brief file for argument building tests
TEMP_BRIEF=$(mktemp)
echo "test prompt" > "$TEMP_BRIEF"
trap "rm -f '$TEMP_BRIEF'" EXIT

# Test: --effort max on Codex -> xhigh
result=$(CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model gpt-5.4 --effort max 2>/dev/null)
assert_contains "Codex effort max -> xhigh" "xhigh" "$result"

# Test: --effort max on Claude Code -> max
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model opus --effort max 2>/dev/null)
assert_contains "Claude Code effort max -> max" "--effort max" "$result"

# Test: --effort medium -> omitted on both platforms
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model opus --effort medium 2>/dev/null)
assert_not_contains "Claude Code effort medium -> omitted" "--effort" "$result"

result=$(CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model gpt-5.4 --effort medium 2>/dev/null)
assert_not_contains "Codex effort medium -> omitted" "reasoning_effort" "$result"

# Test: --effort high on Claude Code
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model opus --effort high 2>/dev/null)
assert_contains "Claude Code effort high -> --effort high" "--effort high" "$result"

# Test: --effort high on Codex
result=$(CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model gpt-5.4 --effort high 2>/dev/null)
assert_contains "Codex effort high -> reasoning_effort high" "model_reasoning_effort=\"high\"" "$result"

# Test: --effort invalid -> error
assert_exit_nonzero "Invalid effort: exits non-zero" \
  env CLAUDECODE=1 bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model opus --effort invalid

# --- Argument Construction Tests ---

echo "=== Argument Construction ==="

# Test: Claude Code builds correct args
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model opus --settings /tmp/perms.json 2>/dev/null)
assert_contains "Claude Code: has -p" " -p " "$result"
assert_contains "Claude Code: has --model" "--model claude-opus-4-6" "$result"
assert_contains "Claude Code: has --plugin-dir" "--plugin-dir" "$result"
assert_contains "Claude Code: has stream-json" "--output-format stream-json" "$result"
assert_contains "Claude Code: has --verbose" "--verbose" "$result"
assert_contains "Claude Code: has dontAsk" "--permission-mode dontAsk" "$result"
assert_contains "Claude Code: has --settings" "--settings /tmp/perms.json" "$result"

# Test: Codex builds correct args
result=$(CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model gpt-5.4 2>/dev/null)
assert_contains "Codex: starts with 'codex exec'" "codex exec" "$result"
assert_contains "Codex: has --json" "--json" "$result"
assert_contains "Codex: has -c model" "-c model=\"gpt-5.4\"" "$result"
assert_contains "Codex: has --ask-for-approval never" "--ask-for-approval never" "$result"
assert_contains "Codex: has --sandbox workspace-write" "--sandbox workspace-write" "$result"
assert_not_contains "Codex: no --plugin-dir" "--plugin-dir" "$result"
assert_not_contains "Codex: no --verbose" "--verbose" "$result"

# Test: Codex with --skip-permissions
result=$(CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model gpt-5.4 --skip-permissions 2>/dev/null)
assert_contains "Codex skip-permissions: has --sandbox danger-full-access" "--sandbox danger-full-access" "$result"

# Test: Claude Code with --skip-permissions
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model opus --skip-permissions 2>/dev/null)
assert_contains "Claude Code skip-permissions: has --dangerously-skip-permissions" "--dangerously-skip-permissions" "$result"

# Test: Claude Code model alias mapping
result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model sonnet 2>/dev/null)
assert_contains "Claude Code model alias sonnet" "claude-sonnet-4-6" "$result"

result=$(CLAUDECODE=1 CODEX_CI="" AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model haiku 2>/dev/null)
assert_contains "Claude Code model alias haiku" "claude-haiku-4-5-20251001" "$result"

# Test: Codex passes model IDs through (no alias mapping)
result=$(CLAUDECODE="" CODEX_CI=1 AUTOBOARD_PLATFORM="" bash "$SPAWN_SCRIPT" --dry-run "$TEMP_BRIEF" --model opus 2>/dev/null)
assert_contains "Codex model passthrough: opus as-is" "-c model=\"opus\"" "$result"

# --- Results ---

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo -e "\nFailures:$ERRORS"
  exit 1
else
  echo "All tests passed."
  exit 0
fi
