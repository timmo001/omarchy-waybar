# Waybar Home Assistant Agent Notes

Instructions for agents editing this Waybar config.

## Home Assistant Watchers (Go Automate)

- Use `go-automate ha bridge watch entity` for Waybar watcher scripts by default.
- Do not introduce `go-automate ha watch entity` direct watchers unless bridge mode is unavailable and explicitly required.
- For machine-consumed module output, prefer `--waybar` JSON output.
- If a watcher emits plain text intentionally, document why in the script.

## Script Safety

- Avoid spawning long-lived orphan watcher processes from interval scripts.
- If a script polls only one value, use bounded execution (`timeout`) and stop after the first emitted line.
