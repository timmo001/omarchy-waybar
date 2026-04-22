#!/usr/bin/env bash

set -euo pipefail

MOTION_ENTITY="binary_sensor.front_door_motion_2"
MOTION_ICON="󰤂"
SIMULATE_STATE=""
FORCE_TRUE=0

POPUP_ENABLED=1
POPUP_CAMERA_ENTITY="camera.front_door"
POPUP_BASE_URL="http://homeassistant.local:8123"
POPUP_WORKSPACE="1"
POPUP_WIDTH="640"
POPUP_HEIGHT="640"
POPUP_MARGIN="16"
POPUP_BOTTOM_MARGIN="6"
POPUP_DURATION_SECONDS="20"

POPUP_URL=""
POPUP_LOCK_FILE=""
popup_lock_fd=""
popup_addr=""
close_timer_pid=""
waybar_parent_pid=""
waybar_parent_starttime=""

usage() {
  cat <<'EOF'
Usage: front-door-motion.sh [options] [entity_id]

Options:
  --entity <entity_id>           Motion entity to watch
  --icon <icon>                  Icon shown when motion is active
  --simulate <on|off>            Emit one simulated state and exit
  --force-true                   Force simulated on state and exit
  --no-popup                     Disable popup behavior
  --popup-camera-entity <id>     Camera entity for more-info popup
  --popup-base-url <url>         Home Assistant base URL
  --popup-workspace <id>         Workspace for popup placement
  --popup-width <px>             Popup width in pixels
  --popup-height <px>            Popup height in pixels
  --popup-margin <px>            Left margin in pixels
  --popup-bottom-margin <px>     Bottom margin in pixels
  --popup-duration <seconds>     Popup visibility duration
  --help                         Show this help
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
      --no-popup)
        POPUP_ENABLED=0
        shift
        ;;
      --popup-camera-entity)
        POPUP_CAMERA_ENTITY="$2"
        shift 2
        ;;
      --popup-base-url)
        POPUP_BASE_URL="$2"
        shift 2
        ;;
      --popup-workspace)
        POPUP_WORKSPACE="$2"
        shift 2
        ;;
      --popup-width)
        POPUP_WIDTH="$2"
        shift 2
        ;;
      --popup-height)
        POPUP_HEIGHT="$2"
        shift 2
        ;;
      --popup-margin)
        POPUP_MARGIN="$2"
        shift 2
        ;;
      --popup-bottom-margin)
        POPUP_BOTTOM_MARGIN="$2"
        shift 2
        ;;
      --popup-duration)
        POPUP_DURATION_SECONDS="$2"
        shift 2
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

validate_numeric_settings() {
  local key value

  for key in POPUP_WORKSPACE POPUP_WIDTH POPUP_HEIGHT POPUP_MARGIN POPUP_BOTTOM_MARGIN POPUP_DURATION_SECONDS; do
    value="${!key}"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value <= 0 )); then
      printf 'front-door-motion.sh: %s must be a positive integer\n' "$key" >&2
      exit 1
    fi
  done
}

require_commands() {
  local cmd

  for cmd in go-automate jq flock; do
    command -v "$cmd" >/dev/null 2>&1 || {
      printf 'front-door-motion.sh: missing command: %s\n' "$cmd" >&2
      exit 1
    }
  done

  if (( POPUP_ENABLED )); then
    for cmd in hyprctl omarchy-launch-webapp; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'front-door-motion.sh: popup disabled (missing command: %s)\n' "$cmd" >&2
        POPUP_ENABLED=0
      fi
    done
  fi
}

find_waybar_ancestor_pid() {
  local pid="$PPID"
  local depth=0
  local comm=""
  local next_pid=""

  while [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 )) && (( depth < 8 )); do
    comm="$(awk '{print $2}' "/proc/$pid/stat" 2>/dev/null || true)"
    if [[ "$comm" == "(waybar)" ]]; then
      printf '%s' "$pid"
      return 0
    fi

    next_pid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || true)"
    if [[ ! "$next_pid" =~ ^[0-9]+$ ]] || (( next_pid <= 1 )); then
      break
    fi

    pid="$next_pid"
    depth=$((depth + 1))
  done

  return 1
}

capture_waybar_parent_starttime() {
  waybar_parent_pid="$(find_waybar_ancestor_pid || printf '%s' "$PPID")"
  waybar_parent_starttime="$(awk '{print $22}' "/proc/$waybar_parent_pid/stat" 2>/dev/null || true)"

  if [[ -z "$waybar_parent_starttime" ]]; then
    printf 'front-door-motion.sh: unable to read Waybar parent starttime\n' >&2
    exit 1
  fi
}

emit_on() {
  printf '{"class":"active","text":"%s","tooltip":"Front Door Motion (%s): Motion detected"}\n' "$MOTION_ICON" "$MOTION_ENTITY"
}

emit_off() {
  printf '{"class":"hidden","text":"","tooltip":"Front Door Motion (%s): Clear"}\n' "$MOTION_ENTITY"
}

window_exists() {
  local addr="$1"
  [[ -n "$addr" ]] || return 1
  hyprctl -j clients | jq -e --arg addr "$addr" '.[] | select(.address == $addr)' >/dev/null
}

resolve_workspace_monitor_name() {
  local monitor_name

  monitor_name="$(hyprctl -j workspaces | jq -r --argjson workspace "$POPUP_WORKSPACE" '.[] | select(.id == $workspace) | .monitor' | head -n 1)"
  if [[ -z "$monitor_name" || "$monitor_name" == "null" ]]; then
    monitor_name="$(hyprctl -j monitors | jq -r '.[] | select(.focused == true) | .name' | head -n 1)"
  fi

  printf '%s' "$monitor_name"
}

position_popup() {
  local addr="$1"
  local monitor_name monitor_json
  local monitor_x monitor_y monitor_height
  local reserved_left reserved_bottom
  local pos_x pos_y

  monitor_name="$(resolve_workspace_monitor_name)"
  [[ -n "$monitor_name" ]] || return 1

  monitor_json="$(hyprctl -j monitors | jq -c --arg name "$monitor_name" '.[] | select(.name == $name)')"
  [[ -n "$monitor_json" ]] || return 1

  monitor_x="$(jq -r '.x // 0' <<< "$monitor_json")"
  monitor_y="$(jq -r '.y // 0' <<< "$monitor_json")"
  monitor_height="$(jq -r '.height // 0' <<< "$monitor_json")"
  reserved_left="$(jq -r '.reserved[0] // 0' <<< "$monitor_json")"
  reserved_bottom="$(jq -r '.reserved[3] // 0' <<< "$monitor_json")"

  pos_x=$((monitor_x + reserved_left + POPUP_MARGIN))
  pos_y=$((monitor_y + monitor_height - reserved_bottom - POPUP_HEIGHT - POPUP_BOTTOM_MARGIN))

  hyprctl dispatch movetoworkspacesilent "${POPUP_WORKSPACE},address:${addr}" >/dev/null 2>&1 || true
  hyprctl dispatch setfloating "address:${addr}" >/dev/null 2>&1 || true
  hyprctl dispatch resizewindowpixel "exact ${POPUP_WIDTH} ${POPUP_HEIGHT},address:${addr}" >/dev/null 2>&1 || true
  hyprctl dispatch movewindowpixel "exact ${pos_x} ${pos_y},address:${addr}" >/dev/null 2>&1 || true
}

find_new_popup_window() {
  local before_addresses_json="$1"

  hyprctl -j clients | jq -r --argjson before "$before_addresses_json" '
    [
      .[]
      | select(.mapped == true)
      | select((.address as $addr | $before | index($addr)) == null)
    ]
    | sort_by(.focusHistoryID)
    | reverse
    | .[0].address // empty
  '
}

open_popup() {
  local before_addresses_json
  local new_addr=""
  local attempt

  before_addresses_json="$(hyprctl -j clients | jq -c '[.[].address]')"
  omarchy-launch-webapp "$POPUP_URL" >/dev/null 2>&1 &

  for ((attempt = 0; attempt < 80; attempt += 1)); do
    new_addr="$(find_new_popup_window "$before_addresses_json")"
    if [[ -n "$new_addr" ]]; then
      popup_addr="$new_addr"
      position_popup "$popup_addr" || true
      return 0
    fi
    sleep 0.1
  done

  return 1
}

stop_close_timer() {
  if [[ -n "$close_timer_pid" ]] && kill -0 "$close_timer_pid" 2>/dev/null; then
    kill "$close_timer_pid" 2>/dev/null || true
    wait "$close_timer_pid" 2>/dev/null || true
  fi
  close_timer_pid=""
}

schedule_close() {
  local addr="$1"

  stop_close_timer
  (
    sleep "$POPUP_DURATION_SECONDS"
    if hyprctl -j clients | jq -e --arg close_addr "$addr" '.[] | select(.address == $close_addr)' >/dev/null; then
      hyprctl dispatch closewindow "address:${addr}" >/dev/null 2>&1 || true
    fi
  ) &
  close_timer_pid="$!"
}

acquire_popup_lock() {
  if ! (( POPUP_ENABLED )); then
    return
  fi

  POPUP_LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/front-door-popup.${MOTION_ENTITY}.lock"
  exec {popup_lock_fd}>"$POPUP_LOCK_FILE"
  if ! flock -n "$popup_lock_fd"; then
    POPUP_ENABLED=0
  fi
}

handle_motion_event() {
  if ! (( POPUP_ENABLED )); then
    return
  fi

  if window_exists "$popup_addr"; then
    position_popup "$popup_addr" || true
    schedule_close "$popup_addr"
    return
  fi

  popup_addr=""
  if open_popup; then
    schedule_close "$popup_addr"
  fi
}

state_from_line() {
  local line="$1"
  local state

  state="$(jq -r '.class // ""' <<< "$line" 2>/dev/null)"
  state="${state%% *}"

  if [[ "$state" == "on" ]]; then
    printf 'on'
  else
    printf 'off'
  fi
}

consume_stream() {
  local line state

  while IFS= read -r line; do
    state="$(state_from_line "$line")"

    if [[ "$state" == "on" ]]; then
      emit_on
      handle_motion_event
    else
      emit_off
    fi
  done
}

cleanup() {
  stop_close_timer
  if [[ -n "$popup_lock_fd" ]]; then
    exec {popup_lock_fd}>&-
  fi
}

main() {
  parse_args "$@"

  if (( FORCE_TRUE )); then
    SIMULATE_STATE="on"
  fi

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

  POPUP_URL="${POPUP_BASE_URL}/lovelace/home?more-info-entity-id=${POPUP_CAMERA_ENTITY}"

  validate_numeric_settings
  require_commands
  capture_waybar_parent_starttime
  acquire_popup_lock
  trap cleanup EXIT INT TERM

  consume_stream < <(
    ~/.config/dotfiles/scripts/.local/bin/singleton-stream \
      --key "front-door-motion.${MOTION_ENTITY}" \
      --parent-pid "$waybar_parent_pid" \
      --parent-starttime "$waybar_parent_starttime" \
      -- go-automate ha bridge watch entity --waybar --icon '' "$MOTION_ENTITY"
  )
}

main "$@"
