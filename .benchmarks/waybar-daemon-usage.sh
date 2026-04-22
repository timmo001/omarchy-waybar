#!/usr/bin/env bash

set -euo pipefail

sample_seconds=3
growth_seconds=0
output_file=""
reset_environment=0

usage() {
  cat <<'EOF'
Usage: waybar-daemon-usage.sh [--sample SECONDS] [--growth SECONDS] [--output PATH] [--reset]

  --sample, -s  CPU sample window in seconds (default: 3)
  --growth, -g  Optional watcher growth window in seconds (default: 0)
  --output, -o  Output file path (default: .benchmarks/output timestamped file)
  --reset       Kill/restart Waybar stack before/after measurement
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--sample)
      sample_seconds="$2"
      shift 2
      ;;
    -g|--growth)
      growth_seconds="$2"
      shift 2
      ;;
    -o|--output)
      output_file="$2"
      shift 2
      ;;
    --reset)
      reset_environment=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$output_file" ]]; then
  mkdir -p "$script_dir/output"
  output_file="$script_dir/output/waybar-daemon-usage-$(date +%Y%m%d-%H%M%S).txt"
else
  mkdir -p "$(dirname "$output_file")"
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

count_watchers() {
  pgrep -fc '^go-automate ha bridge watch entity --waybar' || true
}

category_for_cmd() {
  local cmd="$1"

  if [[ "$cmd" =~ (^|/)waybar($|[[:space:]]) ]]; then
    printf 'waybar'
  elif [[ "$cmd" == *"go-automate ha bridge serve"* ]]; then
    printf 'go-automate bridge serve'
  elif [[ "$cmd" == *"go-automate ha bridge watch entity --waybar"* ]]; then
    printf 'go-automate bridge watch'
  elif [[ "$cmd" == *"go-automate ha watch entity --waybar"* ]]; then
    printf 'go-automate watch'
  elif [[ "$cmd" == *"ha-watch-singleton"* ]]; then
    printf 'ha-watch-singleton'
  elif [[ "$cmd" == *"singleton-stream --key"* ]]; then
    printf 'singleton-stream'
  elif [[ "$cmd" == *"twitch-notifications"* ]]; then
    printf 'twitch-notifications'
  elif [[ "$cmd" == *"omarchy-voxtype-status"* ]]; then
    printf 'omarchy-voxtype-status'
  elif [[ "$cmd" == *"dot-diff-waybar.sh"* ]]; then
    printf 'dot-diff-waybar'
  elif [[ "$cmd" == *"github-workflow-failures-waybar.sh"* ]]; then
    printf 'github-workflow-failures-waybar'
  elif [[ "$cmd" == *"ha-waybar-module.sh"* ]]; then
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

format_tenths() {
  local tenths="$1"
  awk -v t="$tenths" 'BEGIN { printf "%.1f", t / 10.0 }'
}

format_rss_kb_to_mb() {
  local kb="$1"
  awk -v v="$kb" 'BEGIN { printf "%.1f", v / 1024.0 }'
}

format_bytes_to_mb() {
  local bytes="$1"
  awk -v v="$bytes" 'BEGIN { printf "%.1f", v / 1024.0 / 1024.0 }'
}

run_snapshot() {
  local ps_lines
  local line
  local pid ppid pcpu rss cmd category
  local cpu_tenths entity

  declare -A pid_tcp_conns=()
  declare -A pid_tcp_rx=()
  declare -A pid_tcp_tx=()
  declare -A category_count=()
  declare -A category_cpu_tenths=()
  declare -A category_rss_kb=()
  declare -A category_tcp_conns=()
  declare -A category_tcp_rx=()
  declare -A category_tcp_tx=()
  declare -A watch_entities_count=()
  declare -A watch_entities_rss_kb=()
  declare -A watch_ppid_count=()

  while IFS=$'\t' read -r pid conns rx tx; do
    [[ -n "$pid" ]] || continue
    pid_tcp_conns[$pid]="$conns"
    pid_tcp_rx[$pid]="$rx"
    pid_tcp_tx[$pid]="$tx"
  done < <(collect_tcp_pid_stats)

  sleep "$sample_seconds"

  ps_lines="$(ps -eo pid=,ppid=,pcpu=,rss=,args= | awk '{pid=$1; ppid=$2; cpu=$3; rss=$4; $1=$2=$3=$4=""; sub(/^ +/, "", $0); printf "%s\t%s\t%s\t%s\t%s\n", pid, ppid, cpu, rss, $0 }')"

  while IFS=$'\t' read -r pid ppid pcpu rss cmd; do
    category="$(category_for_cmd "$cmd")"
    [[ -n "$category" ]] || continue

    cpu_tenths="$(awk -v v="$pcpu" 'BEGIN { printf "%.0f", v * 10.0 }')"

    category_count[$category]=$(( ${category_count[$category]:-0} + 1 ))
    category_cpu_tenths[$category]=$(( ${category_cpu_tenths[$category]:-0} + cpu_tenths ))
    category_rss_kb[$category]=$(( ${category_rss_kb[$category]:-0} + rss ))

    if [[ -n "${pid_tcp_conns[$pid]:-}" ]]; then
      category_tcp_conns[$category]=$(( ${category_tcp_conns[$category]:-0} + ${pid_tcp_conns[$pid]} ))
      category_tcp_rx[$category]=$(( ${category_tcp_rx[$category]:-0} + ${pid_tcp_rx[$pid]} ))
      category_tcp_tx[$category]=$(( ${category_tcp_tx[$category]:-0} + ${pid_tcp_tx[$pid]} ))
    fi

    if [[ "$cmd" == *"go-automate ha bridge watch entity --waybar"* ]]; then
      entity="${cmd##* }"
      if [[ "$entity" =~ ^[a-z_]+\.[a-z0-9_]+$ ]]; then
        watch_entities_count[$entity]=$(( ${watch_entities_count[$entity]:-0} + 1 ))
        watch_entities_rss_kb[$entity]=$(( ${watch_entities_rss_kb[$entity]:-0} + rss ))
      fi
      watch_ppid_count[$ppid]=$(( ${watch_ppid_count[$ppid]:-0} + 1 ))
    fi
  done <<< "$ps_lines"

  printf 'CPU sample window: %.1fs\n' "$sample_seconds"
  printf 'CATEGORY\tCOUNT\tCPU%%_SUM\tRSS_MB_SUM\tTCP_CONNS\tTCP_RX_MB\tTCP_TX_MB\n'

  for category in "${!category_count[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$category" \
      "${category_count[$category]}" \
      "$(format_tenths "${category_cpu_tenths[$category]:-0}")" \
      "$(format_rss_kb_to_mb "${category_rss_kb[$category]:-0}")" \
      "${category_tcp_conns[$category]:-0}" \
      "$(format_bytes_to_mb "${category_tcp_rx[$category]:-0}")" \
      "$(format_bytes_to_mb "${category_tcp_tx[$category]:-0}")"
  done | sort

  printf '\nTOP_WATCH_ENTITIES\tCOUNT\tRSS_MB_SUM\n'
  for entity in "${!watch_entities_count[@]}"; do
    printf '%s\t%s\t%s\n' \
      "$entity" \
      "${watch_entities_count[$entity]}" \
      "$(format_rss_kb_to_mb "${watch_entities_rss_kb[$entity]:-0}")"
  done | sort -t$'\t' -k2,2nr | awk 'NR<=10'

  printf '\nTOP_WATCH_PARENT_PIDS\tCOUNT\n'
  for parent_pid in "${!watch_ppid_count[@]}"; do
    printf '%s\t%s\n' "$parent_pid" "${watch_ppid_count[$parent_pid]}"
  done | sort -t$'\t' -k2,2nr | awk 'NR<=5'

  if (( growth_seconds > 0 )); then
    local start end delta per_min
    start="$(count_watchers)"
    sleep "$growth_seconds"
    end="$(count_watchers)"
    delta=$((end - start))
    per_min="$(awk -v d="$delta" -v w="$growth_seconds" 'BEGIN { printf "%.1f", d * (60.0 / w) }')"
    printf '\nWATCHER_GROWTH\twindow_s=%s\tstart=%s\tend=%s\tdelta=%s\test_per_min=%s\n' \
      "$growth_seconds" "$start" "$end" "$delta" "$per_min"
  fi
}

{
  if (( reset_environment )); then
    printf 'Preparation: stopping Waybar and related watcher/module processes\n'
    cleanup_waybar_processes
    printf 'Preparation: restarting Waybar before measurement\n'
    restart_waybar
    sleep 2
  else
    printf 'Preparation: using current live Waybar state (no reset)\n'
  fi
  run_snapshot
} | tee "$output_file"

if (( reset_environment )); then
  restart_waybar
fi
printf '\nSaved benchmark output: %s\n' "$output_file" | tee -a "$output_file"
if (( reset_environment )); then
  printf 'Post-run: Waybar restart requested\n' | tee -a "$output_file"
else
  printf 'Post-run: no restart (live-state mode)\n' | tee -a "$output_file"
fi
