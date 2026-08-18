# Working on Omatheme

Omatheme is an Omarchy shell **panel plugin**: `manifest.json` at the root,
`Omatheme.qml` as the panel entry point, four self-contained panels under
`Panels/`, shared widgets and singletons under `Ui/`, and one bundled
`bin/omatheme-<domain>` helper per panel. The architecture rule that governs
everything: **QML draws, shell scripts mutate.** Anything the GUI can do must
also be reachable from a terminal through the helpers.

## Deploy and drive

The plugin runs inside the long-lived `omarchy-shell` process. Deploy by copy
(the plugin folder may not contain symlinks, and the shell's file watcher does
not see through them), then restart the shell — its QML component cache does
not reliably drop an already-loaded plugin:

```bash
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/davies-sam.omatheme/
omarchy-restart-shell
omarchy-shell shell summon davies-sam.omatheme '{}'   # open
omarchy-shell shell hide davies-sam.omatheme          # close
omarchy plugin validate .                             # before publishing
```

## Hard-won constraints

Read these before writing code; each one cost real debugging time.

- **Never call `Qt.quit()`** anywhere in this codebase — in-process it kills
  the user's entire desktop shell. User-initiated closes go through
  `root.requestClose()` (which round-trips `shell.hide` so the host's
  open-panel bookkeeping stays consistent).
- **The hosted engine severs pull-bindings over `Repeater.itemAt()`** and
  stomps `StackLayout.currentIndex` during delegate population. Push state
  imperatively instead (see `tallestImplicit`'s `recomputeTallest` and the
  `desiredIndex` heal in `Omatheme.qml`). If a layout property mysteriously
  freezes, suspect a severed binding before anything else.
- **Helpers are not on PATH inside the shell.** Every `Process` command
  resolves its executable through `Session.bin("omatheme-...")`.
- **`hyprctl keyword` does not work** — Quattro parses Lua. Live preview goes
  through `hyprctl eval 'hl.config({ ... })'`, dispatches through
  `hl.dsp.*` (see `omarchy-launch-or-focus` for the focus form).
- **Never retrigger a running `Process`** (`running = true` is a no-op and a
  `command` change is inert). Use the panels' `runApplier` queue pattern and
  drive re-reads from `onExited`, never from a wall-clock Timer.
- **Config edits must round-trip byte-identically.** The helpers rewrite only
  the lines they own; `tests/run` checks this for every writer.
- **Never edit `/usr/share/omarchy`.** User-theme writes go to
  `~/.config/omarchy/themes/<slug>/`; window chrome goes to
  `~/.config/hypr/looknfeel.lua` (deliberately not theme-owned).

## Verifying

Claims about behavior need evidence, not plausible code:

- `tests/run` exercises every helper end to end on a throwaway fork and must
  end with the desktop exactly as it started (theme, background, and a clean
  `git status` here and in the user's Hyprland config repo).
- Visual claims are proven with screenshots read back (`grim`, then look at
  the image). "The button is visible" means the entire button — border all
  the way around, margin beneath — on every tab. Crop and magnify the region
  in question rather than squinting at a full-screen shot.
- The UI cannot be clicked from a terminal. Drive tab changes with a
  temporary Timer rig in `Omatheme.qml` (`// TEMP TEST RIG`), and grep the
  diff for `TEMP` before every commit.
- QML changes get linted (the repo's reviews use the qt-qml-review ruleset);
  deviations are individually justified in the commit message, never waved
  through.
