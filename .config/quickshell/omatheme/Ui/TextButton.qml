import QtQuick
import qs.Ui

Rectangle {
  id: root

  property string label: ""
  property bool primary: false
  property bool enabled: true
  signal clicked()

  implicitWidth: text.implicitWidth + Theme.size(28)
  implicitHeight: Theme.size(32)
  radius: Theme.radius
  opacity: root.enabled ? 1 : 0.4

  color: root.primary
    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, area.containsMouse ? 0.30 : 0.20)
    : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, area.containsMouse ? 0.12 : 0.06)
  border.width: 1
  border.color: root.primary
    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
    : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.25)

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
    enabled: root.enabled
    onClicked: root.clicked()
  }
}
