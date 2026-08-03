#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$SCRIPT_DIR/../scripts/package-updates-waybar.sh"
TEST_DIR="$(mktemp -d)"
PACKAGE_FILE="$TEST_DIR/packages"
CACHE_DIR="$TEST_DIR/cache"
FAKE_YAY="$TEST_DIR/yay"
FAKE_PKILL="$TEST_DIR/pkill"
FAKE_SETSID="$TEST_DIR/setsid"

trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$CACHE_DIR"

cat >"$FAKE_YAY" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_YAY_ARGS_FILE"
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
esac
EOF

cat >"$FAKE_PKILL" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$FAKE_SETSID" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$FAKE_YAY" "$FAKE_PKILL" "$FAKE_SETSID"

export WAYBAR_PACKAGE_UPDATES_FILE="$PACKAGE_FILE"
export WAYBAR_PACKAGE_UPDATES_CACHE_DIR="$CACHE_DIR"
export WAYBAR_PACKAGE_UPDATES_YAY_BIN="$FAKE_YAY"
export WAYBAR_PACKAGE_UPDATES_PKILL_BIN="$FAKE_PKILL"
export WAYBAR_PACKAGE_UPDATES_SETSID_BIN="$FAKE_SETSID"
export FAKE_YAY_ARGS_FILE="$TEST_DIR/yay-args"

cat >"$PACKAGE_FILE" <<'EOF'
# Watched packages

context-git
  system-bridge-git # inline comment
EOF

assert_json() {
  local expression="$1"
  jq -e "$expression" "$CACHE_DIR/package-updates-waybar.json" >/dev/null
}

FAKE_YAY_RESULT=updates "$MODULE" refresh
assert_json '.text == "󰏗 2" and .class == "package-updates"'
assert_json '.tooltip == "Watched package updates:\ncontext-git\nsystem-bridge-git"'
expected_args=$'-Quq\n--\ncontext-git\nsystem-bridge-git'
[[ "$(<"$FAKE_YAY_ARGS_FILE")" == "$expected_args" ]]

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_YAY_RESULT=none "$MODULE" refresh
assert_json '.text == "" and .class == "hidden"'

rm -rf "$CACHE_DIR/package-updates-waybar.lock"
FAKE_YAY_RESULT=error "$MODULE" refresh
assert_json '.text == " ?" and .class == "package-updates-unknown"'

rm -f "$CACHE_DIR/package-updates-waybar.json"
rmdir "$CACHE_DIR/package-updates-waybar.lock" 2>/dev/null || true
loading_json="$($MODULE status)"
jq -e '.text == "󰏗 .." and .class == "package-updates-unknown"' <<<"$loading_json" >/dev/null

printf '{"text":"cached","class":"package-updates"}\n' >"$CACHE_DIR/package-updates-waybar.json"
cached_json="$($MODULE status)"
jq -e '.text == "cached" and .class == "package-updates"' <<<"$cached_json" >/dev/null

printf 'package-updates-waybar: all tests passed\n'
