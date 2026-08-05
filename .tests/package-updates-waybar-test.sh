#!/usr/bin/env bash

set -euo pipefail

MODULE="${PACKAGE_UPDATES_BAR_BIN:-package-updates-bar}"
TEST_DIR="$(mktemp -d)"
PACKAGE_FILE="$TEST_DIR/packages"
CACHE_DIR="$TEST_DIR/cache"
FAKE_YAY="$TEST_DIR/yay"
FAKE_PACMAN="$TEST_DIR/pacman"
FAKE_PKILL="$TEST_DIR/pkill"
FAKE_SETSID="$TEST_DIR/setsid"

trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$CACHE_DIR"

cat >"$FAKE_YAY" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_YAY_ARGS_FILE"
printf 'called\n' >>"$FAKE_YAY_CALLS_FILE"
case "$FAKE_YAY_RESULT" in
  updates)
    printf 'context-git\nsystem-bridge-git\ncontext-git\n'
    ;;
  none)
    exit 1
    ;;
  error)
    printf 'network unavailable\n' >&2
    exit 1
    ;;
  http-error)
    printf 'status 429: Rate limit reached\n' >&2
    exit 1
    ;;
esac
EOF

cat >"$FAKE_PACMAN" <<'EOF'
#!/usr/bin/env bash
case "$1:$2:${3:-}" in
  -Qnq:--:context-git) exit 0 ;;
  -Qmq:--:system-bridge-git) exit 0 ;;
  -Quq:--:*)
    [[ "$FAKE_PACMAN_RESULT" == "updates" ]] && printf 'context-git\n'
    ;;
esac
exit 1
EOF

cat >"$FAKE_PKILL" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$FAKE_SETSID" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$FAKE_YAY" "$FAKE_PACMAN" "$FAKE_PKILL" "$FAKE_SETSID"

export WAYBAR_PACKAGE_UPDATES_FILE="$PACKAGE_FILE"
export WAYBAR_PACKAGE_UPDATES_CACHE_DIR="$CACHE_DIR"
export WAYBAR_PACKAGE_UPDATES_YAY_BIN="$FAKE_YAY"
export WAYBAR_PACKAGE_UPDATES_PACMAN_BIN="$FAKE_PACMAN"
export WAYBAR_PACKAGE_UPDATES_PKILL_BIN="$FAKE_PKILL"
export WAYBAR_PACKAGE_UPDATES_SETSID_BIN="$FAKE_SETSID"
export FAKE_YAY_ARGS_FILE="$TEST_DIR/yay-args"
export FAKE_YAY_CALLS_FILE="$TEST_DIR/yay-calls"

cat >"$PACKAGE_FILE" <<'EOF'
# Watched packages

context-git
  system-bridge-git # inline comment
EOF

assert_json() {
  local expression="$1"
  jq -e "$expression" "$CACHE_DIR/package-updates-waybar.json" >/dev/null
}

FAKE_PACMAN_RESULT=updates FAKE_YAY_RESULT=updates "$MODULE" refresh
assert_json '.text == "󰏗 2" and .class == "package-updates"'
assert_json '.tooltip == "Watched package updates:\ncontext-git\nsystem-bridge-git"'
expected_args=$'-Quaq\n--\nsystem-bridge-git'
[[ "$(<"$FAKE_YAY_ARGS_FILE")" == "$expected_args" ]]

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_PACMAN_RESULT=none FAKE_YAY_RESULT=none "$MODULE" refresh
assert_json '.text == "" and .class == "hidden"'

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_PACMAN_RESULT=updates FAKE_YAY_RESULT=error "$MODULE" refresh
assert_json '.text == "󰏗 1" and .class == "package-updates"'
assert_json '.tooltip == "Watched package updates:\ncontext-git\n\nAUR updates unavailable"'

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_PACMAN_RESULT=none FAKE_YAY_RESULT=error "$MODULE" refresh
assert_json '.text == " ?" and .class == "package-updates-unknown"'
[[ ! -e "$CACHE_DIR/package-updates-waybar.backoff" ]]

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_PACMAN_RESULT=updates FAKE_YAY_RESULT=http-error "$MODULE" refresh
assert_json '.text == "󰏗 1" and .class == "package-updates"'
read -r failures retry_at <"$CACHE_DIR/package-updates-waybar.backoff"
[[ "$failures" == 1 && "$retry_at" -gt "$(date +%s)" ]]

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
calls_before="$(wc -l <"$FAKE_YAY_CALLS_FILE")"
FAKE_PACMAN_RESULT=updates FAKE_YAY_RESULT=updates "$MODULE" refresh
calls_after="$(wc -l <"$FAKE_YAY_CALLS_FILE")"
[[ "$calls_after" == "$calls_before" ]]
assert_json '.tooltip == "Watched package updates:\ncontext-git\n\nAUR updates unavailable"'

printf '1 0\n' >"$CACHE_DIR/package-updates-waybar.backoff"
rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_PACMAN_RESULT=none FAKE_YAY_RESULT=http-error "$MODULE" refresh
read -r failures retry_at <"$CACHE_DIR/package-updates-waybar.backoff"
remaining=$((retry_at - $(date +%s)))
[[ "$failures" == 2 && "$remaining" -ge 3599 && "$remaining" -le 3600 ]]

printf '2 0\n' >"$CACHE_DIR/package-updates-waybar.backoff"
rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_PACMAN_RESULT=none FAKE_YAY_RESULT=none "$MODULE" refresh
[[ ! -e "$CACHE_DIR/package-updates-waybar.backoff" ]]

rm -f "$CACHE_DIR/package-updates-waybar.json"
rmdir "$CACHE_DIR/package-updates-waybar.lock" 2>/dev/null || true
loading_json="$($MODULE status)"
jq -e '.text == "󰏗 .." and .class == "package-updates-unknown"' <<<"$loading_json" >/dev/null

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
printf '{"text":"cached","class":"package-updates"}\n' >"$CACHE_DIR/package-updates-waybar.json"
cached_json="$($MODULE status)"
jq -e '.text == "cached" and .class == "package-updates"' <<<"$cached_json" >/dev/null
[[ ! -d "$CACHE_DIR/package-updates-waybar.lock" ]]

printf 'package-updates-bar: all tests passed\n'
