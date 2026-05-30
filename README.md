# Omarchy Waybar

Waybar config for [omarchy](https://omarchy.org).

You can find my other dotfiles [here](https://github.com/timmo001/dotfiles).

## Git Modules

- `custom/git-workflows` uses `~/.config/waybar/scripts/git-workflows-waybar.sh`.
- The workflow module reads `dot git-workflows --waybar --since <one-hour-ago>` so it only reflects watched workflow runs created in the last hour.
- `custom/git-diff` uses `~/.config/waybar/scripts/git-diff-waybar.sh` and reads `dot git-diff --waybar`.
- Left click opens the filtered TUI; right click refreshes the cache or alternate git diff pane.
