#!/bin/bash

line=$(
  go-automate ha watch entity --waybar --icon '' sensor.apollo_air_1_806d64_co2 2>/dev/null |
    { IFS= read -r first_line; printf '%s\n' "$first_line"; }
)

state=${line#*\"class\":\"}
state=${state%%\"*}

if [[ ! "$state" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo '{"text":"","class":"hidden"}'
  exit 0
fi

co2_ppm=${state%%.*}

if (( co2_ppm > 2000 )); then
  printf '{"text":"󰟤","class":"critical","tooltip":"CO2 %.0f ppm"}\n' "$state"
elif (( co2_ppm > 1400 )); then
  printf '{"text":"󰟤","class":"warning","tooltip":"CO2 %.0f ppm"}\n' "$state"
else
  echo '{"text":"","class":"hidden"}'
fi
