#!/bin/bash

line=""
coproc CO2_WATCH {
  go-automate ha watch entity --waybar --icon '' sensor.apollo_air_1_806d64_co2 2>/dev/null
}
IFS= read -r line <&"${CO2_WATCH[0]}"
kill "$CO2_WATCH_PID" 2>/dev/null
wait "$CO2_WATCH_PID" 2>/dev/null

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
  printf '{"text":"󰟤 %.0f ppm","class":"critical","tooltip":"CO2 %.0f ppm"}\n' "$state" "$state"
elif (( co2_ppm > 1400 )); then
  printf '{"text":"󰟤 %.0f ppm","class":"warning","tooltip":"CO2 %.0f ppm"}\n' "$state" "$state"
else
  echo '{"text":"","class":"hidden"}'
fi
