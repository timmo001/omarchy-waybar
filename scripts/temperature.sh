#!/bin/bash

entity_id=${1:-sensor.meter_plus_378b_temperature}
entity_name=${2:-Meter Plus Temperature}

read_entity_line() {
  local watch_entity_id="$1"
  local line=""
  local watch_pid=""

  coproc ENTITY_WATCH {
    exec go-automate ha bridge watch entity --waybar --icon '' "$watch_entity_id" 2>/dev/null
  }

  watch_pid="${ENTITY_WATCH_PID:-}"
  IFS= read -r line <&"${ENTITY_WATCH[0]}" || true

  if [[ -n "$watch_pid" ]]; then
    kill -- "-$watch_pid" 2>/dev/null || kill "$watch_pid" 2>/dev/null || true
    wait "$watch_pid" 2>/dev/null || true
  fi

  printf '%s' "$line"
}

line="$(read_entity_line "$entity_id")"

if [[ -z "$line" ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

state=${line#*\"class\":\"}
state=${state%%\"*}

if [[ ! "$state" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

printf '{"text":"%.1f","class":"temperature","tooltip":"%s (%s): %.1f °C"}\n' "$state" "$entity_name" "$entity_id" "$state"
