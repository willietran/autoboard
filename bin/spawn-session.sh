#!/usr/bin/env bash
set -euo pipefail

# Cross-platform wrapper for spawning autoboard session agents.
# Detects the platform (Claude Code or Codex) and invokes the appropriate CLI.
#
# Sessions run with scoped permissions unless --skip-permissions is passed.
#
# Process lifecycle: Launches the CLI in its own process group (via perl setpgrp)
# so that on exit — normal, signal, or crash — the wrapper can atomically kill
# the entire group (CLI + MCP servers + dev servers). Writes a PID file with
# start time for the orchestrator's stale-process reaper.
#
# Usage: spawn-session.sh <brief-file> --model <model> --cwd <worktree-path>
#        [--effort <low|medium|high|max>] [--skip-permissions]
#        [--settings <file>] [--standards <file>] [--test-baseline <file>]
#        spawn-session.sh --detect-platform

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- Platform detection ---

detect_platform() {
  # Explicit override — validate against allowlist
  if [ -n "${AUTOBOARD_PLATFORM:-}" ]; then
    case "$AUTOBOARD_PLATFORM" in
      claude-code|codex) echo "$AUTOBOARD_PLATFORM" ;;
      *) echo "ERROR: Invalid AUTOBOARD_PLATFORM='$AUTOBOARD_PLATFORM'. Valid: claude-code, codex" >&2; exit 1 ;;
    esac
  elif [ "${CLAUDECODE:-}" = "1" ] && [ -n "${CODEX_CI:-}" ]; then
    echo "WARNING: Both CLAUDECODE and CODEX_CI set. Using claude-code. Override with AUTOBOARD_PLATFORM." >&2
    echo "claude-code"
  elif [ "${CLAUDECODE:-}" = "1" ]; then
    echo "claude-code"
  elif [ -n "${CODEX_CI:-}" ]; then
    echo "codex"
  else
    echo "ERROR: Not running inside a supported CLI. Expected CLAUDECODE=1 or CODEX_CI=1. Override with AUTOBOARD_PLATFORM=claude-code|codex" >&2
    exit 1
  fi
}

# Handle --detect-platform: print platform and exit
if [[ "${1:-}" == "--detect-platform" ]]; then
  detect_platform
  exit 0
fi

# Handle --dry-run: build args and print them instead of executing
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

# --- Argument parsing ---

BRIEF_FILE="" MODEL="" CWD="." SKIP_PERMISSIONS=false SETTINGS_FILE=""
STANDARDS_FILE="" TEST_BASELINE_FILE="" EFFORT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --cwd)   CWD="$2";   shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --skip-permissions) SKIP_PERMISSIONS=true; shift ;;
    --settings) SETTINGS_FILE="$2"; shift 2 ;;
    --standards) STANDARDS_FILE="$2"; shift 2 ;;
    --test-baseline) TEST_BASELINE_FILE="$2"; shift 2 ;;
    *)       BRIEF_FILE="$1"; shift ;;
  esac
done

[[ -z "$BRIEF_FILE" ]] && { echo "Usage: spawn-session.sh <brief-file> --model <model> --cwd <path> [--effort <level>] [--skip-permissions]" >&2; exit 1; }
[[ ! -f "$BRIEF_FILE" ]] && { echo "Brief file not found: $BRIEF_FILE" >&2; exit 1; }

# Validate effort level
if [[ -n "$EFFORT" ]]; then
  case "$EFFORT" in
    low|medium|high|max) ;; # valid
    *) echo "ERROR: Invalid effort level '$EFFORT'. Valid: low, medium, high, max" >&2; exit 1 ;;
  esac
fi

# --- Platform-specific configuration ---

PLATFORM=$(detect_platform)

# Map model aliases to full model IDs (Claude Code only)
resolve_model_id() {
  local model="${1:-opus}"
  if [[ "$PLATFORM" == "claude-code" ]]; then
    case "$model" in
      opus)   echo "claude-opus-4-6" ;;
      sonnet) echo "claude-sonnet-4-6" ;;
      haiku)  echo "claude-haiku-4-5-20251001" ;;
      *)      echo "$model" ;;
    esac
  else
    # Codex: pass model IDs through directly
    echo "$model"
  fi
}

MODEL_ID=$(resolve_model_id "${MODEL:-opus}")

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

# --- Build platform-specific argument arrays ---

build_claude_code_args() {
  ARGS=(
    -p "$PROMPT"
    --model "$MODEL_ID"
    --plugin-dir "$PLUGIN_DIR"
    --output-format stream-json
    --verbose
  )
  # Effort: omit for medium (default), pass for others
  if [[ -n "$EFFORT" && "$EFFORT" != "medium" ]]; then
    ARGS+=(--effort "$EFFORT")
  fi
  # Permissions
  if [[ "$SKIP_PERMISSIONS" == "true" ]]; then
    ARGS+=(--dangerously-skip-permissions)
  elif [[ -n "$SETTINGS_FILE" ]]; then
    ARGS+=(--permission-mode dontAsk --settings "$SETTINGS_FILE")
  fi
  CLI_BIN="claude"
}

build_codex_args() {
  # Map effort: max -> xhigh for Codex
  local codex_effort="$EFFORT"
  if [[ "$codex_effort" == "max" ]]; then
    codex_effort="xhigh"
  fi

  if [[ "$SKIP_PERMISSIONS" == "true" ]]; then
    ARGS=(--dangerously-bypass-approvals-and-sandbox)
  else
    ARGS=(
      --ask-for-approval never
      --sandbox workspace-write
    )
  fi
  ARGS+=(
    exec "$PROMPT"
    --json
    -m "$MODEL_ID"
  )
  # Effort: omit for medium (default), pass for others
  if [[ -n "$codex_effort" && "$codex_effort" != "medium" ]]; then
    ARGS+=(-c "model_reasoning_effort=\"$codex_effort\"")
  fi
  CLI_BIN="codex"
}

CLI_BIN=""
ARGS=()

if [[ "$PLATFORM" == "claude-code" ]]; then
  build_claude_code_args
else
  build_codex_args
fi

# --- Dry run mode: print command and exit ---

if [[ "$DRY_RUN" == "true" ]]; then
  echo "$CLI_BIN ${ARGS[*]}"
  exit 0
fi

cd "$CWD"

# --- Process lifecycle management ---
#
# Why this matters: Each session spawns MCP servers (via npx), dev servers,
# and subagents — all node processes. Without cleanup, they become orphans
# when the session ends, accumulating across runs until the system melts.
#
# Approach: Launch the CLI in its own process group so `kill -- -$PID`
# atomically kills the entire tree. Perl's setpgrp is used because:
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

# Launch CLI in its own process group
if command -v perl >/dev/null 2>&1; then
  perl -e 'setpgrp(0,0); exec @ARGV' -- "$CLI_BIN" "${ARGS[@]}" &
  SESSION_PID=$!
  USE_PGROUP=true
else
  "$CLI_BIN" "${ARGS[@]}" &
  SESSION_PID=$!
  USE_PGROUP=false
fi

# Record PID + start time for stale-process reaper (prevents PID reuse kills)
LSTART=$(ps -o lstart= -p "$SESSION_PID" 2>/dev/null)
echo "$SESSION_PID $LSTART" > "$PID_DIR/s-${SESSION_PID}.pid"

cleanup() {
  if [ "$USE_PGROUP" = true ]; then
    # TERM the entire process group
    kill -- -"$SESSION_PID" 2>/dev/null || true
    sleep 1
    # KILL any survivors
    kill -9 -- -"$SESSION_PID" 2>/dev/null || true
  else
    # Fallback: recursive PPID-tree kill (TERM pass)
    kill_descendants "$SESSION_PID"
    sleep 1
    # Second pass for stubborn processes
    kill_descendants "$SESSION_PID"
  fi
  rm -f "$PID_DIR/s-${SESSION_PID}.pid"
}

# Signal traps: clean up then exit with standard signal codes
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
# EXIT trap: safety net for normal exit path
trap 'cleanup' EXIT

wait "$SESSION_PID"
SESSION_EXIT=$?

# Normal exit: disable EXIT trap to avoid double-cleanup, clean up explicitly
trap - EXIT
cleanup
exit "$SESSION_EXIT"
