#!/bin/bash

line=""
coproc NEXT_EVENT_WATCH {
  go-automate ha watch entity --waybar --icon '' input_text.current_next_event_in_an_hour 2>/dev/null
}
IFS= read -r line <&"${NEXT_EVENT_WATCH[0]}"
kill "$NEXT_EVENT_WATCH_PID" 2>/dev/null
wait "$NEXT_EVENT_WATCH_PID" 2>/dev/null

if [[ -z "$line" ]] || [[ "$line" == *'"text":""'* ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

echo "$line"
