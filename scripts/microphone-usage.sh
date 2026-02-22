#!/bin/bash
# Outputs microphone usage state as JSON for waybar custom module
# Detects processes with active ALSA capture devices via /proc/asound/

declare -A pids

for status_file in /proc/asound/card*/pcm*c/sub*/status; do
  [[ -f "$status_file" ]] || continue
  content=$(< "$status_file")

  [[ "$content" == *"state: RUNNING"* ]] || continue

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    if [[ "$line" == owner_pid* ]]; then
      pid="${line#*:}"
      pid="${pid// /}"
      if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
        pids["$pid"]=1
      fi
    fi
  done <<< "$content"
done

names=()
for pid in "${!pids[@]}"; do
  if [[ -r "/proc/$pid/comm" ]]; then
    name=$(< "/proc/$pid/comm")
    [[ -n "$name" ]] && names+=("$name")
  fi
done

if [[ ${#names[@]} -gt 0 ]]; then
  apps=$(printf '%s, ' "${names[@]}")
  apps="${apps%, }"
  echo "{\"text\": \"󰍬\", \"tooltip\": \"Microphone in use by: ${apps}\", \"class\": \"in-use\"}"
else
  echo '{"text": "", "class": "idle"}'
fi
