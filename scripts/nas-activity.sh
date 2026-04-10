#!/bin/bash

entity_id=sensor.nas_activity
entity_name='NAS Activity'
switch_id=switch.nas
inactive_script_id=script.turn_off_nas_when_inactive

line=""
switch_line=""
inactive_script_line=""
coproc NAS_WATCH {
  go-automate ha watch entity --waybar --icon '' "$entity_id" 2>/dev/null
}
coproc NAS_SWITCH_WATCH {
  go-automate ha watch entity --waybar --icon '' "$switch_id" 2>/dev/null
}
coproc NAS_INACTIVE_SCRIPT_WATCH {
  go-automate ha watch entity --waybar --icon '' "$inactive_script_id" 2>/dev/null
}
IFS= read -r line <&"${NAS_WATCH[0]}"
IFS= read -r switch_line <&"${NAS_SWITCH_WATCH[0]}"
IFS= read -r inactive_script_line <&"${NAS_INACTIVE_SCRIPT_WATCH[0]}"
kill "$NAS_WATCH_PID" 2>/dev/null
wait "$NAS_WATCH_PID" 2>/dev/null
kill "$NAS_SWITCH_WATCH_PID" 2>/dev/null
wait "$NAS_SWITCH_WATCH_PID" 2>/dev/null
kill "$NAS_INACTIVE_SCRIPT_WATCH_PID" 2>/dev/null
wait "$NAS_INACTIVE_SCRIPT_WATCH_PID" 2>/dev/null

if [[ -z "$line" || -z "$switch_line" || -z "$inactive_script_line" ]]; then
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

inactive_script_state=${inactive_script_line#*\"class\":\"}
inactive_script_state=${inactive_script_state%%\"*}

if [[ ! "$state" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

class_name=''

if [[ "$inactive_script_state" == "on" ]]; then
  class_name='active'
fi

printf '{"text":"󰒋 %s","class":"%s","tooltip":"%s (%s): %s\\nTurn Off NAS When Inactive (%s): %s"}\n' "$state" "$class_name" "$entity_name" "$entity_id" "$state" "$inactive_script_id" "$inactive_script_state"
