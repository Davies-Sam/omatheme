pragma Singleton

import QtQuick

// The app's own chrome is painted from the theme it edits, so it looks like
// the rest of the desktop and re-skins itself the moment a theme is applied.
// `colors` is the raw colors.toml map handed over by omaborder-theme.
QtObject {
  id: root

  property var colors: ({})

  function value(key, fallback) {
    const found = root.colors ? root.colors[key] : undefined
    return (found && String(found).length > 0) ? found : fallback
  }

  readonly property color background: value("background", "#16161e")
  readonly property color surface: value("lighter_background", "#22242e")
  readonly property color sunken: value("dark_background", "#101014")
  readonly property color foreground: value("foreground", "#c8ccd8")
  readonly property color dim: value("dark_foreground", "#7a8096")
  readonly property color accent: value("accent", "#7aa2f7")
  readonly property color selection: value("selection", "#33467c")

  // The recurring tint vocabulary, named once: hairlines around fields and
  // swatches, sunken field fills, and the ring on a focused field.
  readonly property color hairline: Qt.alpha(foreground, 0.15)
  readonly property color hairlineStrong: Qt.alpha(foreground, 0.25)
  readonly property color fieldFill: Qt.alpha(sunken, 0.8)
  readonly property color focusRing: Qt.alpha(accent, 0.7)

  // GNOME's text-scaling-factor, as set by `omarchy display text size`.
  // Every size in the app goes through size(), so the whole window grows
  // with it rather than the text alone overflowing fixed chrome.
  property real textScale: 1.0

  function size(value) {
    return Math.round(value * root.textScale)
  }

  readonly property int radius: size(8)
  readonly property int gap: size(14)
  // Set from `omarchy font current` so the app matches the rest of the
  // desktop rather than pinning a family that may not even be installed.
  property string fontFamily: "monospace"
}
