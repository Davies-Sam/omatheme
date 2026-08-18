import QtQuick
import QtQuick.Layouts
import qs.Ui

// Two-or-more mutually exclusive options rendered as one pill.
Rectangle {
  id: root

  property var options: []          // [{ key, label }]
  property string current: ""
  signal selected(string key)

  implicitHeight: Theme.size(30)
  implicitWidth: row.implicitWidth + Theme.size(8)
  radius: Theme.radius
  color: Qt.rgba(Theme.sunken.r, Theme.sunken.g, Theme.sunken.b, 0.8)
  border.width: 1
  border.color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.15)

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.margins: 4
    spacing: 4

    Repeater {
      model: root.options

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radius - 2
        color: modelData.key === root.current
          ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
          : (segmentArea.containsMouse ? Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.08) : "transparent")

        Behavior on color { ColorAnimation { duration: 90 } }

        Text {
          anchors.centerIn: parent
          text: parent.modelData.label
          color: parent.modelData.key === root.current ? Theme.foreground : Theme.dim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.size(12)
        }

        MouseArea {
          id: segmentArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selected(parent.modelData.key)
        }
      }
    }
  }
}
