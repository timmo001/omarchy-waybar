#!/usr/bin/env bash
# Single-line JSON for Waybar — same logic as `dot diff` (see `dot diff --waybar`).
set -euo pipefail
DOT_BIN="${DOT_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot}"

status_json="$("$DOT_BIN" diff --waybar)"

if [[ "$status_json" == *'"class":"dots-ok"'* ]]; then
  printf '{"text":" 0","tooltip":"dot diff: all repos clean","class":"dots-ok"}\n'
else
  printf '%s\n' "$status_json"
fi
