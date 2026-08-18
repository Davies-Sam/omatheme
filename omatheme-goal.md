# Omatheme — milestone 3: the theme leaves the machine

A brief for a fresh session. Milestone 1 (Border, Window and Palette panels,
the fork flow, code-review cleanup) and milestone 2 (Backgrounds panel,
light/dark mode, contrast hints, preview regeneration, publish, palette
generation) are done — see git history. Their ticked tasks are kept below as
the record; milestone 3 starts at Task 8.

Milestone 3 closes the gap between "publish works" and "what you publish is
actually yours": a fork can carry its parent's lock-screen and keyboard
pins, always carries its parent's boot logo, and publish says nothing about
it. It also makes the tool itself shippable: a committed test suite,
screenshots, a dependency check, and going public.

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

### Facts discovered for milestone 3

- **Lock-screen and keyboard colors already derive from `colors.toml`.**
  Every `omarchy theme set` renders the templates in
  `/usr/share/omarchy/default/themed/` (`shell.toml.tpl` has the `[lock]`
  section; `keyboard.rgb.tpl` is `{{ accent }}`) into
  `~/.local/state/omarchy/current/next-theme/` — but only for files the
  theme dir does not ship itself. Shipped files win over generation.
- A theme-shipped **`shell.<section>.toml`** is a *section override*:
  `omarchy-theme-set-templates` splices it over the matching section of the
  generated `shell.toml`, freezing those values. A shipped `keyboard.rgb`
  overrides the generated one the same way. Among the 22 stock themes only
  tokyo-night ships either — they are optional pins, not standard files.
  A fork copies its parent's pins verbatim, which is how a fork's lock
  screen and keyboard get stuck at the parent's palette.
- **Rewriting a pin's values from the palette would degrade a fork**: the
  generated `[lock]` sets `border`/`border-active` to
  `"hyprland.active-border"` (they track the live border gradient) and
  computes `placeholder` as a foreground/background mix. Palette literals
  cannot express either. The fix for stale pins is removal, so generation
  takes over — never synchronization.
- `keyboard.rgb` consumers strip an optional leading `#`
  (`sed 's/^#//'`); the template writes one. Either form works.
- `unlock.png` genuinely has no template — it is static per theme.
  `omarchy-plymouth-set-by-theme` reads background + text from the theme's
  `colors.toml` and installs `unlock.png` byte-for-byte. Installing needs
  root — verify generated logos by reading the file back, never by
  applying.
- Stock `unlock.png` sizes vary (tokyo-night 1108x523, others 800x188):
  there is no canonical size, only "wide wordmark on transparency".
- The milestone-2 "helper test suite" was ad-hoc scratch scripts, never
  committed. Nothing in the repo runs the helpers today.
- Prior review passes deliberately left an ~89-item pre-existing QML style
  backlog (ORD-1 ordering, `var`/`==`) unfixed.

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
- [x] **5b. UI hook.** A "Publish…" action next to the fork row that runs
      the helper and surfaces its output (the printed next steps) in the
      panel — the same pattern as forkError, but for stdout.
      **Done when:** the flow is reachable from the GUI and the output is
      readable in the panel.

## Task 6 — Palette from wallpaper

The authoring accelerator: start a theme from an image instead of from an
existing palette.

- [x] **6a. `generate` on `omatheme-palette`.** `generate <image>` extracts
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
- [x] **6b. UI hook.** In the Backgrounds panel: "Palette from this
      background" on the selected background, which fills the Palette
      panel's pending edits (not the disk) so the user can eyeball the
      swatches and press Preview themselves. Generation quality is
      heuristic — the human stays in the loop.
      **Done when:** the flow works end to end on a fork and nothing is
      written until Preview.

## Task 7 — Polish

- [x] **7a. README.** Update for the new panels and helpers, including the
      authoring story (fork → backgrounds → palette → previews → publish).
- [x] **7b. Review pass.** Run the qt-qml-review lint script over changed
      QML and fix what it flags in the new code (the pre-existing style
      backlog stays out of scope); rerun the helper test suite and the
      panel rigs.

## Task 8 — Lock screen and keyboard follow the palette

A fork of a theme that ships pins (tokyo-night today) copies
`shell.*.toml` and `keyboard.rgb` verbatim, freezing its lock screen and
keyboard at the parent's palette. Omarchy already derives both from
`colors.toml` whenever the files are absent — so the fix is removal, not
synchronization (see the milestone 3 facts above).

- [x] **8a. Fork stops copying pins.** `omatheme-palette fork` excludes the
      parent's `shell.*.toml` section overrides and `keyboard.rgb` from the
      copy — a fork wants derivation, not the parent's frozen values. (Do
      not exclude a full `shell.toml`; a theme shipping the whole file made
      a deliberate choice.)
      **Done when:** a fresh fork of tokyo-night contains neither pin but
      still contains everything else the parent ships; after applying the
      fork with a distinct accent, the state dir
      (`~/.local/state/omarchy/current/theme/`) shows `keyboard.rgb` equal
      to the fork's accent and a `[lock]` section using the fork's colors;
      the test fork is removed and the previously running theme and
      background are restored (verify, don't assume).
- [x] **8b. `unpin` on `omatheme-palette`.** For existing forks that
      already carry inherited pins: delete `shell.*.toml` (again sparing
      `shell.toml` itself) and `keyboard.rgb` from a user-owned theme
      (refuse stock with a pointer to fork first), print what was removed,
      no-op with a message when nothing is pinned, and re-apply the theme.
      No UI hook — after 8a fresh forks never have the problem, so a shell
      verb is enough for old ones; this decision is recorded here.
      **Done when:** on a test fork given tokyo-night's pins, unpin removes
      both and re-applies (state dir derives them from the fork's palette
      afterwards); a second unpin no-ops with a message; a stock theme is
      refused; cleanup and restoration verified as in 8a.

## Task 9 — Boot/unlock logo

- [ ] **9a. `logo` on `omatheme-preview`.** Render the theme's name as a
      wordmark: the desktop font (from `omatheme-state`), theme foreground
      on transparency, drawn by magick at a wide aspect (the 800x188 class),
      written to the fork's `unlock.png`. User themes only. Never run
      plymouth-set — it needs root.
      **Done when:** the file has sane wide dimensions, real transparency
      and non-empty glyph pixels (verify by reading it back — `magick
      identify` plus a histogram, not just existence), and differs from the
      parent's.
- [ ] **9b. UI hook.** Fold into the existing "Regenerate previews" action
      or add a sibling button — decide while building and write down which.
      **Done when:** the flow on a fork produces the fork's own logo.

## Task 10 — Publish preflight

Publish currently says nothing about how much of the parent's identity a
fork still carries.

- [ ] **10a. `check` on `omatheme-publish`,** also run automatically before
      publish prints its next steps: compare the fork against its parent
      and warn for each inherited file that is still byte-identical and
      carries the parent's face — `preview.png`, `preview-unlock.png`,
      `unlock.png`, any `shell.*.toml` pin, `keyboard.rgb`, `neovim.lua`,
      `vscode.json`. Warn only — editor configs stay hand-edited (see out
      of scope). Point each warning at its fix (regen previews / unpin /
      logo / "edit by hand").
      **Done when:** on a fresh fork every warning fires; after running
      tasks 8–9's actions plus preview regen, only the editor-config
      warnings remain; the warnings are readable in the panel through the
      existing publish-output path.

## Task 11 — Committed test suite

The "helper test suite" so far has been ad-hoc. Commit it so a fresh
session (or a loop) can verify without reinventing it.

- [ ] **11a. `tests/run`.** A bash suite exercising every helper end to end
      on a throwaway fork: fork → palette set / mode / generate → bg add
      and remove (use a local file; no network) → unpin → preview regen
      and logo → publish into a temp dir → `omarchy theme install` from the
      local path → verify → `theme remove` + delete the fork, ending on the
      theme and background it started on. Mark desktop-dependent checks
      (grim, hyprctl) and skip them cleanly when headless. Per-check
      PASS/FAIL lines, non-zero exit on any failure, and it must leave
      `git status` clean here and in ~/dotfiles.
      **Done when:** `tests/run` passes twice in a row on this machine, the
      desktop ends as it began (verify theme and background, don't assume),
      and the "How to test" section above points to it.

## Task 12 — Ship the tool

- [ ] **12a. Style backlog.** Clear the ~89-item pre-existing QML review
      backlog (ORD-1 ordering, `var`/`==`, …) with the qt-qml-review lint
      script until the repo lints clean or each remaining item is
      individually justified in the commit message. Rerun `tests/run` and a
      full-screen capture of all four panels after.
      **Done when:** the lint script reports zero unjustified findings and
      the app still looks and behaves right in the captures.
- [ ] **12b. README screenshots and a dependency check.** Capture each of
      the four panels (grim, cropped to the window geometry from `hyprctl
      clients`), commit under `docs/`, embed in the README. Make the
      `omatheme` launcher die with a clear message naming any missing
      dependency (qs, magick, jq, omarchy).
      **Done when:** the README renders with images on GitHub (relative
      paths, check after pushing), and the launcher's failure message is
      verified by hiding one dependency from PATH.
- [ ] **12c. Go public.** A final pass over the repo for anything private
      (no secrets, no personal paths in docs), then **stop and ask** —
      flipping `gh repo edit Davies-Sam/omatheme --visibility public` and
      any "PR into Omarchy" follow-up is Sam's call, not the loop's.
      **Done when:** the ask has been made and answered, and whichever
      action Sam chose is done. This is the milestone's natural stopping
      point.

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
