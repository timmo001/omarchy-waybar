#!/bin/bash

line=""
voc_line=""
FAKE_STATE=${WAYBAR_FAKE_VOC_ALERT:-}

if [[ "$FAKE_STATE" == "critical" ]]; then
  printf '{"text":"󰵃 410","class":"critical","tooltip":"Apollo Air 1 VOC (sensor.apollo_air_1_806d64_sen55_voc): 410\\nApollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): Extremely abnormal"}\n'
  exit 0
elif [[ "$FAKE_STATE" == "warning" ]]; then
  printf '{"text":"󰵃 240","class":"warning","tooltip":"Apollo Air 1 VOC (sensor.apollo_air_1_806d64_sen55_voc): 240\\nApollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): Very abnormal"}\n'
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

line="$(read_entity_line sensor.apollo_air_1_806d64_voc_quality)"
voc_line="$(read_entity_line sensor.apollo_air_1_806d64_sen55_voc)"

if [[ -z "$line" || -z "$voc_line" ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

state=${line#*\"class\":\"}
state=${state%%\"*}
state_normalized=${state,,}

voc_value=${voc_line#*\"class\":\"}
voc_value=${voc_value%%\"*}

if [[ ! "$voc_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

if [[ "$state_normalized" == "extremely abnormal" ]]; then
  printf '{"text":"󰵃 %.0f","class":"critical","tooltip":"Apollo Air 1 VOC (sensor.apollo_air_1_806d64_sen55_voc): %.0f\\nApollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): %s"}\n' "$voc_value" "$voc_value" "$state"
elif [[ "$state_normalized" == "very abnormal" ]]; then
  printf '{"text":"󰵃 %.0f","class":"warning","tooltip":"Apollo Air 1 VOC (sensor.apollo_air_1_806d64_sen55_voc): %.0f\\nApollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): %s"}\n' "$voc_value" "$voc_value" "$state"
else
  echo '{"text":"","class":"hidden"}'
fi
