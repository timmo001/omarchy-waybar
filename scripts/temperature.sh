#!/bin/bash

entity_id=${1:-sensor.meter_plus_378b_temperature}
entity_name=${2:-Meter Plus Temperature}

line=""
coproc TEMP_WATCH {
  go-automate ha watch entity --waybar --icon '' "$entity_id" 2>/dev/null
}
IFS= read -r line <&"${TEMP_WATCH[0]}"
kill "$TEMP_WATCH_PID" 2>/dev/null
wait "$TEMP_WATCH_PID" 2>/dev/null

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
