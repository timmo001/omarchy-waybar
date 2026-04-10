#!/bin/bash

entity_id=sensor.nas_activity
entity_name='NAS Activity'
switch_id=switch.nas
inactive_script_id=script.turn_off_nas_when_inactive

line=""
switch_line=""
inactive_script_line=""

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
switch_line="$(read_entity_line "$switch_id")"
inactive_script_line="$(read_entity_line "$inactive_script_id")"

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
