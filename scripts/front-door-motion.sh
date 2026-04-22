#!/usr/bin/env bash

set -euo pipefail

MOTION_ENTITY="binary_sensor.front_door_motion_2"
MOTION_ICON="󰤂"
SIMULATE_STATE=""
FORCE_TRUE=0

usage() {
  cat <<'EOF'
Usage: front-door-motion.sh [options] [entity_id]

Options:
  --entity <entity_id>   Motion entity to watch
  --icon <icon>          Icon shown when motion is active
  --simulate <on|off>    Emit one simulated state and exit
  --force-true           Force simulated on state and exit
  --help                 Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --entity)
        MOTION_ENTITY="$2"
        shift 2
        ;;
      --icon)
        MOTION_ICON="$2"
        shift 2
        ;;
      --simulate)
        SIMULATE_STATE="$2"
        shift 2
        ;;
      --force-true)
        FORCE_TRUE=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --*)
        printf 'front-door-motion.sh: unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
      *)
        MOTION_ENTITY="$1"
        shift
        ;;
    esac
  done
}

parse_args "$@"

if (( FORCE_TRUE )); then
  SIMULATE_STATE="on"
fi

emit_on() {
  printf '{"class":"active","text":"%s","tooltip":"Front Door Motion (%s): Motion detected"}\n' "$MOTION_ICON" "$MOTION_ENTITY"
}

emit_off() {
  printf '{"class":"hidden","text":"","tooltip":"Front Door Motion (%s): Clear"}\n' "$MOTION_ENTITY"
}

case "$SIMULATE_STATE" in
  on)
    emit_on
    exit 0
    ;;
  off)
    emit_off
    exit 0
    ;;
  '')
    ;;
  *)
    printf 'front-door-motion.sh: unsupported --simulate value: %s\n' "$SIMULATE_STATE" >&2
    exit 1
    ;;
esac

exec go-automate ha bridge watch entity --waybar \
  --icon "$MOTION_ICON" \
  --tooltip-on "Front Door Motion (${MOTION_ENTITY}): Motion detected" \
  --tooltip-off "Front Door Motion (${MOTION_ENTITY}): Clear" \
  --class-on active \
  --class-off hidden \
  --hide-off \
  "$MOTION_ENTITY"
