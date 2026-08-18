pragma ComponentBehavior: Bound

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
  color: Theme.fieldFill
  border.width: 1
  border.color: Theme.hairline

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.margins: 4
    spacing: 4

    Repeater {
      model: root.options

      Rectangle {
        id: segment

        required property var modelData

        // Without an intrinsic size the whole pill's implicit width collapses
        // to its spacing; derive it from the label so the component also
        // works outside a fillWidth cell.
        implicitWidth: segmentLabel.implicitWidth + Theme.size(20)
        implicitHeight: segmentLabel.implicitHeight + Theme.size(8)
        radius: Theme.radius - 2
        color: segment.modelData.key === root.current
          ? Qt.alpha(Theme.accent, 0.22)
          : (segmentArea.containsMouse ? Qt.alpha(Theme.foreground, 0.08) : "transparent")
        Layout.fillWidth: true
        Layout.fillHeight: true

        Behavior on color { ColorAnimation { duration: 90 } }

        Text {
          id: segmentLabel
          anchors.centerIn: parent
          text: segment.modelData.label
          color: segment.modelData.key === root.current ? Theme.foreground : Theme.dim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.size(12)
        }

        MouseArea {
          id: segmentArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selected(segment.modelData.key)
        }
      }
    }
  }
}
