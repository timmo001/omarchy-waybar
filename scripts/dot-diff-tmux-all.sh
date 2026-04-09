#!/usr/bin/env bash
set -euo pipefail

HELPER_BIN="${HELPER_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot-diff-tmux-session}"

exec "$HELPER_BIN" all
