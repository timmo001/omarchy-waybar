#!/usr/bin/env bash
# Single-line JSON for Waybar — same logic as `dot diff` (see `dot diff --waybar`).
set -euo pipefail

DOT_BIN="${DOT_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
CACHE_FILE="$CACHE_DIR/dot-diff-waybar.json"
LOCK_DIR="$CACHE_DIR/dot-diff-waybar.lock"
REFRESH_SIGNAL="${WAYBAR_DOT_DIFF_SIGNAL:-11}"
REFRESH_TIMEOUT="${WAYBAR_DOT_DIFF_TIMEOUT:-20}"

loading_json='{"text":" ..","tooltip":"dot diff: loading","class":"dots-unknown"}'
error_json='{"text":" ?","tooltip":"dot diff: unavailable","class":"dots-unknown"}'

mkdir -p "$CACHE_DIR"

if [[ "${WAYBAR_DOT_DIFF_REFRESH_DETACHED:-0}" != "1" ]]; then
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    export WAYBAR_DOT_DIFF_REFRESH_DETACHED=1
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

  status_json="$(timeout "$REFRESH_TIMEOUT" "$DOT_BIN" diff --waybar --no-fetch 2>/dev/null || true)"
  if [[ -z "$status_json" ]]; then
    rendered_json="$error_json"
  elif [[ "$status_json" == *'"class":"dots-ok"'* ]]; then
    rendered_json='{"text":" 0","tooltip":"dot diff: all repos clean","class":"dots-ok"}'
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
