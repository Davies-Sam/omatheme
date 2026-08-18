import QtQuick
import qs.Ui

// A mock window drawn with the border being edited. Qt gradients are axis
// aligned, so the angle is faked the way Hyprland renders it: an oversized
// gradient plane rotated behind a clipping frame, with the window fill laid
// back over the middle. Clicking the mock selects it for editing, which makes
// the preview double as the active/inactive picker.
Rectangle {
  id: root

  property color colorA: "#ffffff"
  property color colorB: "#ffffff"
  property bool gradient: false
  property real angle: 45
  property int borderWidth: 3
  property string caption: ""
  property bool selected: false
  signal clicked()

  radius: 10
  clip: true
  color: "transparent"

  // Gradient plane: sized to the diagonal so no corner is left unpainted at
  // any rotation.
  Rectangle {
    anchors.centerIn: parent
    width: Math.sqrt(root.width * root.width + root.height * root.height)
    height: width
    rotation: -root.angle
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: root.colorA }
      GradientStop { position: 1.0; color: root.gradient ? root.colorB : root.colorA }
    }
  }

  // Window fill, inset by the border width.
  Rectangle {
    anchors.fill: parent
    anchors.margins: root.borderWidth
    radius: Math.max(0, root.radius - root.borderWidth)
    color: Theme.background

    Column {
      anchors.centerIn: parent
      spacing: 6

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.caption
        color: root.selected ? Theme.foreground : Theme.dim
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 22
        height: 2
        radius: 1
        opacity: root.selected ? 1 : 0
        color: Theme.accent
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
