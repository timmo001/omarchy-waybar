#!/usr/bin/env bash

set -euo pipefail

OUTPUT_FILE=""
EXPECT_STOPPED=0
SAMPLE_ATTEMPTS=8
SAMPLE_DELAY="0.25"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'

if [[ -n "${NO_COLOR:-}" ]]; then
  C_RESET=''
  C_BOLD=''
  C_RED=''
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
Usage: waybar-process-snapshot.sh [options]

Shows currently running Waybar-related processes in a human-friendly format.

Options:
  --expect-stopped       Exit non-zero if Waybar-related processes are running
  --output <path>        Output file path
  --help                 Show this help

Examples:
  waybar-process-snapshot.sh
  waybar-process-snapshot.sh --expect-stopped
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-stopped)
      EXPECT_STOPPED=1
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
      printf 'waybar-process-snapshot.sh: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUTPUT_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/waybar-process-snapshot-$(date +%Y%m%d-%H%M%S).txt"
else
  mkdir -p "$(dirname "$OUTPUT_FILE")"
fi

count_matching() {
  local pattern="$1"
  pgrep -fc -- "$pattern" || true
}

classify_process() {
  local cmd="$1"

  if [[ "$cmd" =~ ^/usr/bin/waybar($|[[:space:]]) ]]; then
    printf 'waybar | bar'
  elif [[ "$cmd" == *'ha-waybar-module.sh'* ]]; then
    printf 'ha-waybar-module | module-script'
  elif [[ "$cmd" == *'singleton-stream --key'* ]]; then
    printf 'singleton-stream | stream-worker'
  elif [[ "$cmd" == *'ha-watch-singleton --module'* ]]; then
    printf 'ha-watch-singleton | launcher'
  elif [[ "$cmd" == go-automate\ ha\ bridge\ watch\ entity\ --waybar* ]]; then
    printf 'bridge-watchers | bridge-watcher'
  elif [[ "$cmd" == go-automate\ ha\ watch\ entity\ --waybar* ]]; then
    printf 'direct-watchers | direct-watcher'
  else
    printf 'other'
  fi
}

collect_counts() {
  local sample=0
  local current=0

  waybar_count=0
  module_count=0
  singleton_count=0
  singleton_wrapper_count=0
  bridge_watcher_count=0
  direct_watcher_count=0

  for ((sample = 1; sample <= SAMPLE_ATTEMPTS; sample += 1)); do
    current="$(count_matching '^/usr/bin/waybar')"
    if (( current > waybar_count )); then
      waybar_count="$current"
    fi

    current="$(count_matching 'ha-waybar-module\.sh')"
    if (( current > module_count )); then
      module_count="$current"
    fi

    current="$(count_matching 'singleton-stream --key')"
    if (( current > singleton_count )); then
      singleton_count="$current"
    fi

    current="$(count_matching 'ha-watch-singleton --module')"
    if (( current > singleton_wrapper_count )); then
      singleton_wrapper_count="$current"
    fi

    current="$(count_matching '^go-automate ha bridge watch entity --waybar')"
    if (( current > bridge_watcher_count )); then
      bridge_watcher_count="$current"
    fi

    current="$(count_matching '^go-automate ha watch entity --waybar')"
    if (( current > direct_watcher_count )); then
      direct_watcher_count="$current"
    fi

    if (( sample < SAMPLE_ATTEMPTS )); then
      sleep "$SAMPLE_DELAY"
    fi
  done
}

list_relevant_processes() {
  local lines=""
  local line=""
  local pid=""
  local cmd=""
  local kind=""

  lines="$(pgrep -af '(^/usr/bin/waybar|ha-waybar-module\.sh|singleton-stream --key|ha-watch-singleton --module|^go-automate ha bridge watch entity --waybar|^go-automate ha watch entity --waybar)' || true)"

  if [[ -z "$lines" ]]; then
    printf '(none)\n'
    return
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    pid="${line%% *}"
    cmd="${line#* }"
    if [[ "$cmd" == pgrep* ]]; then
      continue
    fi
    kind="$(classify_process "$cmd")"
    printf '[%-34s] %s %s\n' "$kind" "$pid" "$cmd"
  done <<< "$lines"
}

main() {
  local waybar_count=0
  local module_count=0
  local singleton_count=0
  local singleton_wrapper_count=0
  local bridge_watcher_count=0
  local direct_watcher_count=0
  local helper_active=0
  local total_active=0

  exec > >(tee "$OUTPUT_FILE") 2>&1

  collect_counts

  total_active=$((
    waybar_count +
    module_count +
    singleton_count +
    singleton_wrapper_count +
    bridge_watcher_count +
    direct_watcher_count
  ))

  helper_active=$((
    module_count +
    singleton_count +
    singleton_wrapper_count +
    bridge_watcher_count +
    direct_watcher_count
  ))

  style_line "${C_BOLD}${C_CYAN}" 'Waybar process snapshot'
  style_section 'Configuration'
  printf 'Generated: %s\n' "$(date -Iseconds)"
  printf 'Sample window: %ss (%s samples)\n' "$(awk -v a="$SAMPLE_ATTEMPTS" -v d="$SAMPLE_DELAY" 'BEGIN { printf "%.2f", a * d }')" "$SAMPLE_ATTEMPTS"

  style_section 'Summary'
  printf -- '- Waybar bar process [waybar]: %s\n' "$waybar_count"
  printf -- '- Module helper scripts [ha-waybar-module]: %s\n' "$module_count"
  printf -- '- Shared stream workers [singleton-stream]: %s\n' "$singleton_count"
  printf -- '- HA bridge watcher children [bridge-watchers]: %s\n' "$bridge_watcher_count"
  printf -- '- Direct watcher children [direct-watchers]: %s\n' "$direct_watcher_count"
  printf -- '- Launcher wrappers [ha-watch-singleton]: %s (usually 0 after exec)\n' "$singleton_wrapper_count"

  style_section 'Process details'
  list_relevant_processes

  if (( EXPECT_STOPPED )); then
    style_section 'Result'
    if (( total_active == 0 )); then
      style_line "${C_BOLD}${C_GREEN}" 'Result: PASS (no Waybar-related processes running)'
    elif (( waybar_count == 0 && helper_active > 0 )); then
      printf '%bResult: FAIL%b (Waybar is stopped but %s helper process(es) are still running)\n' "$C_RED" "$C_RESET" "$helper_active"
      printf 'Tip: kill leftovers with `pkill -f "singleton-stream --key"` and `pkill -f "go-automate ha bridge watch entity --waybar"`.\n'
      style_section 'Output'
      printf 'Output file: %s\n' "$OUTPUT_FILE"
      exit 1
    else
      printf '%bResult: FAIL%b (%s Waybar-related process(es) still running)\n' "$C_RED" "$C_RESET" "$total_active"
      printf 'Tip: run `omarchy-toggle-waybar` or `pkill -x waybar` before this check.\n'
      style_section 'Output'
      printf 'Output file: %s\n' "$OUTPUT_FILE"
      exit 1
    fi
  elif (( waybar_count == 0 && helper_active > 0 )); then
    style_section 'Result'
    printf '%bResult: WARNING%b (Waybar is not running but %s helper process(es) are still running)\n' "$C_YELLOW" "$C_RESET" "$helper_active"
    printf 'Tip: kill leftovers with `pkill -f "singleton-stream --key"` and `pkill -f "go-automate ha bridge watch entity --waybar"`.\n'
    style_section 'Output'
    printf 'Output file: %s\n' "$OUTPUT_FILE"
    exit 1
  else
    style_section 'Result'
    style_line "$C_GREEN" 'Result: snapshot complete'
  fi

  style_section 'Output'
  printf 'Output file: %s\n' "$OUTPUT_FILE"
}

main "$@"
