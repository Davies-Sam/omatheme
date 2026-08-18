# Omatheme

A [Quickshell](https://quickshell.org) app for designing an
[Omarchy](https://omarchy.org) Quattro theme in place — live on the desktop
it is theming, painted from the very palette it edits.

It is built as a shell plus panels, switched by tabs that keep each panel's
unsaved edits alive:

- **Border** — the window border colors. Quattro derives every border from
  the active theme's `colors.toml` (`hyprland_active_border` /
  `hyprland_inactive_border`), and the same key feeds the bar, notifications
  and the lock screen, so a change lands everywhere at once. Dragging pushes
  the border straight into the running compositor with `hyprctl eval`
  (Quattro's Lua parser rejects `hyprctl keyword`); nothing is written until
  **Apply**.
- **Window** — the chrome Hyprland owns rather than the theme: border width,
  corner rounding, gaps and opacity. Live preview via the same eval path;
  Apply persists to `~/.config/hypr/looknfeel.lua`, touching only the six
  keys it owns and leaving the rest of that file byte-identical.
- **Palette** — a swatch grid over the theme's color keys. Applying a
  palette regenerates the whole theme (`omarchy theme set`, too slow for
  live-on-drag), so edits collect behind an explicit **Preview** — which also
  re-skins the app itself, since it paints from the theme it edits. A fork
  field copies the current theme to a new slug and switches to it, so a
  stock theme can be a starting point for real design work.

Editing a stock theme never touches `/usr/share/omarchy`: writes land in a
user overlay under `~/.config/omarchy/themes/<slug>/`, which is Omarchy's
documented override mechanism. The window scales with
`omarchy display text size`, and panel content scrolls when a short screen
or a big text scale leaves it no room.

## Shell-first architecture

QML draws, shell scripts mutate. Every panel has an `omatheme-<domain>`
helper with `show` / `set` / `reset` subcommands, so anything the GUI can do
is also reachable and testable from a terminal:

```bash
omatheme-state                   # current theme, palette, font, text scale
omatheme-border show
omatheme-border set --active "rgba(33ccffee) rgba(00ff99ee) 45deg"
omatheme-window set --rounding 12 --gaps-in 4
omatheme-window reset --all
omatheme-palette set --accent "#ff9e64"
omatheme-palette fork my-new-theme
```

## Install

Requires Omarchy (Quattro), Quickshell, and `jq`. The repo is laid out as a
[stow](https://www.gnu.org/software/stow/) package:

```bash
git clone https://github.com/Davies-Sam/omatheme ~/Projects/omatheme
cd ~/Projects && stow -t ~ omatheme
```

Launch with `omatheme` (launch-or-focus by window title), or bind it — in
Quattro's `~/.config/hypr/bindings.lua`:

```lua
hl.bind({ "SUPER", "SHIFT", "CTRL" }, "T", "exec", "omatheme")
```

and float it in `~/.config/hypr/hyprland.lua`:

```lua
hl.window_rule({ float = true, match = { title = "^Omatheme$" } })
```

(Quickshell hardcodes the app-id `org.quickshell` for every instance, so
rules must match on the title.)

## Adding a panel

1. Write `Panels/<Name>Panel.qml` — a ColumnLayout owning its own state,
   processes and action buttons, like `Panels/BorderPanel.qml`.
2. Add a small `omatheme-<domain>` helper next to the others for the reads
   and writes it needs (`omatheme-lib` has the shared theme plumbing).
3. Add one entry to `panels` in `shell.qml`. The switcher appears
   automatically at two panels.

Development notes and the original build plan live in
[omatheme-goal.md](omatheme-goal.md).
