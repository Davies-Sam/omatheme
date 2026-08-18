# Omatheme — remaining work

A brief for a fresh session. Omatheme is a Quickshell app for designing the
current Omarchy Quattro theme. It ships one panel (Border); this document
covers the next two.

Work top to bottom. Tick a box only when its **Done when** clauses all hold.
Commit after each task with a message explaining *why*, and stop to ask if a
task turns out to be a bad idea rather than forcing it through.

---

## Where things live

Everything is a stow package in `~/dotfiles`, symlinked into `$HOME`. **Edit
the files under `~/dotfiles/omatheme/`** — the copies in `~/.config` and
`~/.local/bin` are symlinks to them, so edits are live immediately and land in
git automatically. Never edit through the symlink path, and never re-run
`stow` unless you added a new file (then `cd ~/dotfiles && stow omatheme`).

```
~/dotfiles/omatheme/
  .config/quickshell/omatheme/
    shell.qml               window, session state, text scaling, panel switcher
    Ui/                     qmldir + Theme/Session singletons + shared widgets
    Panels/BorderPanel.qml  the one existing panel — copy its shape
  .local/bin/
    omatheme                launcher (launch-or-focus by window title)
    omatheme-state          shared session: theme, palette, font, text scale
    omatheme-border         the Border panel's domain helper
  .local/share/applications/omatheme.desktop
```

Hyprland integration lives in `~/dotfiles/hypr/.config/hypr/` — `hyprland.lua`
holds the float rule, `bindings.lua` the `SUPER + SHIFT + CTRL + T` binding.

**Architecture rule:** QML draws, shell scripts mutate. Every panel gets an
`omatheme-<domain>` helper with `show` / `set` / `reset` subcommands, so
anything the GUI can do is reachable and testable from a terminal. Keep panels
self-contained: own state, own processes, own action buttons.

---

## Constraints that cost real time to discover

Read these before writing code. Each one was found the hard way.

- **`hyprctl keyword` does not work.** Quattro configures Hyprland in Lua and
  answers *"keyword can't work with non-legacy parsers. Use eval."* Live
  preview must go through `hyprctl eval` with a Lua body, e.g.
  `hyprctl eval 'hl.config({ general = { gaps_in = 4 } })'`.
- **Never edit `/usr/share/omarchy`.** It is package-owned and overwritten on
  update. Reading it is encouraged. To change a stock theme, create
  `~/.config/omarchy/themes/<slug>/` containing only the files you override —
  Omarchy lays the stock theme down first and yours win on top.
- **Do not name a QML singleton `Palette`.** It collides with a built-in
  QtQuick type; every token silently resolves to `undefined` with no error.
  The existing singletons are `Theme` (tokens) and `Session` (current theme).
- **`console.log` / `console.warn` do not reach stdout.** They land in
  Quickshell's own log: `/run/user/1000/quickshell/by-id/*/log.qslog` (newest
  by mtime). Debugging by tailing the launch output will mislead you.
- **Qt only ever grows a mapped floating window.** A smaller `implicitHeight`
  is ignored once the compositor has committed a size; shrink by asking
  Hyprland: `hyprctl dispatch 'hl.dsp.window.resize({ window = "title:Omatheme", x = W, y = H })'`.
  Setting `width`/`height` directly is deprecated and pins the window.
- **Clamp `minimumSize` as well as `implicitHeight`.** Both scale with text
  size, and an unclamped floor re-inflates the window past the screen clamp.
- **Quickshell hardcodes the app-id `org.quickshell`** for every instance, so
  the float rule, the launcher and any window lookup match on the *title*
  `Omatheme`. Do not add `StartupWMClass` to the desktop entry — it would
  claim omarchy-shell's surfaces too.
- **`omarchy theme set <slug>` regenerates 20+ files (~0.5s).** Fine for
  Apply, far too slow to run on every slider pixel.

### How to test

The app cannot be clicked from a terminal, so verify by driving the helper
directly *and* by looking at the result:

```bash
qs -c omatheme &                     # launch (shows QML errors on stdout)
grim ~/shot.png                      # FULL screen, not just the window
```

Capture the **whole screen**. A window-only crop hides the bug where a window
grows under the bar or off the bottom of the display. Check the window's
geometry against the usable area:

```bash
hyprctl clients -j | jq '.[] | select(.title=="Omatheme") | {at, size}'
hyprctl monitors -j | jq '.[0] | {width, height, scale, reserved}'
```

Then read the screenshot back and confirm nothing is clipped. Kill instances
by matching `omatheme` in the process cmdline — never `pkill -f` with a
pattern that also matches your own shell command.

---

## Task 1 — Window panel

Window chrome that is *not* theme-owned: border width, corner rounding, gaps
and opacity. Today these require hand-editing Lua, which makes this the
highest-value panel per line of code.

Controls: `general.border_size`, `decoration.rounding`, `general.gaps_in`,
`general.gaps_out`, `decoration.active_opacity`, `decoration.inactive_opacity`.

- [x] **1a. `omatheme-window` helper.** `show` (JSON of the six values),
      `set --<key> <value>...`, `reset [--all]`. Values are written to
      `~/.config/hypr/looknfeel.lua`, which is a **user file that already has
      content** — a `hl.config({ general = { gaps_in = 8, gaps_out = 14 } })`
      block and a per-monitor `hl.workspace_rule` for the laptop panel.
      Rewrite only the keys you own and leave everything else byte-identical.
      Read current values with `hyprctl -j getoption <option>` rather than
      parsing Lua.
      **Done when:** `omatheme-window show` prints the six live values;
      `set --rounding 12` changes only that line in `looknfeel.lua`; the
      workspace rule and the file's comments survive; `hyprctl configerrors`
      is empty afterwards.
- [x] **1b. `Panels/WindowPanel.qml`.** Sliders using the existing
      `LabeledSlider`, live preview via `hyprctl eval`, and the same
      Apply / Revert / Theme default action row as `BorderPanel.qml`. Revert
      is `hyprctl reload`.
      **Done when:** dragging a slider changes the compositor immediately;
      Apply survives `hyprctl reload`; Revert restores without writing.
- [x] **1c. Register it.** Add one entry to `panels` in `shell.qml`. The
      switcher reveals itself automatically at two panels.
      **Done when:** both tabs render, switching preserves each panel's
      unsaved state, and a full-screen capture at
      `gsettings set org.gnome.desktop.interface text-scaling-factor 1.25`
      shows the window still clearing the bar. Restore the factor to `1.0`.

## Task 2 — Palette panel

Editing the ~28 keys of the active theme's `colors.toml`. This is what makes
the app a theme designer rather than a border tool.

- [ ] **2a. `omatheme-palette` helper.** `show`, `set --<key> <hex>...`,
      `reset [--key ...|--all]`, and `fork <new-slug>` copying the current
      theme to `~/.config/omarchy/themes/<new-slug>/`. Reuse the overlay logic
      already in `omatheme-border` (`writable_colors`) rather than
      reimplementing it — consider lifting it into a small shared sourced file
      if that stays readable.
      **Done when:** editing a stock theme creates an overlay instead of
      touching `/usr/share/omarchy`; `omarchy theme list` shows a forked
      theme; a round trip leaves `colors.toml` byte-identical.
- [ ] **2b. `Panels/PalettePanel.qml`.** A swatch grid over the palette keys,
      reusing `ColorEditor` for the selected one. Because applying is a full
      `omarchy theme set`, use an explicit **Preview** button rather than
      live-on-drag, and say so in the UI.
      **Done when:** picking a swatch edits that key, Preview re-themes the
      desktop, and the app itself re-skins (it paints from the theme it edits,
      so this is a good self-test).
- [ ] **2c. Fork flow.** Somewhere to name and save a copy, so a stock theme
      can be used as a starting point without an overlay accumulating edits.
      **Done when:** fork, edit, and `omarchy theme set <new-slug>` all work
      end to end.

## Task 3 — Polish

- [ ] **3a. Scroll container.** Above roughly 1.5× text scale on a short
      screen the panel content is squeezed and the Border panel's preview
      mocks vanish. Wrap panel content so it scrolls instead.
      **Done when:** at text scale 2.0 every control is reachable and the
      window still fits the screen. Restore the factor to `1.0`.
- [ ] **3b. README.** Update the Omatheme section of `~/dotfiles/README.md`
      to describe the panels that now exist.

---

## Out of scope

Do not build these. Omarchy already does them better, and duplicating them is
how a focused tool becomes a bad settings panel:

- background switching — `SUPER + CTRL + SPACE`
- theme picking — `SUPER + SHIFT + CTRL + SPACE`
- font selection — `omarchy font set`
- text size — `omarchy display text size`
