#!/bin/bash
# Outputs camera usage state as JSON for waybar custom module
# Detects processes with open handles to /dev/video* via fuser

declare -A pids_seen

shopt -s nullglob
video_devices=(/dev/video*)
shopt -u nullglob

if (( ${#video_devices[@]} == 0 )); then
  echo '{"text": "", "class": "idle"}'
  exit 0
fi

for pid in $(fuser "${video_devices[@]}" 2>/dev/null || true); do
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    pids_seen["$pid"]=1
  fi
done

names=()
for pid in "${!pids_seen[@]}"; do
  if [[ -r "/proc/$pid/comm" ]]; then
    name=$(< "/proc/$pid/comm")
    [[ -n "$name" ]] && names+=("$name")
  fi
done

if [[ ${#names[@]} -gt 0 ]]; then
  apps=$(printf '%s, ' "${names[@]}")
  apps="${apps%, }"
  echo "{\"text\": \"󰄀\", \"tooltip\": \"Camera in use by: ${apps}\", \"class\": \"in-use\"}"
else
  echo '{"text": "", "class": "idle"}'
fi
