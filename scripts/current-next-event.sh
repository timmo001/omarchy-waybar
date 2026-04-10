#!/bin/bash

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

line="$(read_entity_line input_text.current_next_event_in_an_hour)"

if [[ -z "$line" ]] || [[ "$line" == *'"text":""'* ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

echo "$line"
