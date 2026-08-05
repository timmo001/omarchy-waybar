# Omarchy Waybar

Waybar config for [omarchy](https://omarchy.org).

You can find my other dotfiles [here](https://github.com/timmo001/dotfiles).

## Git Modules

- `custom/git-notifications` uses the stowed `git-notifications-bar` command and reads `dot git-notifications --bar-json`.
- `custom/git-workflows` uses the stowed `git-workflows-bar` command.
- The workflow module reads `dot git-workflows --bar-json --since <one-hour-ago>` so it only reflects watched workflow runs created in the last hour.
- `custom/git-diff` uses the stowed `git-diff-bar` command and reads `dot git-diff --bar-json`.
- Left click opens the relevant TUI; right click refreshes the cache or alternate git diff pane.

## Package Updates

- `custom/package-updates` reads package names from `~/.config/dotfiles/.dot-public-packages` and checks repository packages with `pacman -Qu` and foreign packages with `yay -Qua`.
- Repo and AUR package updates are shown as a count with the package names in the tooltip. Repository updates remain visible when the AUR check fails, and the module stays hidden when every watched package is current.
- The module sits alongside Omarchy's built-in update indicator. Its cache refreshes every 15 minutes, on signal 12, or on right click. AUR HTTP 4xx/5xx responses trigger an AUR-only exponential retry delay from 30 minutes up to six hours. Left click opens the full Omarchy updater.
