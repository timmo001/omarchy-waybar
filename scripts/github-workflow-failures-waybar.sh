#!/usr/bin/env bash
# Single-line JSON for Waybar - failed GitHub workflow runs tracked by git-workflow-watch.
set -euo pipefail

WATCH_BIN="${DOT_WORKFLOW_WATCH_BIN:-$HOME/.local/bin/git-workflow-watch}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
CACHE_FILE="$CACHE_DIR/github-workflow-failures-waybar.json"
LOCK_DIR="$CACHE_DIR/github-workflow-failures-waybar.lock"
REFRESH_SIGNAL="${WAYBAR_WORKFLOW_FAILURES_SIGNAL:-12}"
REFRESH_TIMEOUT="${WAYBAR_WORKFLOW_FAILURES_TIMEOUT:-20}"

loading_json='{"text":" ..","tooltip":"GitHub workflow failures: loading","class":"workflow-failures-unknown"}'
error_json='{"text":" ?","tooltip":"GitHub workflow failures: unavailable","class":"workflow-failures-unknown"}'

mkdir -p "$CACHE_DIR"

if [[ "${WAYBAR_WORKFLOW_FAILURES_REFRESH_DETACHED:-0}" != "1" ]]; then
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    export WAYBAR_WORKFLOW_FAILURES_REFRESH_DETACHED=1
    setsid "$0" "$@" >/dev/null 2>&1 &
  fi

  if [[ -s "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE"
  else
    printf '%s\n' "$loading_json"
  fi
  exit 0
fi

refresh_cache() {
  local status_json rendered_json tmp_file

  status_json="$(timeout "$REFRESH_TIMEOUT" "$WATCH_BIN" waybar-status 2>/dev/null || true)"
  if [[ -z "$status_json" ]]; then
    rendered_json="$error_json"
  else
    rendered_json="$status_json"
  fi

  tmp_file="$CACHE_FILE.tmp"
  printf '%s\n' "$rendered_json" > "$tmp_file"
  mv "$tmp_file" "$CACHE_FILE"
  pkill -RTMIN+${REFRESH_SIGNAL} waybar >/dev/null 2>&1 || true
}

trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
refresh_cache
