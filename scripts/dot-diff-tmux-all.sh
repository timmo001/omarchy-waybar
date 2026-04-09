#!/usr/bin/env bash
# Open ALL repos tracked by dot diff in a tmux session, one window per repo.
# If the session already exists, attach to it instead of recreating.
set -euo pipefail
DOT_BIN="${DOT_BIN:-$HOME/.config/dotfiles/scripts/.local/bin/dot}"
TMUX_BIN="${TMUX_BIN:-/usr/bin/tmux}"
SESSION="dot"
window_names=()
window_paths=()

while IFS='|' read -r name path; do
  if [[ -z "$name" || -z "$path" ]]; then
    continue
  fi

  window_names+=("${name#*:}")
  window_paths+=("$path")
done < <("$DOT_BIN" diff --list-all)

if [[ ${#window_names[@]} -eq 0 ]]; then
  exit 0
fi

if "$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null; then
  clients=()
  if mapfile -t clients < <("$TMUX_BIN" list-clients -t "$SESSION" -F '#{client_tty}' 2>/dev/null) && [[ ${#clients[@]} -gt 0 ]]; then
    uwsm app -- xdg-terminal-exec --app-id=org.omarchy.terminal "$TMUX_BIN" attach-session -t "$SESSION"
    exit 0
  fi

  "$TMUX_BIN" kill-session -t "$SESSION"
fi

first=1
for i in "${!window_names[@]}"; do
  win="${window_names[$i]}"
  path="${window_paths[$i]}"
  if [[ $first -eq 1 ]]; then
    "$TMUX_BIN" new-session -d -s "$SESSION" -n "$win" -c "$path"
    first=0
  else
    "$TMUX_BIN" new-window -t "$SESSION:" -n "$win" -c "$path"
  fi
done

if [[ $first -eq 1 ]]; then
  exit 0
fi

uwsm app -- xdg-terminal-exec --app-id=org.omarchy.terminal "$TMUX_BIN" attach-session -t "$SESSION"
