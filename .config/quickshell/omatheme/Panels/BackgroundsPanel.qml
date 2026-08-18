pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui

// Curate the current theme's background set through omatheme-bg: what the
// theme ships is authoring and lives here; cycling between backgrounds
// stays with Omarchy (SUPER+CTRL+SPACE, `omarchy theme bg next`).
//
// Clicking a thumbnail applies it. Adds accept a local path or an http(s)
// URL; for a user-owned theme they land in the theme's own backgrounds/ so
// a published fork carries them. Stock-shipped files can't be removed --
// the helper refuses, and the button greys out.
ColumnLayout {
  id: root

  property var backgrounds: []   // [{ name, path, source, removable, current }]
  property bool owned: false
  property string selected: ""
  property string status: ""     // helper stderr, surfaced like the fork error

  spacing: Theme.gap

  readonly property var selectedEntry: {
    for (var i = 0; i < backgrounds.length; i++)
      if (backgrounds[i].name === selected) return backgrounds[i]
    return null
  }

  // ------------------------------------------------------------ processes
  Process {
    id: loader
    command: ["omatheme-bg", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  function applyState(json) {
    try {
      var state = JSON.parse(json)
      root.backgrounds = state.backgrounds || []
      root.owned = state.owned === true
      if (!root.selectedEntry) {
        var current = root.backgrounds.find(entry => entry.current)
        root.selected = current ? current.name
          : (root.backgrounds.length > 0 ? root.backgrounds[0].name : "")
      }
    } catch (error) {
      console.warn("omatheme: could not read background state:", error)
    }
  }

  // Same queue pattern as the other panels: a Process must never be
  // retriggered while running, and the re-read is driven by its exit.
  Process {
    id: applier
    property var pending: null
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.status = text.trim()
    }
    onExited: {
      if (pending) {
        command = pending
        pending = null
        running = true
        return
      }
      loader.running = true
    }
  }

  function runApplier(cmd) {
    root.status = ""
    if (applier.running) applier.pending = cmd
    else {
      applier.command = cmd
      applier.running = true
    }
  }

  function setBackground(name) {
    root.selected = name
    runApplier(["omatheme-bg", "set", name])
  }

  function add(arg) {
    if (arg.length === 0) return
    runApplier(["omatheme-bg", "add", arg])
  }

  function removeSelected() {
    if (root.selectedEntry && root.selectedEntry.removable)
      runApplier(["omatheme-bg", "remove", root.selected])
  }

  // Palette generation is heuristic, so the human stays in the loop: the
  // proposal lands in the Palette panel as pending edits (nothing on disk)
  // and the user eyeballs the swatches before pressing Preview there.
  Process {
    id: generator
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          Session.paletteProposed(JSON.parse(text))
          Session.panelRequested("palette")
        } catch (error) {
          root.status = "palette generation produced no usable result"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim().length > 0) root.status = text.trim()
    }
  }

  function generatePalette() {
    if (generator.running || !root.selectedEntry) return
    root.status = ""
    generator.command = ["omatheme-palette", "generate", root.selectedEntry.path]
    generator.running = true
  }

  Component.onCompleted: loader.running = true

  // ------------------------------------------------------------------- ui
  GridLayout {
    Layout.fillWidth: true
    columns: 3
    columnSpacing: Theme.size(6)
    rowSpacing: Theme.size(6)

    Repeater {
      model: root.backgrounds

      Rectangle {
        id: cell

        required property var modelData

        Layout.fillWidth: true
        Layout.preferredHeight: Theme.size(74)
        color: Theme.sunken
        border.width: cell.modelData.current ? 2 : 1
        border.color: cell.modelData.current ? Theme.accent
          : (root.selected === cell.modelData.name ? Theme.focusRing : Theme.hairline)

        // 4K wallpapers: decode a thumbnail off the UI thread, never the
        // full image.
        Image {
          anchors.fill: parent
          anchors.margins: 1
          source: "file://" + cell.modelData.path
          sourceSize.width: 320
          asynchronous: true
          fillMode: Image.PreserveAspectCrop
          clip: true
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.setBackground(cell.modelData.name)
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: root.selectedEntry !== null
    text: root.selected + (root.selectedEntry && !root.selectedEntry.removable
      ? "  (shipped by the stock theme)" : "")
    color: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(12)
    font.bold: true
    elide: Text.ElideRight
  }

  Item { Layout.fillHeight: true }

  RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Field {
      id: addField
      Layout.fillWidth: true
      placeholder: "path or https://… image link"
    }

    TextButton {
      label: "Add"
      enabled: addField.text.trim().length > 0
      onClicked: {
        root.add(addField.text.trim())
        addField.text = ""
      }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: root.status.length > 0
    textFormat: Text.PlainText
    text: root.status
    color: Theme.value("red", "#f7768e")
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(11)
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    text: "Added images go to this theme's own set. Cycling stays on SUPER + CTRL + SPACE."
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(11)
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 8

    TextButton {
      label: "Remove"
      enabled: root.selectedEntry !== null && root.selectedEntry.removable
      onClicked: root.removeSelected()
    }

    TextButton {
      label: "Palette from this background"
      enabled: root.selectedEntry !== null
      onClicked: root.generatePalette()
    }

    Item { Layout.fillWidth: true }
  }
}
