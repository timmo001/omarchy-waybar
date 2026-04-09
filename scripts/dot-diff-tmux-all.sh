#!/usr/bin/env bash
# Open ALL repos tracked by dot diff in a tmux session, one window per repo.
# If the session already exists, attach to it instead of recreating.
set -euo pipefail
DOT_BIN="${DOT_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot}"
SESSION="dot"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  uwsm app -- xdg-terminal-exec --app-id=org.omarchy.terminal tmux attach-session -t "$SESSION"
  exit 0
fi

first=1
while IFS='|' read -r name path; do
  [[ -z "$name" || -z "$path" ]] && continue
  win="${name#*:}"
  if [[ $first -eq 1 ]]; then
    tmux new-session -d -s "$SESSION" -n "$win" -c "$path"
    first=0
  else
    tmux new-window -t "$SESSION" -n "$win" -c "$path"
  fi
done < <("$DOT_BIN" diff --list-all)

[[ $first -eq 1 ]] && exit 0

uwsm app -- xdg-terminal-exec --app-id=org.omarchy.terminal tmux attach-session -t "$SESSION"
