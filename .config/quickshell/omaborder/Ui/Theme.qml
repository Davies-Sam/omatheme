pragma Singleton

import QtQuick

// The app's own chrome is painted from the theme it edits, so it looks like
// the rest of the desktop and re-skins itself the moment a theme is applied.
// `colors` is the raw colors.toml map handed over by omaborder-theme.
QtObject {
  id: root

  property var colors: ({})

  function value(key, fallback) {
    var found = root.colors ? root.colors[key] : undefined
    return (found && String(found).length > 0) ? found : fallback
  }

  readonly property color background: value("background", "#16161e")
  readonly property color surface: value("lighter_background", "#22242e")
  readonly property color sunken: value("dark_background", "#101014")
  readonly property color foreground: value("foreground", "#c8ccd8")
  readonly property color dim: value("dark_foreground", "#7a8096")
  readonly property color accent: value("accent", "#7aa2f7")
  readonly property color selection: value("selection", "#33467c")

  readonly property int radius: 8
  readonly property int gap: 14
  // Set from `omarchy font current` so the app matches the rest of the
  // desktop rather than pinning a family that may not even be installed.
  property string fontFamily: "monospace"
}
