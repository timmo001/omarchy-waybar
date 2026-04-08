#!/usr/bin/env bash
# Floating terminal: same command as Hypr bind SUPER SHIFT + Q (bindings.conf).
set -euo pipefail
DOT_BIN="${DOT_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot}"
exec uwsm app -- xdg-terminal-exec --app-id=org.omarchy.terminal -e bash -lc "exec $(printf '%q' "$DOT_BIN") diff"
