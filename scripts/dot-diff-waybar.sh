#!/usr/bin/env bash
# Single-line JSON for Waybar — same logic as `dot diff` (see `dot diff --status`).
set -euo pipefail
DOT_BIN="${DOT_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot}"
exec "$DOT_BIN" diff --status
