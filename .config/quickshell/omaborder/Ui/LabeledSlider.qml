import QtQuick
import QtQuick.Layouts
import qs.Ui

// A labelled slider whose track can paint an arbitrary gradient, so the hue
// and saturation rows preview the value they are about to set.
RowLayout {
  id: root

  property string label: ""
  property real from: 0
  property real to: 1
  property real value: 0
  property string readout: ""
  property list<GradientStop> trackStops
  signal moved(real value)

  spacing: 10

  Text {
    text: root.label
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: 11
    Layout.preferredWidth: 34
  }

  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 20

    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 8
      radius: 4
      color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.12)

      // A horizontal gradient needs an explicit rotation; without stops the
      // flat fill above shows through.
      gradient: root.trackStops.length > 0 ? trackGradient : null

      Gradient {
        id: trackGradient
        orientation: Gradient.Horizontal
        stops: root.trackStops
      }
    }

    Rectangle {
      id: handle
      width: 14
      height: 14
      radius: 7
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(1, (root.value - root.from) / Math.max(0.0001, root.to - root.from))) * (track.width - width)
      color: Theme.foreground
      border.width: 2
      border.color: Theme.background
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor

      function commit(mouseX) {
        var ratio = Math.max(0, Math.min(1, (mouseX - handle.width / 2) / Math.max(1, track.width - handle.width)))
        root.moved(root.from + ratio * (root.to - root.from))
      }

      onPressed: mouse => commit(mouse.x)
      onPositionChanged: mouse => { if (pressed) commit(mouse.x) }
    }
  }

  Text {
    text: root.readout
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: 11
    horizontalAlignment: Text.AlignRight
    Layout.preferredWidth: 38
  }
}
