#!/bin/bash

line=$(
  go-automate ha watch entity --waybar --icon '' sensor.apollo_air_1_806d64_voc_quality 2>/dev/null |
    { IFS= read -r first_line; printf '%s\n' "$first_line"; }
)

state=${line#*\"class\":\"}
state=${state%%\"*}
state_normalized=${state,,}

if [[ "$state_normalized" == "extremely abnormal" ]]; then
  printf '{"text":"󰴃","class":"critical","tooltip":"VOC %s"}\n' "$state"
elif [[ "$state_normalized" == "very abnormal" ]]; then
  printf '{"text":"󰴃","class":"warning","tooltip":"VOC %s"}\n' "$state"
else
  echo '{"text":"","class":"hidden"}'
fi
