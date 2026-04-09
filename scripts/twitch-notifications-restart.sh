#!/usr/bin/env bash
set -euo pipefail

if [[ "$(twitch-notifications --status 2>/dev/null || printf 'inactive')" != "inactive" ]]; then
  exit 0
fi

pkill -f '/usr/bin/twitch-notifications( |$)' >/dev/null 2>&1 || pkill -f '(^| )twitch-notifications( |$)' >/dev/null 2>&1 || true
sleep 1
setsid uwsm-app -- twitch-notifications >/dev/null 2>&1 &
