#!/bin/bash

line=""
coproc VOC_WATCH {
  go-automate ha watch entity --waybar --icon '' sensor.apollo_air_1_806d64_voc_quality 2>/dev/null
}
IFS= read -r line <&"${VOC_WATCH[0]}"
kill "$VOC_WATCH_PID" 2>/dev/null
wait "$VOC_WATCH_PID" 2>/dev/null

if [[ -z "$line" ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

state=${line#*\"class\":\"}
state=${state%%\"*}
state_normalized=${state,,}

if [[ "$state_normalized" == "extremely abnormal" ]]; then
  printf '{"text":"󰵃 %s IAQ","class":"critical","tooltip":"Apollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): %s IAQ"}\n' "$state" "$state"
elif [[ "$state_normalized" == "very abnormal" ]]; then
  printf '{"text":"󰵃 %s IAQ","class":"warning","tooltip":"Apollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): %s IAQ"}\n' "$state" "$state"
else
  echo '{"text":"","class":"hidden"}'
fi
