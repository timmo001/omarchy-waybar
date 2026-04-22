#!/usr/bin/env bash

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
OUTPUT_FILE=""
CYCLES=3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

usage() {
  cat <<'EOF'
Usage: waybar-leak-test.sh [options]

Options:
  --cycles <n>           Restart cycles to run (default: 3)
  --output <path>        Output file path
  --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cycles)
      CYCLES="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'waybar-leak-test.sh: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$CYCLES" =~ ^[0-9]+$ ]] || (( CYCLES < 1 )); then
  printf 'waybar-leak-test.sh: --cycles must be >= 1\n' >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/waybar-leak-test-$(date +%Y%m%d-%H%M%S).txt"
else
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

count_waybar() {
  pgrep -fc '^/usr/bin/waybar' || true
}

count_watchers() {
  pgrep -fc '^go-automate ha bridge watch entity --waybar' || true
}

count_singleton() {
  pgrep -fc 'singleton-stream --key' || true
}

count_waybar_modules() {
  pgrep -fc 'ha-waybar-module\.sh' || true
}

list_relevant_processes() {
  pgrep -af '(^/usr/bin/waybar|ha-waybar-module\.sh|singleton-stream --key|ha-watch-singleton --module|go-automate ha bridge watch entity --waybar|go-automate ha watch entity --waybar)' || true
}

cleanup_waybar_processes() {
  pkill -x waybar >/dev/null 2>&1 || true
  pkill -f '/home/aidan/.config/waybar/scripts/ha-waybar-module.sh' >/dev/null 2>&1 || true
  pkill -f 'ha-watch-singleton --module' >/dev/null 2>&1 || true
  pkill -f 'singleton-stream --key' >/dev/null 2>&1 || true
  pkill -f 'go-automate ha bridge watch entity --waybar' >/dev/null 2>&1 || true
  pkill -f 'go-automate ha watch entity --waybar' >/dev/null 2>&1 || true

  rm -f "$RUNTIME_DIR"/singleton-stream-*.lock >/dev/null 2>&1 || true
  rm -f "$RUNTIME_DIR"/singleton-stream-*.state >/dev/null 2>&1 || true
  rm -f "$RUNTIME_DIR"/singleton-stream-*.lock.owner >/dev/null 2>&1 || true
  rm -f "$RUNTIME_DIR"/ha-waybar-trigger-*.state >/dev/null 2>&1 || true
  rm -f "$RUNTIME_DIR"/ha-waybar-trigger-*.last >/dev/null 2>&1 || true
}

restart_waybar() {
  omarchy-restart-waybar >/dev/null 2>&1 || true
}

print_snapshot() {
  local label="$1"

  printf '\n== %s ==\n' "$label"
  printf 'waybar: %s\n' "$(count_waybar)"
  printf 'ha-waybar-module: %s\n' "$(count_waybar_modules)"
  printf 'singleton-stream: %s\n' "$(count_singleton)"
  printf 'bridge-watchers: %s\n' "$(count_watchers)"
  printf 'details:\n'
  list_relevant_processes
}

{
  printf 'Waybar full leak test\n'
  printf 'Runtime dir: %s\n' "$RUNTIME_DIR"
  printf 'Restart cycles: %s\n' "$CYCLES"

  printf '\nPreparation: stopping all waybar/module/watcher processes\n'
  cleanup_waybar_processes
  sleep 1
  print_snapshot 'After cleanup'

  printf '\nStarting Waybar\n'
  restart_waybar
  sleep 2
  print_snapshot 'After first start'

  printf '\nRestarting Waybar (%s cycles)\n' "$CYCLES"
  for ((i = 1; i <= CYCLES; i += 1)); do
    printf '  cycle %s/%s\n' "$i" "$CYCLES"
    restart_waybar
    sleep 1
  done
  print_snapshot 'After restart cycles'

  printf '\nToggling Waybar off\n'
  omarchy-toggle-waybar
  sleep 2
  print_snapshot 'After toggle off'

  printf '\nToggling Waybar on\n'
  omarchy-toggle-waybar
  sleep 2
  print_snapshot 'After toggle on'

  printf '\nPost-test cleanup and restart\n'
  cleanup_waybar_processes
  sleep 1
  restart_waybar
  sleep 2
  print_snapshot 'After final restart'

  printf '\nResult: completed full leak test sequence\n'
} | tee "$OUTPUT_FILE"

printf '\nSaved test output: %s\n' "$OUTPUT_FILE"
