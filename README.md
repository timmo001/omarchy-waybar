# Omarchy Waybar

Waybar config for [omarchy](https://omarchy.org).

You can find my other dotfiles [here](https://github.com/timmo001/dotfiles).

## GitHub Workflows

- `custom/github-workflows` uses `~/.config/waybar/scripts/github-workflows-waybar.sh`.
- The module reads `dot workflows --waybar --since <one-hour-ago>` so it only reflects watched workflow runs created in the last hour.
- Left click opens the filtered `dot workflows` TUI; right click refreshes the cache.
