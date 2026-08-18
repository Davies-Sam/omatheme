pragma Singleton

import QtQuick

// Shared session state: which theme the app is editing right now. Panels read
// it rather than each shelling out for the same answer, and any panel that
// writes a theme calls reloaded() so the rest of the app re-reads.
QtObject {
  id: root

  // The plugin's bundled helpers, by absolute path: inside omarchy-shell
  // nothing puts bin/ on PATH, so every Process command resolves its
  // executable through here. Anchored to this file's location (Ui/).
  readonly property string binDir: {
    const url = Qt.resolvedUrl("../bin/").toString()
    return url.startsWith("file://") ? decodeURIComponent(url.substring(7)) : url
  }
  function bin(name) { return binDir + name }

  property string slug: ""
  property string name: "…"

  // False means the current theme is a stock one, and writing to it will
  // create a user overlay first.
  property bool editable: true
  property bool ready: false

  signal reloaded()

  // Cross-panel handoffs, since panels are self-contained and never talk to
  // each other directly: a generated palette proposal ({ mode, colors }) for
  // the Palette panel to stage as pending edits, and a request for the shell
  // to switch tabs.
  signal paletteProposed(var proposal)
  signal panelRequested(string key)
}
