#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper around claude -p for spawning autoboard session agents.
# Sessions run with scoped permissions (dontAsk mode + allow/deny rules)
# unless --skip-permissions is passed (falls back to --dangerously-skip-permissions).
#
# Process lifecycle: Launches claude in its own process group (via perl setpgrp)
# so that on exit — normal, signal, or crash — the wrapper can atomically kill
# the entire group (claude + MCP servers + dev servers). Writes a PID file with
# start time for the orchestrator's stale-process reaper.
#
# Usage: spawn-session.sh <brief-file> --model <model> --cwd <worktree-path> [--skip-permissions]
#        [--standards <file>] [--test-baseline <file>]

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

BRIEF_FILE="" MODEL="" CWD="." SKIP_PERMISSIONS=false SETTINGS_FILE=""
STANDARDS_FILE="" TEST_BASELINE_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --cwd)   CWD="$2";   shift 2 ;;
    --skip-permissions) SKIP_PERMISSIONS=true; shift ;;
    --settings) SETTINGS_FILE="$2"; shift 2 ;;
    --standards) STANDARDS_FILE="$2"; shift 2 ;;
    --test-baseline) TEST_BASELINE_FILE="$2"; shift 2 ;;
    *)       BRIEF_FILE="$1"; shift ;;
  esac
done

[[ -z "$BRIEF_FILE" ]] && { echo "Usage: spawn-session.sh <brief-file> --model <model> --cwd <path> [--skip-permissions]" >&2; exit 1; }
[[ ! -f "$BRIEF_FILE" ]] && { echo "Brief file not found: $BRIEF_FILE" >&2; exit 1; }

# Map model aliases to full model IDs
case "${MODEL:-opus}" in
  opus)   MODEL_ID="claude-opus-4-6" ;;
  sonnet) MODEL_ID="claude-sonnet-4-6" ;;
  haiku)  MODEL_ID="claude-haiku-4-5-20251001" ;;
  *)      MODEL_ID="$MODEL" ;;
esac

# Build prompt: brief + mechanically appended standards/baseline files
# These files are appended here (not by the orchestrator) to prevent LLM summarization
PROMPT="$(cat "$BRIEF_FILE")"
if [[ -n "$STANDARDS_FILE" && -f "$STANDARDS_FILE" ]]; then
  PROMPT="$PROMPT

## Quality Standards

$(cat "$STANDARDS_FILE")"
fi
if [[ -n "$TEST_BASELINE_FILE" && -f "$TEST_BASELINE_FILE" ]]; then
  PROMPT="$PROMPT

## Test Baseline

$(cat "$TEST_BASELINE_FILE")"
fi

# Build argument array (no string interpolation into shell commands)
ARGS=(
  -p "$PROMPT"
  --model "$MODEL_ID"
  --plugin-dir "$PLUGIN_DIR"
  --output-format stream-json
  --verbose
)
if [[ "$SKIP_PERMISSIONS" == "true" ]]; then
  ARGS+=(--dangerously-skip-permissions)
elif [[ -n "$SETTINGS_FILE" ]]; then
  ARGS+=(--permission-mode dontAsk --settings "$SETTINGS_FILE")
fi

cd "$CWD"

# --- Process lifecycle management ---
#
# Why this matters: Each claude -p session spawns MCP servers (via npx), dev
# servers, and subagents — all node processes. Without cleanup, they become
# orphans when the session ends, accumulating across runs until the system melts.
#
# Approach: Launch claude in its own process group so `kill -- -$PID` atomically
# kills the entire tree. Perl's setpgrp is used because:
#   - set -m doesn't work in background processes (tested on macOS)
#   - setsid isn't available on macOS
#   - PPID recursion (pgrep -P) fails on normal exit (children re-parent to PID 1)
#   - Perl ships with macOS (/usr/bin/perl) and every major Linux distro

# Fallback: recursive PPID-tree kill (handles signal case but not normal exit)
kill_descendants() {
  local pid=$1
  local children
  children=$(pgrep -P "$pid" 2>/dev/null) || true
  for child in $children; do
    kill_descendants "$child"
  done
  kill "$pid" 2>/dev/null || true
}

PID_DIR="/tmp/autoboard-pids"
mkdir -p "$PID_DIR"

# Launch claude in its own process group
if command -v perl >/dev/null 2>&1; then
  perl -e 'setpgrp(0,0); exec @ARGV' -- claude "${ARGS[@]}" &
  CLAUDE_PID=$!
  USE_PGROUP=true
else
  claude "${ARGS[@]}" &
  CLAUDE_PID=$!
  USE_PGROUP=false
fi

# Record PID + start time for stale-process reaper (prevents PID reuse kills)
LSTART=$(ps -o lstart= -p "$CLAUDE_PID" 2>/dev/null)
echo "$CLAUDE_PID $LSTART" > "$PID_DIR/s-${CLAUDE_PID}.pid"

cleanup() {
  if [ "$USE_PGROUP" = true ]; then
    # TERM the entire process group
    kill -- -"$CLAUDE_PID" 2>/dev/null || true
    sleep 1
    # KILL any survivors
    kill -9 -- -"$CLAUDE_PID" 2>/dev/null || true
  else
    # Fallback: recursive PPID-tree kill (TERM pass)
    kill_descendants "$CLAUDE_PID"
    sleep 1
    # Second pass for stubborn processes
    kill_descendants "$CLAUDE_PID"
  fi
  rm -f "$PID_DIR/s-${CLAUDE_PID}.pid"
}

# Signal traps: clean up then exit with standard signal codes
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
# EXIT trap: safety net for normal exit path
trap 'cleanup' EXIT

wait "$CLAUDE_PID"
CLAUDE_EXIT=$?

# Normal exit: disable EXIT trap to avoid double-cleanup, clean up explicitly
trap - EXIT
cleanup
exit "$CLAUDE_EXIT"
