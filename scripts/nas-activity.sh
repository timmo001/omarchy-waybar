#!/bin/bash

entity_id=sensor.nas_activity
entity_name='NAS Activity'
switch_id=switch.nas

line=""
switch_line=""
coproc NAS_WATCH {
  go-automate ha watch entity --waybar --icon '' "$entity_id" 2>/dev/null
}
coproc NAS_SWITCH_WATCH {
  go-automate ha watch entity --waybar --icon '' "$switch_id" 2>/dev/null
}
IFS= read -r line <&"${NAS_WATCH[0]}"
IFS= read -r switch_line <&"${NAS_SWITCH_WATCH[0]}"
kill "$NAS_WATCH_PID" 2>/dev/null
wait "$NAS_WATCH_PID" 2>/dev/null
kill "$NAS_SWITCH_WATCH_PID" 2>/dev/null
wait "$NAS_SWITCH_WATCH_PID" 2>/dev/null

if [[ -z "$line" || -z "$switch_line" ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

switch_state=${switch_line#*\"class\":\"}
switch_state=${switch_state%%\"*}

if [[ "$switch_state" != "on" ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

state=${line#*\"class\":\"}
state=${state%%\"*}

if [[ ! "$state" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

printf '{"text":"󰒋 %s","class":"nas-activity","tooltip":"%s (%s): %s"}\n' "$state" "$entity_name" "$entity_id" "$state"
