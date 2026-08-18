# Omatheme — milestone 2: theme authoring

A brief for a fresh session. Milestone 1 (Border, Window and Palette panels,
the fork flow, and the code-review cleanup) is done — see git history. This
milestone completes the two halves of the tool's identity: *customizing the
look and feel* (backgrounds, mode) and *authoring a standalone theme* that
can leave this machine (previews, publishing, palette generation).

Work top to bottom. Tick a box only when its **Done when** clauses all hold.
Commit after each task with a message explaining *why*, push to origin, and
stop to ask if a task turns out to be a bad idea rather than forcing it
through.

---

## Where things live

This repo is `~/Projects/omatheme`, laid out as a stow package and symlinked
into `$HOME` (`cd ~/Projects && stow -t ~ omatheme`). **Edit files here** —
the copies under `~/.config` and `~/.local/bin` are symlinks, so edits are
live immediately. Re-run stow only when adding a new file. Push to
`github.com/Davies-Sam/omatheme` (private for now).

```
.config/quickshell/omatheme/
  shell.qml               window, session state, text scaling, panel switcher
  Ui/                     qmldir + Theme/Session singletons + shared widgets
                          (Field, HexField, LabeledSlider, Segmented,
                           TextButton, ColorEditor, BorderPreview)
  Panels/                 BorderPanel, WindowPanel, PalettePanel — copy their
                          shape: self-contained ColumnLayout, own processes,
                          own action row
.local/bin/
  omatheme                launcher (launch-or-focus by window title)
  omatheme-state          shared session: theme, palette, font, text scale
  omatheme-lib            sourced by helpers: current_slug, source_colors,
                          writable_colors, apply_theme, die
  omatheme-border/-window/-palette   the existing domain helpers
```

**Architecture rule:** QML draws, shell scripts mutate. Every panel gets an
`omatheme-<domain>` helper so anything the GUI can do is reachable and
testable from a terminal. Panels stay self-contained.

---

## Constraints that cost real time to discover

Carried forward from milestone 1, plus what the code review taught. Read
these before writing code.

- **`hyprctl keyword` does not work** — Quattro parses Lua. Live preview goes
  through `hyprctl eval 'hl.config({ ... })'`.
- **Never edit `/usr/share/omarchy`.** Reading it is encouraged. User
  overrides go in `~/.config/omarchy/...`.
- **Do not name a QML singleton `Palette`** — collides with a built-in type,
  every token silently becomes `undefined`.
- **`console.log`/`console.warn` land in Quickshell's log**, not stdout:
  `/run/user/1000/quickshell/by-id/*/log.qslog` (newest by mtime). The
  files are binary-ish — `grep -a` them.
- **Qt only ever grows a mapped floating window.** Shrink via
  `hyprctl dispatch 'hl.dsp.window.resize({ window = "title:Omatheme", ... })'`.
- **Quickshell Process: setting `command` while running is inert and
  `running = true` is a no-op.** Never retrigger a running Process; use the
  panels' existing `runApplier` queue pattern, and drive re-reads from
  `onExited`, never from a wall-clock Timer.
- **`Repeater.itemAt()` is a plain function call** — a binding using it must
  also read `count` (or another reactive property) or it evaluates once
  against the unpopulated Repeater and stays null forever. shell.qml's
  `currentImplicit` is the worked example.
- **`pragma ComponentBehavior: Bound` is in force** where files have
  delegates. New delegates need `required property` model data and should
  reference the delegate root by id, not via `parent`.
- **Big images in QML need `sourceSize` and `asynchronous: true`.** The
  backgrounds are 4K wallpapers; a naive `Image { source: ... }` grid will
  decode every one at full resolution on the UI thread.
- **Long-lived watcher processes need `stdbuf -oL`** — GLib tools
  block-buffer stdout into a pipe (see the gsettings monitor in shell.qml).
- **`omarchy theme set` regenerates 20+ files (~0.5s).** Fine for a button,
  never for live-on-drag.

### Facts discovered for this milestone

- Backgrounds for the current theme resolve from **two** places (see
  `/usr/share/omarchy/bin/omarchy-theme-bg-next`): the theme's own
  `backgrounds/` dir, and a per-theme user overlay at
  `~/.config/omarchy/backgrounds/<theme-name>/`. The current background is a
  symlink at `~/.local/state/omarchy/current/background`. Allowed
  extensions: jpg, jpeg, png, gif, bmp, webp.
- `omarchy theme bg set <path>` / `bg next` / `bg cache` (thumbnail cache)
  already exist — delegate to them, never reimplement switching.
- Preview asset dimensions in stock themes: `preview.png` 1800x1012,
  `preview-unlock.png` 1920x1080, `unlock.png` 800x188.
- `omarchy theme install [git-repo-url]` installs a theme from a git repo
  (local paths work for testing); `omarchy theme remove` deletes user
  themes. The publish format is therefore "a git repo of the theme dir".
- ImageMagick (`magick`) is installed; python3 has **no** PIL. Palette
  extraction goes through magick (e.g. `-resize 25% -colors N
  -unique-colors txt:`).

### How to test

The app cannot be clicked from a terminal. Verify by driving the helper
directly *and* by looking at the result:

```bash
qs -c omatheme &                     # launch (QML errors on stdout)
grim ~/shot.png                      # FULL screen, then read it back
hyprctl clients -j | jq '.[] | select(.title=="Omatheme") | {at, size}'
```

For UI behavior, insert a `// TEMP TEST RIG` block of Timers into shell.qml
that drives panel functions (`root.panel = ...`, `panelRepeater.itemAt(n)
.item.someFunction(...)`), screenshot the stages, and **remove the rig
before committing** — grep for TEMP before every commit. Kill instances by
matching `^qs -c omatheme`, never a pattern that matches your own shell.
Anything that mutates the desktop must be restored and verified via
`git status` in this repo (and in ~/dotfiles for looknfeel.lua) before the
task is ticked.

---

## Task 1 — Backgrounds panel

Curating the theme's background *set* is authoring and belongs here; the
switching UX (SUPER+CTRL+SPACE, `bg next`) is Omarchy's and stays out.

- [x] **1a. `omatheme-bg` helper.** `list` (JSON: every background from both
      resolution paths with absolute path and which one is current),
      `add <path-or-url>` (curl for http(s) URLs, copy for files; validate
      the extension against the allowed list; for a user-owned theme the
      file lands in the theme's own `backgrounds/` so a published fork
      carries it, for a stock theme in
      `~/.config/omarchy/backgrounds/<slug>/`), `remove <filename>` (only
      from user-writable locations; refuse `/usr/share` politely), and
      `set <filename>` delegating to `omarchy theme bg set`. Run
      `omarchy theme bg cache` after add/remove.
      **Done when:** `add` works end to end for both a local file and a
      URL; the file lands in the right place for a stock theme vs a fork;
      `list` marks the current background; `remove` deletes only
      user-writable files; a stock theme's `/usr/share` dir is untouched
      throughout.
- [x] **1b. `Panels/BackgroundsPanel.qml`.** A thumbnail grid over `list`
      (Images with `sourceSize` capped and `asynchronous: true`), click to
      `set`, a `Field` + Add button accepting a path or URL (reuse the
      Field component), and a remove action for the selected background
      that is disabled for read-only files. Register as the fourth tab.
      **Done when:** thumbnails render, clicking one changes the desktop
      background, add-by-URL shows up in the grid and on disk, and the
      full-screen capture shows the window still fitting the screen with
      four tabs at text scale 1.25 (restore to 1.0 after).

## Task 2 — Light/dark mode

- [x] **2a. `mode` on `omatheme-palette`.** `mode` prints the current value;
      `mode light|dark` rewrites only that line (byte-identical round trip,
      same editing discipline as the color keys) and applies the theme.
      Other values are refused.
      **Done when:** flipping mode on a fork survives a round trip
      byte-identically and `gsettings get org.gnome.desktop.interface
      color-scheme` follows after apply.
- [x] **2b. Mode control in the Palette panel.** A two-option Segmented
      (Dark / Light) near the fork row. Applying goes through the helper —
      it is a theme regeneration, so it belongs with Preview-style actions,
      not live toggling.
      **Done when:** flipping it re-themes the desktop and the app, and the
      control reflects the real value after reload.

## Task 3 — Contrast hints

- [x] **3a. WCAG ratio in the Palette panel.** When a key is selected, show
      the contrast ratio against the theme's `background` (for foreground-
      ish keys) or against `foreground` (for `*background*` keys), computed
      in QML from the *pending* value so it updates while editing. Show the
      ratio to one decimal with a quiet pass/caution marker (≥4.5 fine,
      3–4.5 caution, below 3 warn). No new helper — this is pure display.
      **Done when:** the shown ratio matches an independently computed
      value for at least two known pairs (e.g. hermaeus foreground on
      background), and editing a color updates the ratio live.

## Task 4 — Preview regeneration

A fork keeps its parent's `preview.png`/`preview-unlock.png`, so it shows
the wrong face in Omarchy's theme switcher forever.

- [x] **4a. `omatheme-preview` helper.** `regen` captures the current
      desktop with grim and produces `preview.png` (1800x1012) and
      `preview-unlock.png` (1920x1080) via magick resize/crop into the
      current theme's writable dir (user themes only — refuse stock themes
      with a pointer to fork first). `show` prints the paths and whether
      they differ from the parent's.
      **Done when:** after regen on a fork, the files have the stock
      dimensions, and `omarchy theme switcher` shows the fork's own look
      (verify by reading the generated PNGs back, full-screen capture of
      the switcher is a bonus).
- [x] **4b. UI hook.** A "Regenerate previews" TextButton in the Palette
      panel's fork area, enabled only for user-owned themes, running the
      helper. The app's own window is part of the desktop — accept that,
      or briefly minimize via hyprctl if it proves ugly; decide while
      building and write down which.
      **Done when:** pressing it produces fresh previews for a fork.

## Task 5 — Publish

- [x] **5a. `omatheme-publish` helper.** For a user-owned theme: ensure the
      theme dir is a git repo (init + add + commit if not), and print
      copy-pasteable next steps (`gh repo create ... --push`, then
      `omarchy theme install <url>`). If `--push <remote-url>` is given,
      add the remote and push. Never touch stock themes.
      **Done when:** fork → publish → `omarchy theme install <path-or-url>`
      of the produced repo installs a working duplicate theme (local clone
      is fine for the test; clean up the duplicate after).
- [ ] **5b. UI hook.** A "Publish…" action next to the fork row that runs
      the helper and surfaces its output (the printed next steps) in the
      panel — the same pattern as forkError, but for stdout.
      **Done when:** the flow is reachable from the GUI and the output is
      readable in the panel.

## Task 6 — Palette from wallpaper

The authoring accelerator: start a theme from an image instead of from an
existing palette.

- [ ] **6a. `generate` on `omatheme-palette`.** `generate <image>` extracts
      a candidate palette with magick (quantize, then assign roles:
      backgrounds from the darkest/most common tones, foregrounds from the
      lightest, accent from the most saturated mid-tone, the eight named
      colors nearest-matched by hue with sensible fallbacks, brights
      derived by lightening; infer `mode` from overall luminance) and
      prints the full key->hex JSON **without writing anything**.
      `generate <image> --apply` writes all keys through the existing edit
      path (byte-identical formatting rules apply) and applies the theme.
      **Done when:** generate on two contrasting wallpapers produces valid
      full palettes (every key a hex, mode sensible for each), and --apply
      on a fork re-themes the desktop without hand editing.
- [ ] **6b. UI hook.** In the Backgrounds panel: "Palette from this
      background" on the selected background, which fills the Palette
      panel's pending edits (not the disk) so the user can eyeball the
      swatches and press Preview themselves. Generation quality is
      heuristic — the human stays in the loop.
      **Done when:** the flow works end to end on a fork and nothing is
      written until Preview.

## Task 7 — Polish

- [ ] **7a. README.** Update for the new panels and helpers, including the
      authoring story (fork → backgrounds → palette → previews → publish).
- [ ] **7b. Review pass.** Run the qt-qml-review lint script over changed
      QML and fix what it flags in the new code (the pre-existing style
      backlog stays out of scope); rerun the helper test suite and the
      panel rigs.

---

## Out of scope

Omarchy already does these better, and duplicating them is how a focused
tool becomes a bad settings panel:

- background *switching* UX — `SUPER + CTRL + SPACE`, `omarchy theme bg next`
- theme picking — `SUPER + SHIFT + CTRL + SPACE`
- font selection and text size — `omarchy font set`, `omarchy display text size`
- fork deletion/renaming — `omarchy theme remove`
- editing `neovim.lua` / `vscode.json` / `icons.theme` — text-editor
  territory; note in the README that forks inherit the parent's editor
  colorschemes
