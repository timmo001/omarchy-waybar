#!/usr/bin/env bash
# Floating terminal in first repo with dot diffs.
set -euo pipefail
DOT_BIN="${DOT_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot}"

status_json="$("$DOT_BIN" diff --waybar)"
target_dir="$HOME/.config/dotfiles"

if [[ "$status_json" != *'"class":"dots-ok"'* ]]; then
  tooltip="${status_json#*\"tooltip\":\"}"
  tooltip="${tooltip%%\",\"class\":\"*}"

  first_segment="$tooltip"
  if [[ "$first_segment" == 'Repositories with changes pending: '* ]]; then
    first_segment="${first_segment#Repositories with changes pending: }"
  elif [[ "$first_segment" == 'dot diff: '* ]]; then
    first_segment="${first_segment#dot diff: }"
  fi
  first_segment="${first_segment%%; *}"
  first_repo="${first_segment%% (*}"

  case "$first_repo" in
    public|dotfiles)
      target_dir="$HOME/.config/dotfiles"
      ;;
    private|dotfiles-private)
      target_dir="$HOME/.config/dotfiles-private"
      ;;
    notes)
      target_dir="$HOME/Documents/notes"
      ;;
    omarchy:*)
      target_dir="$HOME/.config/${first_repo#omarchy:}"
      ;;
  esac
fi

if [[ ! -d "$target_dir" ]]; then
  target_dir="$HOME"
fi

exec uwsm app -- xdg-terminal-exec --app-id=org.omarchy.terminal --dir="$target_dir"
