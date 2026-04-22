#!/usr/bin/env bash

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
OUTPUT_FILE=""
SAMPLES=12
INTERVAL=5
STARTUP_DELAY=2
SHUTDOWN_WAIT=6
FAILURES=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

usage() {
  cat <<'EOF'
Usage: ha-watch-singleton-isolation-test.sh [options]

Options:
  --samples <n>          Samples per module case (default: 12)
  --interval <seconds>   Seconds between samples (default: 5)
  --output <path>        Output file path
  --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --samples)
      SAMPLES="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
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
      printf 'ha-watch-singleton-isolation-test.sh: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$SAMPLES" =~ ^[0-9]+$ ]] || (( SAMPLES < 1 )); then
  printf 'ha-watch-singleton-isolation-test.sh: --samples must be >= 1\n' >&2
  exit 1
fi

if [[ ! "$INTERVAL" =~ ^[0-9]+$ ]] || (( INTERVAL < 1 )); then
  printf 'ha-watch-singleton-isolation-test.sh: --interval must be >= 1\n' >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/ha-watch-singleton-isolation-test-$(date +%Y%m%d-%H%M%S).txt"
else
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

regex_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//./\\.}"
  value="${value//+/\\+}"
  value="${value//\*/\\*}"
  value="${value//\?/\\?}"
  value="${value//\[/\\[}"
  value="${value//\]/\\]}"
  value="${value//\(/\\(}"
  value="${value//\)/\\)}"
  value="${value//^/\\^}"
  value="${value//\$/\\$}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

count_matching() {
  local pattern="$1"
  pgrep -fc -- "$pattern" || true
}

list_matching() {
  local pattern="$1"
  pgrep -af -- "$pattern" || true
}

count_child_watchers_for_singleton() {
  local singleton_pattern="$1"
  local singleton_pid=""
  local total=0
  local children=0

  while IFS= read -r singleton_pid; do
    [[ -n "$singleton_pid" ]] || continue
    children="$(pgrep -P "$singleton_pid" -fc '^go-automate ha bridge watch entity --waybar' || true)"
    if [[ "$children" =~ ^[0-9]+$ ]]; then
      total=$((total + children))
    fi
  done < <(pgrep -f -- "$singleton_pattern" || true)

  printf '%s' "$total"
}

list_child_watchers_for_singleton() {
  local singleton_pattern="$1"
  local singleton_pid=""

  while IFS= read -r singleton_pid; do
    [[ -n "$singleton_pid" ]] || continue
    pgrep -P "$singleton_pid" -af '^go-automate ha bridge watch entity --waybar' || true
  done < <(pgrep -f -- "$singleton_pattern" || true)
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
}

restart_waybar() {
  omarchy-restart-waybar >/dev/null 2>&1 || true
}

stop_case_process() {
  local pid="$1"
  local grace=0

  kill -- "-$pid" >/dev/null 2>&1 || kill "$pid" >/dev/null 2>&1 || true

  while kill -0 "$pid" >/dev/null 2>&1; do
    grace=$((grace + 1))
    if (( grace >= 5 )); then
      kill -KILL -- "-$pid" >/dev/null 2>&1 || kill -KILL "$pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 1
  done

  wait "$pid" >/dev/null 2>&1 || true
}

print_case_snapshot() {
  local label="$1"
  local singleton_pattern="$2"

  printf '\n-- %s --\n' "$label"
  printf 'singleton-stream: %s\n' "$(count_matching "$singleton_pattern")"
  printf 'bridge-watchers: %s\n' "$(count_child_watchers_for_singleton "$singleton_pattern")"
  printf 'details:\n'
  list_matching "$singleton_pattern"
  list_child_watchers_for_singleton "$singleton_pattern"
}

run_case() {
  local name="$1"
  local module="$2"
  local entity="$3"
  shift 3

  local key
  local key_re
  local singleton_pattern

  local module_pid=""
  local singleton_count=0
  local watcher_count=0
  local first_singleton=-1
  local first_watcher=-1
  local min_singleton=99999
  local min_watcher=99999
  local max_singleton=0
  local max_watcher=0
  local end_singleton=0
  local end_watcher=0
  local sample=0
  local status="PASS"

  key="ha-watch.${module}.${entity}"
  key_re="$(regex_escape "$key")"

  singleton_pattern="singleton-stream --key ${key_re}"

  printf '\n== Case: %s ==\n' "$name"
  printf 'module: %s\n' "$module"
  printf 'entity: %s\n' "$entity"

  setsid ha-watch-singleton --module "$module" --entity "$entity" "$@" >/dev/null 2>&1 &
  module_pid="$!"

  sleep "$STARTUP_DELAY"
  print_case_snapshot 'After start' "$singleton_pattern"

  for ((sample = 1; sample <= SAMPLES; sample += 1)); do
    singleton_count="$(count_matching "$singleton_pattern")"
    watcher_count="$(count_child_watchers_for_singleton "$singleton_pattern")"

    if (( first_singleton < 0 )); then
      first_singleton="$singleton_count"
    fi
    if (( first_watcher < 0 )); then
      first_watcher="$watcher_count"
    fi

    if (( singleton_count < min_singleton )); then
      min_singleton="$singleton_count"
    fi
    if (( singleton_count > max_singleton )); then
      max_singleton="$singleton_count"
    fi

    if (( watcher_count < min_watcher )); then
      min_watcher="$watcher_count"
    fi
    if (( watcher_count > max_watcher )); then
      max_watcher="$watcher_count"
    fi

    printf 'sample %02d/%02d: singleton=%s bridge-watchers=%s\n' "$sample" "$SAMPLES" "$singleton_count" "$watcher_count"
    sleep "$INTERVAL"
  done

  stop_case_process "$module_pid"

  for ((sample = 1; sample <= SHUTDOWN_WAIT; sample += 1)); do
    end_singleton="$(count_matching "$singleton_pattern")"
    end_watcher="$(count_child_watchers_for_singleton "$singleton_pattern")"
    if (( end_singleton == 0 && end_watcher == 0 )); then
      break
    fi
    sleep 1
  done

  print_case_snapshot 'After stop' "$singleton_pattern"

  if (( first_singleton == 0 )); then
    status="FAIL"
  fi
  if (( max_singleton > 1 || max_watcher > 1 )); then
    status="FAIL"
  fi
  if (( end_singleton != 0 || end_watcher != 0 )); then
    status="FAIL"
  fi

  printf 'summary singleton: first=%s min=%s max=%s end=%s\n' "$first_singleton" "$min_singleton" "$max_singleton" "$end_singleton"
  printf 'summary watchers : first=%s min=%s max=%s end=%s\n' "$first_watcher" "$min_watcher" "$max_watcher" "$end_watcher"
  printf 'result: %s\n' "$status"

  if [[ "$status" != "PASS" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
}

{
  printf 'HA watch singleton isolation test\n'
  printf 'Runtime dir: %s\n' "$RUNTIME_DIR"
  printf 'Samples: %s\n' "$SAMPLES"
  printf 'Interval: %ss\n' "$INTERVAL"

  printf '\nPreparation: stopping all waybar/module/watcher processes\n'
  cleanup_waybar_processes
  sleep 1
  printf 'Preparation: restarting Waybar before isolation cases\n'
  restart_waybar
  sleep 2

  run_case 'Time Check' 'isolation.time-check' 'input_boolean.time_check' \
    --text-on 'Check the time' \
    --class-on active \
    --class-off inactive \
    --hide-off

  run_case 'In A Call' 'isolation.in-a-call' 'input_boolean.in_a_call' \
    --class-on active \
    --class-off inactive \
    --hide-off

  run_case 'Heating' 'isolation.heating' 'sensor.thermostat_status'

  run_case 'Rain' 'isolation.rain' 'binary_sensor.weather_station_rain_state_piezo' \
    --class-on raining \
    --class-off hidden \
    --hide-off

  printf '\nPost-test cleanup and restart\n'
  cleanup_waybar_processes
  sleep 1
  restart_waybar
  sleep 2

  if (( FAILURES > 0 )); then
    printf '\nResult: FAIL (%s failing case(s))\n' "$FAILURES"
    exit 1
  fi

  printf '\nResult: PASS (all cases stable)\n'
} | tee "$OUTPUT_FILE"

printf '\nSaved test output: %s\n' "$OUTPUT_FILE"
