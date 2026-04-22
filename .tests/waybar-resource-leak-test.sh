#!/usr/bin/env bash

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
OUTPUT_FILE=""

DURATION=180
INTERVAL=5
WARMUP=20

RSS_GROWTH_MB=20
CPU_GROWTH_PCT=10
TCP_CONN_GROWTH=2
COUNT_GROWTH=1

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

declare -a CATEGORIES=(
  "waybar"
  "go-automate bridge serve"
  "go-automate bridge watch"
  "singleton-stream"
  "ha-waybar-module"
)

declare -A SAMPLE_COUNT=()
declare -A SAMPLE_CPU_TENTHS=()
declare -A SAMPLE_RSS_KB=()
declare -A SAMPLE_TCP_CONNS=()
declare -A SAMPLE_TCP_RX=()
declare -A SAMPLE_TCP_TX=()

declare -A FIRST_COUNT=()
declare -A FIRST_CPU_TENTHS=()
declare -A FIRST_RSS_KB=()
declare -A FIRST_TCP_CONNS=()

declare -A FINAL_COUNT=()
declare -A FINAL_CPU_TENTHS=()
declare -A FINAL_RSS_KB=()
declare -A FINAL_TCP_CONNS=()

declare -A MIN_COUNT=()
declare -A MIN_CPU_TENTHS=()
declare -A MIN_RSS_KB=()
declare -A MIN_TCP_CONNS=()

declare -A MAX_COUNT=()
declare -A MAX_CPU_TENTHS=()
declare -A MAX_RSS_KB=()
declare -A MAX_TCP_CONNS=()

declare -a FAIL_MESSAGES=()

usage() {
  cat <<'EOF'
Usage: waybar-resource-leak-test.sh [options]

Options:
  --duration <seconds>         Total sampling duration (default: 180)
  --interval <seconds>         Seconds between samples (default: 5)
  --warmup <seconds>           Startup stabilization time (default: 20)
  --rss-growth-mb <n>          Allowed RSS growth per category in MB (default: 20)
  --cpu-growth-pct <n>         Allowed CPU growth per category in percent (default: 10)
  --tcp-conn-growth <n>        Allowed TCP connection growth per category (default: 2)
  --count-growth <n>           Allowed process count growth per category (default: 1)
  --output <path>              Output file path
  --help                       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --warmup)
      WARMUP="$2"
      shift 2
      ;;
    --rss-growth-mb)
      RSS_GROWTH_MB="$2"
      shift 2
      ;;
    --cpu-growth-pct)
      CPU_GROWTH_PCT="$2"
      shift 2
      ;;
    --tcp-conn-growth)
      TCP_CONN_GROWTH="$2"
      shift 2
      ;;
    --count-growth)
      COUNT_GROWTH="$2"
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
      printf 'waybar-resource-leak-test.sh: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

validate_non_negative_int() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf 'waybar-resource-leak-test.sh: %s must be a non-negative integer\n' "$name" >&2
    exit 1
  fi
}

validate_non_negative_int '--duration' "$DURATION"
validate_non_negative_int '--interval' "$INTERVAL"
validate_non_negative_int '--warmup' "$WARMUP"
validate_non_negative_int '--rss-growth-mb' "$RSS_GROWTH_MB"
validate_non_negative_int '--cpu-growth-pct' "$CPU_GROWTH_PCT"
validate_non_negative_int '--tcp-conn-growth' "$TCP_CONN_GROWTH"
validate_non_negative_int '--count-growth' "$COUNT_GROWTH"

if (( DURATION < 1 )); then
  printf 'waybar-resource-leak-test.sh: --duration must be >= 1\n' >&2
  exit 1
fi

if (( INTERVAL < 1 )); then
  printf 'waybar-resource-leak-test.sh: --interval must be >= 1\n' >&2
  exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/waybar-resource-leak-test-$(date +%Y%m%d-%H%M%S).txt"
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
  pgrep -af '(^/usr/bin/waybar|ha-waybar-module\.sh|singleton-stream --key|ha-watch-singleton --module|go-automate ha bridge serve|go-automate ha bridge watch entity --waybar|go-automate ha watch entity --waybar)' || true
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

print_process_snapshot() {
  local label="$1"

  printf '\n%b== %s ==%b\n' "${C_BOLD}${C_BLUE}" "$label" "$C_RESET"
  printf 'waybar: %s\n' "$(count_waybar)"
  printf 'ha-waybar-module: %s\n' "$(count_waybar_modules)"
  printf 'singleton-stream: %s\n' "$(count_singleton)"
  printf 'bridge-watchers: %s\n' "$(count_watchers)"
  printf 'details:\n'
  list_relevant_processes
}

category_for_cmd() {
  local cmd="$1"

  if [[ "$cmd" =~ (^|/)waybar($|[[:space:]]) ]]; then
    printf 'waybar'
  elif [[ "$cmd" == *'go-automate ha bridge serve'* ]]; then
    printf 'go-automate bridge serve'
  elif [[ "$cmd" == *'singleton-stream --key'* ]]; then
    printf 'singleton-stream'
  elif [[ "$cmd" == *'go-automate ha bridge watch entity --waybar'* ]]; then
    printf 'go-automate bridge watch'
  elif [[ "$cmd" == *'ha-waybar-module.sh'* ]]; then
    printf 'ha-waybar-module'
  else
    printf ''
  fi
}

collect_tcp_pid_stats() {
  ss -tinpH 2>/dev/null | awk '
    function flush_record() {
      if (!record_started) return
      for (i = 1; i <= pid_count; i++) {
        pid = pids[i]
        conns[pid] += 1
        rx[pid] += rec_rx
        tx[pid] += rec_tx
      }
    }
    {
      if ($0 !~ /^\t/) {
        flush_record()
        delete pids
        pid_count = 0
        rec_rx = 0
        rec_tx = 0
        record_started = 1
        line = $0
        while (match(line, /pid=([0-9]+)/, m)) {
          pid_count += 1
          pids[pid_count] = m[1]
          line = substr(line, RSTART + RLENGTH)
        }
      } else {
        if (match($0, /bytes_received:([0-9]+)/, m)) rec_rx = m[1]
        if (match($0, /bytes_sent:([0-9]+)/, m)) rec_tx = m[1]
      }
    }
    END {
      flush_record()
      for (pid in conns) {
        printf "%s\t%s\t%s\t%s\n", pid, conns[pid], rx[pid], tx[pid]
      }
    }
  '
}

sample_categories() {
  local ps_lines=""
  local line=""
  local pid=""
  local ppid=""
  local pcpu=""
  local rss=""
  local cmd=""
  local category=""
  local cpu_tenths=0

  declare -A pid_tcp_conns=()
  declare -A pid_tcp_rx=()
  declare -A pid_tcp_tx=()

  SAMPLE_COUNT=()
  SAMPLE_CPU_TENTHS=()
  SAMPLE_RSS_KB=()
  SAMPLE_TCP_CONNS=()
  SAMPLE_TCP_RX=()
  SAMPLE_TCP_TX=()

  while IFS=$'\t' read -r pid conns rx tx; do
    [[ -n "$pid" ]] || continue
    pid_tcp_conns[$pid]="$conns"
    pid_tcp_rx[$pid]="$rx"
    pid_tcp_tx[$pid]="$tx"
  done < <(collect_tcp_pid_stats)

  ps_lines="$(ps -eo pid=,ppid=,pcpu=,rss=,args= | awk '{pid=$1; ppid=$2; cpu=$3; rss=$4; $1=$2=$3=$4=""; sub(/^ +/, "", $0); printf "%s\t%s\t%s\t%s\t%s\n", pid, ppid, cpu, rss, $0 }')"

  while IFS=$'\t' read -r pid ppid pcpu rss cmd; do
    category="$(category_for_cmd "$cmd")"
    [[ -n "$category" ]] || continue

    cpu_tenths="$(awk -v v="$pcpu" 'BEGIN { printf "%.0f", v * 10.0 }')"

    SAMPLE_COUNT[$category]=$(( ${SAMPLE_COUNT[$category]:-0} + 1 ))
    SAMPLE_CPU_TENTHS[$category]=$(( ${SAMPLE_CPU_TENTHS[$category]:-0} + cpu_tenths ))
    SAMPLE_RSS_KB[$category]=$(( ${SAMPLE_RSS_KB[$category]:-0} + rss ))

    if [[ -n "${pid_tcp_conns[$pid]:-}" ]]; then
      SAMPLE_TCP_CONNS[$category]=$(( ${SAMPLE_TCP_CONNS[$category]:-0} + ${pid_tcp_conns[$pid]} ))
      SAMPLE_TCP_RX[$category]=$(( ${SAMPLE_TCP_RX[$category]:-0} + ${pid_tcp_rx[$pid]} ))
      SAMPLE_TCP_TX[$category]=$(( ${SAMPLE_TCP_TX[$category]:-0} + ${pid_tcp_tx[$pid]} ))
    fi
  done <<< "$ps_lines"
}

format_tenths() {
  local tenths="$1"
  awk -v t="$tenths" 'BEGIN { printf "%.1f", t / 10.0 }'
}

format_kb_to_mb() {
  local kb="$1"
  awk -v v="$kb" 'BEGIN { printf "%.1f", v / 1024.0 }'
}

append_failure() {
  local message="$1"
  FAIL_MESSAGES+=("$message")
}

finalize_case_stats() {
  local category="$1"
  local sample_index="$2"

  local count="${SAMPLE_COUNT[$category]:-0}"
  local cpu_tenths="${SAMPLE_CPU_TENTHS[$category]:-0}"
  local rss_kb="${SAMPLE_RSS_KB[$category]:-0}"
  local tcp_conns="${SAMPLE_TCP_CONNS[$category]:-0}"

  if [[ -z "${FIRST_COUNT[$category]:-}" ]]; then
    FIRST_COUNT[$category]="$count"
    FIRST_CPU_TENTHS[$category]="$cpu_tenths"
    FIRST_RSS_KB[$category]="$rss_kb"
    FIRST_TCP_CONNS[$category]="$tcp_conns"

    MIN_COUNT[$category]="$count"
    MIN_CPU_TENTHS[$category]="$cpu_tenths"
    MIN_RSS_KB[$category]="$rss_kb"
    MIN_TCP_CONNS[$category]="$tcp_conns"

    MAX_COUNT[$category]="$count"
    MAX_CPU_TENTHS[$category]="$cpu_tenths"
    MAX_RSS_KB[$category]="$rss_kb"
    MAX_TCP_CONNS[$category]="$tcp_conns"
  else
    if (( count < MIN_COUNT[$category] )); then
      MIN_COUNT[$category]="$count"
    fi
    if (( cpu_tenths < MIN_CPU_TENTHS[$category] )); then
      MIN_CPU_TENTHS[$category]="$cpu_tenths"
    fi
    if (( rss_kb < MIN_RSS_KB[$category] )); then
      MIN_RSS_KB[$category]="$rss_kb"
    fi
    if (( tcp_conns < MIN_TCP_CONNS[$category] )); then
      MIN_TCP_CONNS[$category]="$tcp_conns"
    fi

    if (( count > MAX_COUNT[$category] )); then
      MAX_COUNT[$category]="$count"
    fi
    if (( cpu_tenths > MAX_CPU_TENTHS[$category] )); then
      MAX_CPU_TENTHS[$category]="$cpu_tenths"
    fi
    if (( rss_kb > MAX_RSS_KB[$category] )); then
      MAX_RSS_KB[$category]="$rss_kb"
    fi
    if (( tcp_conns > MAX_TCP_CONNS[$category] )); then
      MAX_TCP_CONNS[$category]="$tcp_conns"
    fi
  fi

  FINAL_COUNT[$category]="$count"
  FINAL_CPU_TENTHS[$category]="$cpu_tenths"
  FINAL_RSS_KB[$category]="$rss_kb"
  FINAL_TCP_CONNS[$category]="$tcp_conns"
}

run_analysis() {
  local category=""
  local first_count=0
  local first_cpu=0
  local first_rss=0
  local first_conn=0
  local final_count=0
  local final_cpu=0
  local final_rss=0
  local final_conn=0
  local delta_count=0
  local delta_cpu=0
  local delta_rss=0
  local delta_conn=0

  local rss_growth_kb_threshold=$((RSS_GROWTH_MB * 1024))
  local cpu_growth_tenths_threshold=$((CPU_GROWTH_PCT * 10))

  printf '\nAnalysis thresholds:\n'
  printf -- '- count growth > %s\n' "$COUNT_GROWTH"
  printf -- '- RSS growth > %s MB\n' "$RSS_GROWTH_MB"
  printf -- '- CPU growth > %s%%\n' "$CPU_GROWTH_PCT"
  printf -- '- TCP connection growth > %s\n' "$TCP_CONN_GROWTH"

  style_section 'Analysis'
  printf 'Category summary (first -> final, with min/max):\n'

  for category in "${CATEGORIES[@]}"; do
    first_count="${FIRST_COUNT[$category]:-0}"
    first_cpu="${FIRST_CPU_TENTHS[$category]:-0}"
    first_rss="${FIRST_RSS_KB[$category]:-0}"
    first_conn="${FIRST_TCP_CONNS[$category]:-0}"

    final_count="${FINAL_COUNT[$category]:-0}"
    final_cpu="${FINAL_CPU_TENTHS[$category]:-0}"
    final_rss="${FINAL_RSS_KB[$category]:-0}"
    final_conn="${FINAL_TCP_CONNS[$category]:-0}"

    delta_count=$((final_count - first_count))
    delta_cpu=$((final_cpu - first_cpu))
    delta_rss=$((final_rss - first_rss))
    delta_conn=$((final_conn - first_conn))

    printf '\n* %s\n' "$category"
    printf '  count: %s -> %s (min=%s max=%s delta=%s)\n' \
      "$first_count" "$final_count" "${MIN_COUNT[$category]:-0}" "${MAX_COUNT[$category]:-0}" "$delta_count"
    printf '  cpu: %s%% -> %s%% (min=%s%% max=%s%% delta=%s%%)\n' \
      "$(format_tenths "$first_cpu")" \
      "$(format_tenths "$final_cpu")" \
      "$(format_tenths "${MIN_CPU_TENTHS[$category]:-0}")" \
      "$(format_tenths "${MAX_CPU_TENTHS[$category]:-0}")" \
      "$(format_tenths "$delta_cpu")"
    printf '  rss: %s MB -> %s MB (min=%s MB max=%s MB delta=%s MB)\n' \
      "$(format_kb_to_mb "$first_rss")" \
      "$(format_kb_to_mb "$final_rss")" \
      "$(format_kb_to_mb "${MIN_RSS_KB[$category]:-0}")" \
      "$(format_kb_to_mb "${MAX_RSS_KB[$category]:-0}")" \
      "$(format_kb_to_mb "$delta_rss")"
    printf '  tcp-conns: %s -> %s (min=%s max=%s delta=%s)\n' \
      "$first_conn" "$final_conn" "${MIN_TCP_CONNS[$category]:-0}" "${MAX_TCP_CONNS[$category]:-0}" "$delta_conn"

    if (( delta_count > COUNT_GROWTH )); then
      append_failure "$category: process count grew by $delta_count (threshold $COUNT_GROWTH)"
    fi

    if (( delta_rss > rss_growth_kb_threshold )); then
      append_failure "$category: RSS grew by $(format_kb_to_mb "$delta_rss") MB (threshold ${RSS_GROWTH_MB} MB)"
    fi

    if (( delta_cpu > cpu_growth_tenths_threshold )); then
      append_failure "$category: CPU grew by $(format_tenths "$delta_cpu")% (threshold ${CPU_GROWTH_PCT}%)"
    fi

    if (( delta_conn > TCP_CONN_GROWTH )); then
      append_failure "$category: TCP connections grew by $delta_conn (threshold $TCP_CONN_GROWTH)"
    fi
  done
}

main() {
  local total_samples=0
  local warmup_samples=0
  local analysis_start=0
  local sample=0
  local remaining=0

  total_samples=$(((DURATION + INTERVAL - 1) / INTERVAL))
  warmup_samples=$((WARMUP / INTERVAL))
  if (( warmup_samples >= total_samples )); then
    warmup_samples=$((total_samples - 1))
  fi
  analysis_start=$((warmup_samples + 1))

  exec > >(tee "$OUTPUT_FILE") 2>&1

  style_line "${C_BOLD}${C_CYAN}" 'Waybar resource leak test'
  style_section 'Configuration'
  printf 'Runtime dir: %s\n' "$RUNTIME_DIR"
  printf 'Duration: %ss\n' "$DURATION"
  printf 'Interval: %ss\n' "$INTERVAL"
  printf 'Warmup: %ss (analysis starts at sample %s/%s)\n' "$WARMUP" "$analysis_start" "$total_samples"

  style_section 'Preparation'
  style_step 'Stopping all waybar/module/watcher processes'
  cleanup_waybar_processes
  sleep 1

  style_step 'Restarting Waybar'
  restart_waybar
  sleep 2

  print_process_snapshot 'After start'

  style_section 'Execution'
  style_step 'Sampling resources'
  for ((sample = 1; sample <= total_samples; sample += 1)); do
    sample_categories

    if (( sample >= analysis_start )); then
      for category in "${CATEGORIES[@]}"; do
        finalize_case_stats "$category" "$sample"
      done
    fi

    remaining=$((total_samples - sample))
    printf 'sample %02d/%02d: waybar=%s singleton=%s bridge-watch=%s bridge-serve-tcp=%s remaining=%ss\n' \
      "$sample" \
      "$total_samples" \
      "${SAMPLE_COUNT[waybar]:-0}" \
      "${SAMPLE_COUNT[singleton-stream]:-0}" \
      "${SAMPLE_COUNT[go-automate bridge watch]:-0}" \
      "${SAMPLE_TCP_CONNS[go-automate bridge serve]:-0}" \
      "$((remaining * INTERVAL))"

    if (( sample < total_samples )); then
      sleep "$INTERVAL"
    fi
  done

  print_process_snapshot 'Before cleanup'

  run_analysis

  style_section 'Cleanup'
  style_step 'Post-test cleanup and restart'
  cleanup_waybar_processes
  sleep 1
  restart_waybar
  sleep 2
  print_process_snapshot 'After final restart'

  style_section 'Result'
  if (( ${#FAIL_MESSAGES[@]} > 0 )); then
    style_line "${C_BOLD}${C_RED}" 'Result: FAIL'
    printf 'Failures:\n'
    for message in "${FAIL_MESSAGES[@]}"; do
      printf -- '- %s\n' "$message"
    done
    style_section 'Output'
    printf 'Output file: %s\n' "$OUTPUT_FILE"
    exit 1
  fi

  style_line "${C_BOLD}${C_GREEN}" 'Result: PASS'
  printf 'No CPU, RSS, process-count, or TCP-connection growth exceeded thresholds.\n'
  style_section 'Output'
  printf 'Output file: %s\n' "$OUTPUT_FILE"
}

main "$@"
