import QtQuick
import QtQuick.Layouts
import qs.Ui

// Edits one colour stop: hex in, HSV + alpha sliders out. The component is
// stateless -- it reports every change and re-reads whatever it is given.
ColumnLayout {
  id: root

  property color value: "#ffffff"
  property real alpha: 1.0
  // Palette colors are plain #rrggbb; hide the alpha row where it has no
  // meaning rather than letting it edit a channel that is thrown away.
  property bool showAlpha: true

  // Qt reports hue as -1 for greys; holding the last real hue keeps the
  // slider from jumping to red when saturation hits zero. The gesture also
  // has to lead its own echo: an emitted color comes back through the parent
  // quantized to 8-bit RGB, which jitters the hue at low saturation -- and
  // on greys never comes back at all (equal colors fire no change signal),
  // which used to leave the hue slider dead. So the slider writes `hue`
  // directly and the echo of our own emission is ignored.
  property real hue: 0
  property string lastEmitted: ""

  signal changed(color value, real alpha)

  spacing: 10

  onValueChanged: {
    if (value.toString() === root.lastEmitted) return
    if (value.hsvHue >= 0) hue = value.hsvHue
  }

  function emit(h, s, v, a) {
    const next = Qt.hsva(Math.max(0, Math.min(0.99999, h)),
                       Math.max(0, Math.min(1, s)),
                       Math.max(0, Math.min(1, v)), 1)
    root.lastEmitted = next.toString()
    root.changed(next, a)
  }

  RowLayout {
    spacing: 10
    Layout.fillWidth: true

    Rectangle {
      radius: Theme.radius
      color: root.value
      border.width: 1
      border.color: Theme.hairlineStrong
      Layout.preferredWidth: Theme.size(30)
      Layout.preferredHeight: Theme.size(30)
    }

    HexField {
      value: root.value.toString().substring(0, 7)
      onEdited: hex => root.changed(hex, root.alpha)
    }

    Item { Layout.fillWidth: true }
  }

  LabeledSlider {
    label: "Hue"
    value: root.hue
    readout: Math.round(root.hue * 360) + "°"
    trackStops: [
      GradientStop { position: 0.00; color: "#ff0000" },
      GradientStop { position: 0.17; color: "#ffff00" },
      GradientStop { position: 0.33; color: "#00ff00" },
      GradientStop { position: 0.50; color: "#00ffff" },
      GradientStop { position: 0.67; color: "#0000ff" },
      GradientStop { position: 0.83; color: "#ff00ff" },
      GradientStop { position: 1.00; color: "#ff0000" }
    ]
    Layout.fillWidth: true
    onMoved: v => {
      root.hue = v
      root.emit(v, root.value.hsvSaturation, root.value.hsvValue, root.alpha)
    }
  }

  LabeledSlider {
    label: "Sat"
    value: root.value.hsvSaturation
    readout: Math.round(root.value.hsvSaturation * 100) + "%"
    trackStops: [
      GradientStop { position: 0.0; color: Qt.hsva(root.hue, 0, root.value.hsvValue, 1) },
      GradientStop { position: 1.0; color: Qt.hsva(root.hue, 1, root.value.hsvValue, 1) }
    ]
    Layout.fillWidth: true
    onMoved: v => root.emit(root.hue, v, root.value.hsvValue, root.alpha)
  }

  LabeledSlider {
    label: "Val"
    value: root.value.hsvValue
    readout: Math.round(root.value.hsvValue * 100) + "%"
    trackStops: [
      GradientStop { position: 0.0; color: "#000000" },
      GradientStop { position: 1.0; color: Qt.hsva(root.hue, root.value.hsvSaturation, 1, 1) }
    ]
    Layout.fillWidth: true
    onMoved: v => root.emit(root.hue, root.value.hsvSaturation, v, root.alpha)
  }

  LabeledSlider {
    visible: root.showAlpha
    label: "Alpha"
    value: root.alpha
    readout: Math.round(root.alpha * 100) + "%"
    trackStops: [
      GradientStop { position: 0.0; color: Qt.alpha(root.value, 0) },
      GradientStop { position: 1.0; color: Qt.alpha(root.value, 1) }
    ]
    Layout.fillWidth: true
    onMoved: v => root.changed(root.value, v)
  }
}
