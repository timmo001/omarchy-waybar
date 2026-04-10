#!/bin/bash

SENSOR_ENTITY=${1:-sensor.apollo_air_1_806d64_co2}
SENSOR_LABEL=${2:-Apollo Air 1 CO2}
FAKE_STATE=${WAYBAR_FAKE_CO2_ALERT:-}

if [[ "$FAKE_STATE" == "critical" ]]; then
  printf '{"text":"󰟤 2200 ppm","class":"critical","tooltip":"%s (%s): 2200 ppm"}\n' "$SENSOR_LABEL" "$SENSOR_ENTITY"
  exit 0
elif [[ "$FAKE_STATE" == "warning" ]]; then
  printf '{"text":"󰟤 1600 ppm","class":"warning","tooltip":"%s (%s): 1600 ppm"}\n' "$SENSOR_LABEL" "$SENSOR_ENTITY"
  exit 0
fi

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

line="$(read_entity_line "$SENSOR_ENTITY")"

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

co2_ppm=${state%%.*}

if (( co2_ppm > 2000 )); then
  printf '{"text":"󰟤 %.0f ppm","class":"critical","tooltip":"%s (%s): %.0f ppm"}\n' "$state" "$SENSOR_LABEL" "$SENSOR_ENTITY" "$state"
elif (( co2_ppm > 1400 )); then
  printf '{"text":"󰟤 %.0f ppm","class":"warning","tooltip":"%s (%s): %.0f ppm"}\n' "$state" "$SENSOR_LABEL" "$SENSOR_ENTITY" "$state"
else
  echo '{"text":"","class":"hidden"}'
fi
