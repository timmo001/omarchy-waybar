#!/bin/bash
# Outputs camera usage state as JSON for waybar custom module
# Detects processes with open handles to /dev/video* via /proc

declare -A pids_seen

for fd in /proc/[0-9]*/fd/*; do
  target=$(readlink "$fd" 2>/dev/null) || continue
  if [[ "$target" == /dev/video* ]]; then
    pid="${fd#/proc/}"
    pid="${pid%%/fd/*}"
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
