# Waybar Tests and Benchmarks

Saved test and benchmark utilities for this Waybar setup.

## Scripts

- `.benchmarks/waybar-command-bench.sh`: command runtime benchmark.
- `.benchmarks/waybar-daemon-usage.sh`: daemon/process snapshot benchmark.
- `.tests/waybar-leak-test.sh`: full lifecycle/leak test with readable process snapshots.

## Output layout

- Benchmarks write outputs to `.benchmarks/output/`.
- Tests write outputs to `.tests/output/`.

Flow by script:
1. `.tests/waybar-leak-test.sh`: always kills first, runs lifecycle checks, then restarts.
2. `.benchmarks/waybar-command-bench.sh`: always kills first, runs command bench, then restarts.
3. `.benchmarks/waybar-daemon-usage.sh`: defaults to live-state measurement; use `--reset` for clean baseline mode.

## Usage

```bash
# Daemon/process snapshot (3s CPU sample)
.benchmarks/waybar-daemon-usage.sh

# Include watcher growth check over 20s
.benchmarks/waybar-daemon-usage.sh --growth 20

# Clean baseline snapshot (kills/restarts before measuring)
.benchmarks/waybar-daemon-usage.sh --sample 3 --growth 20 --reset

# Command-level benchmark (3 runs each)
.benchmarks/waybar-command-bench.sh

# Command-level benchmark with more runs
.benchmarks/waybar-command-bench.sh --runs 5

# Full leak/lifecycle test
.tests/waybar-leak-test.sh --cycles 3
```

## Notes

See `CHANGE_NOTES.md` for baseline findings and where changes are likely needed.
