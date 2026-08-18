import QtQuick
import qs.Ui

Rectangle {
  id: root

  property string label: ""
  property bool primary: false
  signal clicked()

  // The inherited Item.enabled is the disable mechanism -- declaring our own
  // bool here would shadow it, leaving the real one stuck on (hover cursor
  // still active, future children still live).
  implicitWidth: text.implicitWidth + Theme.size(28)
  implicitHeight: Theme.size(32)
  radius: Theme.radius
  opacity: root.enabled ? 1 : 0.4

  color: root.primary
    ? Qt.alpha(Theme.accent, area.containsMouse ? 0.30 : 0.20)
    : Qt.alpha(Theme.foreground, area.containsMouse ? 0.12 : 0.06)
  border.width: 1
  border.color: root.primary
    ? Theme.focusRing
    : Theme.hairlineStrong

  Behavior on color { ColorAnimation { duration: 90 } }

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    color: root.primary ? Theme.accent : Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(13)
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
