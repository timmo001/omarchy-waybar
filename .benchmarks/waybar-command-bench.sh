#!/usr/bin/env bash

set -euo pipefail

RUNS=3
INCLUDE_STREAM=0
OUTPUT_FILE=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'

if [[ -n "${NO_COLOR:-}" ]]; then
  C_RESET=''
  C_BOLD=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_CYAN=''
fi

style_line() {
  local color="$1"
  shift
  printf '%b%s%b\n' "$color" "$*" "$C_RESET"
}

style_section() {
  local label="$1"
  printf '\n%b== %s ==%b\n' "${C_BOLD}${C_BLUE}" "$label" "$C_RESET"
}

style_step() {
  style_line "$C_YELLOW" "$1"
}

usage() {
  cat <<'EOF'
Usage: waybar-command-bench.sh [options]

Options:
  --runs <n>             Runs per command (default: 3)
  --include-stream       Include long-running stream commands
  --output <path>        Output file path
  --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs)
      RUNS="$2"
      shift 2
      ;;
    --include-stream)
      INCLUDE_STREAM=1
      shift
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
      printf 'waybar-command-bench.sh: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$RUNS" =~ ^[0-9]+$ ]] || (( RUNS < 1 )); then
  printf 'waybar-command-bench.sh: --runs must be >= 1\n' >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/waybar-command-bench-$(date +%Y%m%d-%H%M%S).tsv"
else
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

cleanup_waybar_processes() {
  pkill -x waybar >/dev/null 2>&1 || true
  pkill -f '/home/aidan/.config/waybar/scripts/ha-waybar-module.sh' >/dev/null 2>&1 || true
  pkill -f 'ha-watch-singleton --module' >/dev/null 2>&1 || true
  pkill -f 'singleton-stream --key' >/dev/null 2>&1 || true
  pkill -f 'go-automate ha bridge watch entity --waybar' >/dev/null 2>&1 || true
  pkill -f 'go-automate ha watch entity --waybar' >/dev/null 2>&1 || true
  sleep 1
}

restart_waybar() {
  omarchy-restart-waybar >/dev/null 2>&1 || true
}

sample_tree_rss_kb() {
  local root_pid="$1"
  local pids
  local rss_sum=0
  local pid
  local rss

  pids="$(ps -o pid= --ppid "$root_pid" 2>/dev/null || true)"
  pids="$root_pid $pids"

  for pid in $pids; do
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [[ "$rss" =~ ^[0-9]+$ ]]; then
      rss_sum=$((rss_sum + rss))
    fi
  done

  printf '%s' "$rss_sum"
}

run_once() {
  local command="$1"
  local timeout_seconds="$2"
  local start_ns now_ns elapsed_ms
  local timed_out=0
  local peak_rss_kb=0
  local process_pid
  local process_group
  local current_rss
  local returncode=0

  start_ns="$(date +%s%N)"

  bash -lc "$command" >/dev/null 2>&1 &
  process_pid="$!"
  process_group="$process_pid"

  while kill -0 "$process_pid" 2>/dev/null; do
    current_rss="$(sample_tree_rss_kb "$process_pid")"
    if (( current_rss > peak_rss_kb )); then
      peak_rss_kb="$current_rss"
    fi

    now_ns="$(date +%s%N)"
    elapsed_ms=$(((now_ns - start_ns) / 1000000))
    if (( elapsed_ms > timeout_seconds * 1000 )); then
      timed_out=1
      kill -- -"$process_group" >/dev/null 2>&1 || kill "$process_pid" >/dev/null 2>&1 || true
      break
    fi

    sleep 0.005
  done

  if wait "$process_pid" 2>/dev/null; then
    returncode=0
  else
    returncode=$?
  fi

  now_ns="$(date +%s%N)"
  elapsed_ms=$(((now_ns - start_ns) / 1000000))

  printf '%s\t%s\t%s\n' "$elapsed_ms" "$peak_rss_kb" "$timed_out:$returncode"
}

p95_from_sorted_ms() {
  local -n arr_ref="$1"
  local len="${#arr_ref[@]}"
  local idx=$(((95 * (len - 1) + 50) / 100))
  printf '%s' "${arr_ref[$idx]}"
}

format_ms_to_sec() {
  local ms="$1"
  awk -v ms="$ms" 'BEGIN { printf "%.3f", ms / 1000.0 }'
}

declare -a NAMES=()
declare -a CMDS=()
declare -a TIMEOUTS=()
declare -a EXPECTS_TIMEOUT=()

add_command() {
  NAMES+=("$1")
  CMDS+=("$2")
  TIMEOUTS+=("$3")
  EXPECTS_TIMEOUT+=("$4")
}

add_command "dot-diff-waybar" "~/.config/waybar/scripts/dot-diff-waybar.sh" 10 false
add_command "github-workflow-failures-waybar" "~/.config/waybar/scripts/github-workflow-failures-waybar.sh" 10 false
add_command "twitch-notifications status" "twitch-notifications --status-waybar --max-chars 60" 10 false
add_command "ha-waybar-module temperature" "~/.config/waybar/scripts/ha-waybar-module.sh temperature --entity sensor.meter_plus_378b_temperature --name 'Meter Plus Temperature'" 10 false
add_command "ha-waybar-module nas-activity" "~/.config/waybar/scripts/ha-waybar-module.sh nas-activity --entity sensor.nas_activity --name 'NAS Activity' --switch-entity switch.nas --inactive-script-entity script.turn_off_nas_when_inactive" 10 false
add_command "ha-waybar-module current-next-event" "~/.config/waybar/scripts/ha-waybar-module.sh current-next-event --entity input_text.current_next_event_in_an_hour" 10 false
add_command "ha-waybar-module co2-alert" "~/.config/waybar/scripts/ha-waybar-module.sh co2-alert --entity sensor.apollo_air_1_806d64_co2 --name 'Apollo Air 1 CO2'" 10 false
add_command "ha-waybar-module voc-alert" "~/.config/waybar/scripts/ha-waybar-module.sh voc-alert --quality-entity sensor.apollo_air_1_806d64_voc_quality --value-entity sensor.apollo_air_1_806d64_sen55_voc --name 'Apollo Air 1 VOC'" 10 false
add_command "ha-waybar-module doorbell (simulate off)" "~/.config/waybar/scripts/ha-waybar-module.sh doorbell --entity input_boolean.doorbell --simulate off" 10 false
add_command "omarchy-update-available" "omarchy-update-available" 10 false
add_command "omarchy-voxtype-status" "omarchy-voxtype-status" 5 true
add_command "ha-watch-singleton in_a_call" "ha-watch-singleton --module bench.in-a-call --entity input_boolean.in_a_call --class-on active --class-off inactive --hide-off" 5 true
add_command "ha-watch-singleton time_check" "ha-watch-singleton --module bench.time-check --entity input_boolean.time_check --text-on 'Check the time' --class-on active --class-off inactive --hide-off" 5 true
add_command "ha-watch-singleton thermostat_status" "ha-watch-singleton --module bench.heating --entity sensor.thermostat_status" 5 true
add_command "ha-watch-singleton rain_state" "ha-watch-singleton --module bench.rain --entity binary_sensor.weather_station_rain_state_piezo --class-on raining --class-off hidden --hide-off" 5 true

header="COMMAND\tRUNS\tMEDIAN_SEC\tP95_SEC\tMEDIAN_PEAK_RSS_KB\tTIMEOUTS\tNONZERO\tEXPECTS_TIMEOUT"
rows=("$header")

style_line "${C_BOLD}${C_CYAN}" 'Waybar command benchmark'
style_section 'Configuration'
printf 'Runs per command: %s\n' "$RUNS"
printf 'Include stream commands: %s\n' "$INCLUDE_STREAM"

style_section 'Preparation'
style_step 'Stopping Waybar and related watcher/module processes'
cleanup_waybar_processes
style_step 'Restarting Waybar before command benchmark'
restart_waybar
sleep 2

style_section 'Execution'

for i in "${!NAMES[@]}"; do
  if [[ "${EXPECTS_TIMEOUT[$i]}" == "true" && "$INCLUDE_STREAM" != "1" ]]; then
    continue
  fi

  declare -a elapsed_ms_arr=()
  declare -a peak_rss_arr=()
  timeouts=0
  nonzero=0

  for ((run = 1; run <= RUNS; run += 1)); do
    result="$(run_once "${CMDS[$i]}" "${TIMEOUTS[$i]}")"
    elapsed_ms="${result%%$'\t'*}"
    tmp="${result#*$'\t'}"
    peak_rss="${tmp%%$'\t'*}"
    status_pair="${tmp#*$'\t'}"
    timed_out="${status_pair%%:*}"
    rc="${status_pair##*:}"

    elapsed_ms_arr+=("$elapsed_ms")
    peak_rss_arr+=("$peak_rss")

    if (( timed_out > 0 )); then
      timeouts=$((timeouts + 1))
    fi
    if (( rc != 0 )); then
      nonzero=$((nonzero + 1))
    fi
  done

  IFS=$'\n' sorted_ms=($(printf '%s\n' "${elapsed_ms_arr[@]}" | sort -n))
  IFS=$'\n' sorted_rss=($(printf '%s\n' "${peak_rss_arr[@]}" | sort -n))
  unset IFS

  median_idx=$(((RUNS - 1) / 2))
  median_ms="${sorted_ms[$median_idx]}"
  p95_ms="$(p95_from_sorted_ms sorted_ms)"
  median_rss="${sorted_rss[$median_idx]}"

  row="${NAMES[$i]}\t$RUNS\t$(format_ms_to_sec "$median_ms")\t$(format_ms_to_sec "$p95_ms")\t$median_rss\t$timeouts\t$nonzero\t${EXPECTS_TIMEOUT[$i]}"
  rows+=("$row")
done

for row in "${rows[@]}"; do
  printf '%s\n' "$row"
done

printf '%s\n' "${rows[@]}" > "$OUTPUT_FILE"

style_section 'Cleanup'
style_step 'Restarting Waybar after benchmark'

restart_waybar

style_section 'Result'
style_line "$C_GREEN" 'Result: completed command benchmark'

style_section 'Output'
printf 'Output file: %s\n' "$OUTPUT_FILE"
