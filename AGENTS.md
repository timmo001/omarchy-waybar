# Waybar Home Assistant Agent Notes

Instructions for agents editing this Waybar config.

## Home Assistant Watchers (Go Automate)

- Use `go-automate ha bridge watch entity` for Waybar watcher scripts by default.
- Do not introduce `go-automate ha watch entity` direct watchers unless bridge mode is unavailable and explicitly required.
- For machine-consumed module output, prefer `--waybar` JSON output.
- If a watcher emits plain text intentionally, document why in the script.

## Script Safety

- Avoid spawning long-lived orphan watcher processes from interval scripts.
- If a script polls only one value, read one line then terminate the watcher process group immediately.

## Tests and Benchmarks

- Keep Waybar-specific test scripts in `.tests/`.
- Keep Waybar-specific benchmark scripts in `.benchmarks/`.
- Keep generated outputs in:
  - `.tests/output/`
  - `.benchmarks/output/`
- Do not commit generated output files.

## Validation Scripts

- Full lifecycle and leak check:
  - `.tests/waybar-leak-test.sh`
- Command runtime benchmark:
  - `.benchmarks/waybar-command-bench.sh`
- Daemon/process usage benchmark:
  - `.benchmarks/waybar-daemon-usage.sh`

## Process Reset Policy

- `.tests/waybar-leak-test.sh` always kills Waybar/module/watcher processes first, runs checks, then restarts Waybar at the end.
- `.benchmarks/waybar-command-bench.sh` always runs in reset mode (kill first, restart before measuring, restart after).
- `.benchmarks/waybar-daemon-usage.sh` defaults to live-state mode for long-period observation.
- Use `.benchmarks/waybar-daemon-usage.sh --reset` when a clean baseline is required.

## Reporting Style for Test Scripts

- Keep output human-readable first, while retaining enough detail for debugging process leaks.
- Include both aggregate counts and a detailed process list when reporting watcher/module state.
