import QtQuick
import qs.Ui

// The text-field chrome every field shares: sunken fill, hairline border,
// focus ring, optional placeholder. HexField layers hex validation on top;
// the palette's fork-name field uses it directly.
Rectangle {
  id: root

  property alias text: input.text
  property alias maximumLength: input.maximumLength
  readonly property alias input: input
  property string placeholder: ""
  signal editingFinished()

  implicitWidth: Theme.size(104)
  implicitHeight: Theme.size(30)
  radius: Theme.radius
  color: Theme.fieldFill
  border.width: 1
  border.color: input.activeFocus ? Theme.focusRing : Theme.hairline

  TextInput {
    id: input
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(13)
    selectByMouse: true
    selectionColor: Theme.selection
    onEditingFinished: root.editingFinished()
    anchors {
      fill: parent
      leftMargin: 10
      rightMargin: 10
    }
  }

  Text {
    visible: root.placeholder.length > 0 && input.text.length === 0 && !input.activeFocus
    anchors.fill: input
    verticalAlignment: Text.AlignVCenter
    text: root.placeholder
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(13)
  }
}
