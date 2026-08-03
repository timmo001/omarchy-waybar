#!/usr/bin/env bash
# Cached watched-package updates for Waybar.
set -euo pipefail

PACKAGE_FILE="${WAYBAR_PACKAGE_UPDATES_FILE:-$HOME/.config/dotfiles/.dot-public-packages}"
CACHE_DIR="${WAYBAR_PACKAGE_UPDATES_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar}"
CACHE_FILE="$CACHE_DIR/package-updates-waybar.json"
LOCK_DIR="$CACHE_DIR/package-updates-waybar.lock"
YAY_BIN="${WAYBAR_PACKAGE_UPDATES_YAY_BIN:-yay}"
SETSID_BIN="${WAYBAR_PACKAGE_UPDATES_SETSID_BIN:-setsid}"
PKILL_BIN="${WAYBAR_PACKAGE_UPDATES_PKILL_BIN:-pkill}"
REFRESH_SIGNAL="${WAYBAR_PACKAGE_UPDATES_SIGNAL:-12}"
REFRESH_TIMEOUT="${WAYBAR_PACKAGE_UPDATES_TIMEOUT:-120}"

loading_json='{"text":"󰏗 ..","tooltip":"Watched package updates: loading","class":"package-updates-unknown"}'
hidden_json='{"text":"","tooltip":"Watched packages are up to date","class":"hidden"}'
error_json='{"text":" ?","tooltip":"Watched package updates unavailable","class":"package-updates-unknown"}'

mkdir -p "$CACHE_DIR"

signal_waybar_refresh() {
  "$PKILL_BIN" -RTMIN+"$REFRESH_SIGNAL" -x waybar >/dev/null 2>&1 || true
}

refresh_cache() {
  local output_file error_file status output rendered_json tmp_file
  local -a packages=()

  if [[ ! -r "$PACKAGE_FILE" ]]; then
    rendered_json="$error_json"
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*([^[:space:]#]+) ]]; then
        packages+=("${BASH_REMATCH[1]}")
      fi
    done <"$PACKAGE_FILE"

    if ((${#packages[@]} == 0)); then
      rendered_json="$hidden_json"
    else
      output_file="$(mktemp)"
      error_file="$(mktemp)"
      set +e
      timeout "$REFRESH_TIMEOUT" "$YAY_BIN" -Quq -- "${packages[@]}" >"$output_file" 2>"$error_file"
      status=$?
      set -e

      output="$(sort -u "$output_file" | sed '/^[[:space:]]*$/d')"
      if [[ -n "$output" ]]; then
        rendered_json="$(jq -cn --arg updates "$output" '
          ($updates | split("\n")) as $packages
          | {
              text: ("󰏗 " + ($packages | length | tostring)),
              tooltip: ("Watched package updates:\n" + ($packages | join("\n"))),
              class: "package-updates"
            }
        ')"
      elif { ((status == 0 || status == 1)) && [[ ! -s "$error_file" ]]; }; then
        rendered_json="$hidden_json"
      else
        rendered_json="$error_json"
      fi

      rm -f "$output_file" "$error_file"
    fi
  fi

  tmp_file="$CACHE_FILE.tmp"
  printf '%s\n' "$rendered_json" >"$tmp_file"
  mv "$tmp_file" "$CACHE_FILE"
  signal_waybar_refresh
}

case "${1:-status}" in
refresh)
  if [[ "${WAYBAR_PACKAGE_UPDATES_LOCKED:-0}" != "1" ]]; then
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
  refresh_cache
  ;;
status)
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    "$SETSID_BIN" env WAYBAR_PACKAGE_UPDATES_LOCKED=1 "$0" refresh >/dev/null 2>&1 &
  fi

  if [[ -s "$CACHE_FILE" ]]; then
    cat "$CACHE_FILE"
  else
    printf '%s\n' "$loading_json"
  fi
  ;;
*)
  printf 'Usage: %s [status|refresh]\n' "${0##*/}" >&2
  exit 1
  ;;
esac
