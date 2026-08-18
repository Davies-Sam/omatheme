import QtQuick
import QtQuick.Controls
import qs.Ui

// Hex entry that only reports colors Qt can actually parse, so a half-typed
// value never reaches the compositor.
Rectangle {
  id: root

  property string value: "#000000"
  signal edited(string hex)

  implicitWidth: Theme.size(104)
  implicitHeight: Theme.size(30)
  radius: Theme.radius
  color: Qt.rgba(Theme.sunken.r, Theme.sunken.g, Theme.sunken.b, 0.8)
  border.width: 1
  border.color: input.activeFocus
    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
    : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.15)

  TextInput {
    id: input
    anchors.fill: parent
    anchors.leftMargin: 10
    anchors.rightMargin: 10
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(13)
    selectByMouse: true
    selectionColor: Theme.selection
    maximumLength: 7
    text: root.value

    // Only overwrite while the user is elsewhere; retyping shouldn't fight
    // the binding.
    Connections {
      target: root
      function onValueChanged() {
        if (!input.activeFocus) input.text = root.value
      }
    }

    onTextChanged: {
      if (/^#[0-9a-fA-F]{6}$/.test(text) && text.toLowerCase() !== root.value.toLowerCase())
        root.edited(text.toLowerCase())
    }

    onEditingFinished: input.text = root.value
  }
}
