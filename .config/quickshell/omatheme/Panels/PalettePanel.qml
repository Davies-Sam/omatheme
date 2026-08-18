pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui

// The palette: every color key of the active theme's colors.toml, edited
// through omatheme-palette.
//
// Unlike the other panels there is no live-on-drag preview: applying a
// palette means `omarchy theme set`, which regenerates 20+ files (~0.5s) --
// fine for a button, hopeless for every slider pixel. Edits collect locally
// and an explicit Preview writes and applies them. The app paints its own
// chrome from the theme it edits, so a preview that works re-skins this very
// window -- a built-in self-test.
ColumnLayout {
  id: root

  property var colors: ({})      // key -> hex, as read from the theme
  property var edits: ({})       // key -> hex, pending until Preview
  property var keys: []
  property string selected: ""
  property bool hasStock: false

  // `edits` is only ever replaced wholesale, so this re-evaluates on every
  // change without a hand-synchronized counter to drift out of step.
  readonly property bool dirty: Object.keys(edits).length > 0

  spacing: Theme.gap

  function valueOf(key) {
    return root.edits[key] !== undefined ? root.edits[key] : (root.colors[key] || "#000000")
  }

  function setEdit(key, hex) {
    var next = {}
    for (var k in root.edits) next[k] = root.edits[k]
    if (hex === root.colors[key]) delete next[key]
    else next[key] = hex
    root.edits = next
  }

  // ------------------------------------------------------------ processes
  Process {
    id: loader
    command: ["omatheme-palette", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  function applyState(json) {
    try {
      var state = JSON.parse(json)
      root.colors = state.colors || ({})
      root.keys = Object.keys(root.colors)
      root.hasStock = state.stock === true
      root.edits = ({})
      if (root.keys.indexOf(root.selected) < 0)
        root.selected = root.keys.length > 0 ? root.keys[0] : ""
    } catch (error) {
      console.warn("omatheme: could not read palette state:", error)
    }
  }

  // Setting `command` on a running Process is inert and `running = true` is
  // a no-op, so pressing Preview and then "Stock default" while the first
  // `omarchy theme set` is still regenerating would silently drop the reset.
  // The queue keeps the latest request and replays it on exit; the re-read
  // is driven by the exit itself rather than a wall-clock guess that loses
  // to a slow theme set.
  Process {
    id: applier
    property var pending: null
    onExited: {
      if (pending) {
        command = pending
        pending = null
        running = true
        return
      }
      loader.running = true
      Session.reloaded()
    }
  }

  function runApplier(cmd) {
    if (applier.running) applier.pending = cmd
    else {
      applier.command = cmd
      applier.running = true
    }
  }

  // Fork copies the current theme and switches to the copy, so a stock theme
  // can be a starting point without its overlay accumulating edits. The slug
  // is validated to [a-z0-9-] before it gets near a shell.
  Process {
    id: forker
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.forkError = text.trim()
    }
    onExited: {
      loader.running = true
      Session.reloaded()
    }
  }

  property string forkError: ""

  function fork(slug) {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(slug)) return
    forker.command = ["bash", "-c",
      'omatheme-palette fork "$1" && omarchy theme set "$1"', "fork", slug]
    forker.running = true
  }

  function preview() {
    var command = ["omatheme-palette", "set"]
    for (var key in root.edits) {
      command.push("--" + key)
      command.push(root.edits[key])
    }
    if (command.length === 2) return
    runApplier(command)
  }

  function revert() {
    root.edits = ({})
    loader.running = true
  }

  function resetToStock() {
    runApplier(["omatheme-palette", "reset", "--all"])
    root.edits = ({})
  }

  Component.onCompleted: loader.running = true

  // ------------------------------------------------------------------- ui
  GridLayout {
    Layout.fillWidth: true
    columns: 7
    columnSpacing: Theme.size(6)
    rowSpacing: Theme.size(6)

    Repeater {
      model: root.keys
      Rectangle {
        id: swatch

        required property string modelData

        Layout.fillWidth: true
        Layout.preferredHeight: Theme.size(30)
        radius: Theme.radius
        color: root.valueOf(swatch.modelData)
        border.width: root.selected === swatch.modelData ? 2 : 1
        border.color: root.selected === swatch.modelData
          ? Theme.accent
          : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.25)

        // A pending, un-previewed edit gets a marker so it can be spotted
        // after tabbing around the grid.
        Rectangle {
          visible: root.edits[swatch.modelData] !== undefined
          width: Theme.size(6)
          height: width
          radius: width / 2
          anchors { top: parent.top; right: parent.right; margins: Theme.size(3) }
          color: Theme.accent
          border.width: 1
          border.color: Theme.background
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selected = swatch.modelData
        }
      }
    }
  }

  Text {
    Layout.fillWidth: true
    text: root.selected + (root.edits[root.selected] !== undefined ? "  (edited)" : "")
    color: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(12)
    font.bold: true
    elide: Text.ElideRight
  }

  ColorEditor {
    Layout.fillWidth: true
    showAlpha: false
    value: root.valueOf(root.selected)
    onChanged: (value, alpha) => root.setEdit(root.selected, value.toString().substring(0, 7))
  }

  Item { Layout.fillHeight: true }

  RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Theme.size(30)
      radius: Theme.radius
      color: Qt.rgba(Theme.sunken.r, Theme.sunken.g, Theme.sunken.b, 0.8)
      border.width: 1
      border.color: forkName.activeFocus
        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
        : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.15)

      TextInput {
        id: forkName
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.size(13)
        selectByMouse: true
        selectionColor: Theme.selection
        maximumLength: 40
      }

      Text {
        visible: forkName.text.length === 0 && !forkName.activeFocus
        anchors.fill: forkName
        verticalAlignment: Text.AlignVCenter
        text: "new-theme-name"
        color: Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.size(13)
      }
    }

    TextButton {
      label: "Fork"
      enabled: /^[a-z0-9][a-z0-9-]*$/.test(forkName.text)
      onClicked: { root.fork(forkName.text); forkName.text = "" }
    }
  }

  Text {
    Layout.fillWidth: true
    visible: root.forkError.length > 0
    // Raw helper stderr: AutoText would sniff <tags> or & as styled text
    // and mangle exactly the message a failing fork needs to show verbatim.
    textFormat: Text.PlainText
    text: root.forkError
    color: Theme.value("red", "#f7768e")
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(11)
    wrapMode: Text.WordWrap
  }

  Text {
    Layout.fillWidth: true
    text: "No live preview here: applying a palette regenerates the whole theme, so press Preview to see it."
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(11)
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 8

    TextButton {
      label: "Stock default"
      enabled: root.hasStock
      onClicked: root.resetToStock()
    }

    Item { Layout.fillWidth: true }

    TextButton {
      label: "Revert"
      enabled: root.dirty
      onClicked: root.revert()
    }

    TextButton {
      label: "Preview"
      primary: true
      enabled: root.dirty
      onClicked: root.preview()
    }
  }
}
