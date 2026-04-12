#!/usr/bin/env bash
set -euo pipefail

# Codex launcher for spawning autoboard session agents.
# Mirrors the Claude launcher interface so the orchestrator skills can choose
# the current provider's wrapper without changing the product workflow.
#
# Codex CLI does not currently expose Claude-style per-command permission
# manifests. This wrapper therefore uses the closest documented non-interactive
# modes:
# - default: --full-auto with workspace-write sandbox
# - --skip-permissions: --dangerously-bypass-approvals-and-sandbox
#
# Usage: spawn-codex-session.sh <brief-file> --model <model> --cwd <worktree-path>
#        [--effort <low|medium|high|max>] [--skip-permissions]
#        [--standards <file>] [--test-baseline <file>] [--knowledge <file>]
#        [--codesight <file>]

BRIEF_FILE="" MODEL="" CWD="." SKIP_PERMISSIONS=false SETTINGS_FILE=""
STANDARDS_FILE="" TEST_BASELINE_FILE="" KNOWLEDGE_FILE="" CODESIGHT_FILE="" EFFORT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --cwd)   CWD="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --skip-permissions) SKIP_PERMISSIONS=true; shift ;;
    --settings) SETTINGS_FILE="$2"; shift 2 ;;
    --standards) STANDARDS_FILE="$2"; shift 2 ;;
    --test-baseline) TEST_BASELINE_FILE="$2"; shift 2 ;;
    --knowledge) KNOWLEDGE_FILE="$2"; shift 2 ;;
    --codesight) CODESIGHT_FILE="$2"; shift 2 ;;
    *) BRIEF_FILE="$1"; shift ;;
  esac
done

[[ -z "$BRIEF_FILE" ]] && { echo "Usage: spawn-codex-session.sh <brief-file> --model <model> --cwd <path> [--effort <level>] [--skip-permissions]" >&2; exit 1; }
[[ ! -f "$BRIEF_FILE" ]] && { echo "Brief file not found: $BRIEF_FILE" >&2; exit 1; }

case "${MODEL:-opus}" in
  opus) MODEL_ID="gpt-5.4" ;;
  sonnet) MODEL_ID="gpt-5.4-mini" ;;
  haiku) MODEL_ID="gpt-5.3-codex-spark" ;;
  *) MODEL_ID="$MODEL" ;;
esac

EFFORT_CONFIG=""
if [[ -n "$EFFORT" ]]; then
  case "$EFFORT" in
    low) EFFORT_CONFIG="low" ;;
    medium) EFFORT_CONFIG="medium" ;;
    high) EFFORT_CONFIG="high" ;;
    max) EFFORT_CONFIG="xhigh" ;;
    *) echo "ERROR: Invalid effort level '$EFFORT'. Valid: low, medium, high, max" >&2; exit 1 ;;
  esac
fi

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
if [[ -n "$KNOWLEDGE_FILE" && -f "$KNOWLEDGE_FILE" ]]; then
  PROMPT="$PROMPT

## Knowledge from Prior Sessions

$(cat "$KNOWLEDGE_FILE")"
fi
if [[ -n "$CODESIGHT_FILE" && -f "$CODESIGHT_FILE" ]]; then
  PROMPT="$PROMPT

## Codebase Context (codesight)

The following index lists available codebase context articles. Read the articles relevant to your tasks during the Explore phase.

$(cat "$CODESIGHT_FILE")"
fi

CODEX_ARGS=(
  exec -
  --json
  --ephemeral
  --full-auto
  -C "$CWD"
  -m "$MODEL_ID"
)
if [[ -n "$EFFORT_CONFIG" && "$EFFORT_CONFIG" != "medium" ]]; then
  CODEX_ARGS+=(-c "model_reasoning_effort=\"$EFFORT_CONFIG\"")
fi
if [[ "$SKIP_PERMISSIONS" == "true" ]]; then
  CODEX_ARGS=(exec - --json --ephemeral --dangerously-bypass-approvals-and-sandbox -C "$CWD" -m "$MODEL_ID")
  if [[ -n "$EFFORT_CONFIG" && "$EFFORT_CONFIG" != "medium" ]]; then
    CODEX_ARGS+=(-c "model_reasoning_effort=\"$EFFORT_CONFIG\"")
  fi
elif [[ -n "$SETTINGS_FILE" ]]; then
  echo "WARN: Codex launcher does not support Claude-style session settings files yet; ignoring --settings $SETTINGS_FILE and using --full-auto." >&2
fi

PROMPT_FILE="$(mktemp /tmp/autoboard-codex-prompt.XXXXXX)"
trap 'rm -f "$PROMPT_FILE"' EXIT
printf '%s' "$PROMPT" > "$PROMPT_FILE"

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

if command -v perl >/dev/null 2>&1; then
  perl -e 'setpgrp(0,0); exec @ARGV' -- /bin/sh -c '
    prompt_file=$1
    shift
    exec codex "$@" < "$prompt_file"
  ' sh "$PROMPT_FILE" "${CODEX_ARGS[@]}" &
  CODEX_PID=$!
  USE_PGROUP=true
else
  /bin/sh -c '
    prompt_file=$1
    shift
    exec codex "$@" < "$prompt_file"
  ' sh "$PROMPT_FILE" "${CODEX_ARGS[@]}" &
  CODEX_PID=$!
  USE_PGROUP=false
fi

LSTART=$(ps -o lstart= -p "$CODEX_PID" 2>/dev/null)
echo "$CODEX_PID $LSTART" > "$PID_DIR/s-${CODEX_PID}.pid"

cleanup() {
  if [ "$USE_PGROUP" = true ]; then
    kill -- -"$CODEX_PID" 2>/dev/null || true
    sleep 1
    kill -9 -- -"$CODEX_PID" 2>/dev/null || true
  else
    kill_descendants "$CODEX_PID"
    sleep 1
    kill_descendants "$CODEX_PID"
  fi
  rm -f "$PID_DIR/s-${CODEX_PID}.pid" "$PROMPT_FILE"
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' EXIT

wait "$CODEX_PID"
CODEX_EXIT=$?

trap - EXIT
cleanup
exit "$CODEX_EXIT"
