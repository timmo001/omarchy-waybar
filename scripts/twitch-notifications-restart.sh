#!/usr/bin/env bash
set -euo pipefail

pkill -f '/usr/bin/twitch-notifications( |$)' >/dev/null 2>&1 || pkill -f '(^| )twitch-notifications( |$)' >/dev/null 2>&1 || true
sleep 1
setsid uwsm-app -- twitch-notifications >/dev/null 2>&1 &
