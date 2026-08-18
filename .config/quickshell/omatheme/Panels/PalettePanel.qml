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
  property int editCount: 0

  readonly property bool dirty: editCount > 0

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
    root.editCount = Object.keys(next).length
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
      root.editCount = 0
      if (root.keys.indexOf(root.selected) < 0)
        root.selected = root.keys.length > 0 ? root.keys[0] : ""
    } catch (error) {
      console.warn("omatheme: could not read palette state:", error)
    }
  }

  Process { id: applier }

  // `omarchy theme set` regenerates and reloads config; re-read once it has.
  Timer {
    id: settle
    interval: 600
    onTriggered: { loader.running = true; Session.reloaded() }
  }

  function preview() {
    var command = ["omatheme-palette", "set"]
    for (var key in root.edits) {
      command.push("--" + key)
      command.push(root.edits[key])
    }
    if (command.length === 2) return
    applier.command = command
    applier.running = true
    settle.restart()
  }

  function revert() {
    root.edits = ({})
    root.editCount = 0
    loader.running = true
  }

  function resetToStock() {
    applier.command = ["omatheme-palette", "reset", "--all"]
    applier.running = true
    root.edits = ({})
    root.editCount = 0
    settle.restart()
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
        required property string modelData

        Layout.fillWidth: true
        Layout.preferredHeight: Theme.size(30)
        radius: Theme.radius
        color: root.valueOf(modelData)
        border.width: root.selected === modelData ? 2 : 1
        border.color: root.selected === modelData
          ? Theme.accent
          : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.25)

        // A pending, un-previewed edit gets a marker so it can be spotted
        // after tabbing around the grid.
        Rectangle {
          visible: root.edits[parent.modelData] !== undefined
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
          onClicked: root.selected = parent.modelData
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
