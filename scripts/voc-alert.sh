#!/bin/bash

line=""
voc_line=""
coproc VOC_WATCH {
  go-automate ha watch entity --waybar --icon '' sensor.apollo_air_1_806d64_voc_quality 2>/dev/null
}
coproc VOC_VALUE_WATCH {
  go-automate ha watch entity --waybar --icon '' sensor.apollo_air_1_806d64_sen55_voc 2>/dev/null
}
IFS= read -r line <&"${VOC_WATCH[0]}"
IFS= read -r voc_line <&"${VOC_VALUE_WATCH[0]}"
kill "$VOC_WATCH_PID" 2>/dev/null
wait "$VOC_WATCH_PID" 2>/dev/null
kill "$VOC_VALUE_WATCH_PID" 2>/dev/null
wait "$VOC_VALUE_WATCH_PID" 2>/dev/null

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
  printf '{"text":"󰵃 %.0f","class":"critical","tooltip":"Apollo Air 1 VOC (sensor.apollo_air_1_806d64_sen55_voc): %.0f\\nApollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): %s IAQ"}\n' "$voc_value" "$voc_value" "$state"
elif [[ "$state_normalized" == "very abnormal" ]]; then
  printf '{"text":"󰵃 %.0f","class":"warning","tooltip":"Apollo Air 1 VOC (sensor.apollo_air_1_806d64_sen55_voc): %.0f\\nApollo Air 1 VOC Quality (sensor.apollo_air_1_806d64_voc_quality): %s IAQ"}\n' "$voc_value" "$voc_value" "$state"
else
  echo '{"text":"","class":"hidden"}'
fi
