import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui

// Omaborder -- window border designer for Omarchy Quattro.
//
// Quattro derives every border from the active theme's colors.toml, so this
// edits `hyprland_active_border` / `hyprland_inactive_border` there (via
// omaborder-theme) rather than writing Hyprland config directly. That single
// key is what the bar, notifications and lock screen read too, so a change
// lands everywhere at once.
//
// While you drag, the border is pushed straight into the running compositor
// with `hyprctl eval`. Quattro's Lua parser rejects `hyprctl keyword`, so eval
// is the only live path. Nothing is written until Apply; Revert drops the
// live overrides with a plain config reload.
ShellRoot {
  id: root

  // ---------------------------------------------------------------- state
  property string themeName: "…"
  property bool themeEditable: true
  property string editing: "active"          // which border the controls drive
  property string stop: "a"                  // which gradient stop is selected
  property bool dirty: false
  property bool loaded: false

  property var active: ({ gradient: true, a: "#33ccff", aAlpha: 0.93, b: "#00ff99", bAlpha: 0.93, angle: 45 })
  property var inactive: ({ gradient: false, a: "#595959", aAlpha: 0.67, b: "#595959", bAlpha: 0.67, angle: 45 })

  readonly property var current: editing === "active" ? active : inactive

  // ------------------------------------------------------------ spec I/O
  //
  // Hyprland writes colours as rgba(RRGGBBAA); a gradient is two of them plus
  // an angle. Both directions live here so the parser and the serialiser
  // can't drift apart.

  function toHex2(v) {
    var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
    return s.length < 2 ? "0" + s : s
  }

  function rgbaLiteral(hex, alpha) {
    return "rgba(" + hex.replace("#", "") + toHex2(alpha) + ")"
  }

  function specString(spec) {
    var first = rgbaLiteral(spec.a, spec.aAlpha)
    if (!spec.gradient) return first
    return first + " " + rgbaLiteral(spec.b, spec.bAlpha) + " " + Math.round(spec.angle) + "deg"
  }

  function specLua(spec) {
    var first = '"' + rgbaLiteral(spec.a, spec.aAlpha) + '"'
    if (!spec.gradient) return first
    return '{ colors = { ' + first + ', "' + rgbaLiteral(spec.b, spec.bAlpha) + '" }, angle = ' + Math.round(spec.angle) + ' }'
  }

  function parseSpec(text, fallback) {
    if (!text) return fallback

    var found = []
    var pattern = /(?:rgba|rgb)\(\s*([0-9a-fA-F]{6,8})\s*\)|#([0-9a-fA-F]{6,8})/g
    var match
    while ((match = pattern.exec(text)) !== null) found.push(match[1] || match[2])
    if (found.length === 0) return fallback

    function hexOf(raw) { return "#" + raw.substring(0, 6).toLowerCase() }
    function alphaOf(raw) { return raw.length >= 8 ? parseInt(raw.substring(6, 8), 16) / 255 : 1 }

    var degrees = /(-?\d+(?:\.\d+)?)\s*deg/.exec(text)
    return {
      gradient: found.length > 1,
      a: hexOf(found[0]),
      aAlpha: alphaOf(found[0]),
      b: hexOf(found[found.length > 1 ? 1 : 0]),
      bAlpha: alphaOf(found[found.length > 1 ? 1 : 0]),
      angle: degrees ? Math.round(parseFloat(degrees[1])) : 45
    }
  }

  // ------------------------------------------------------------- mutation
  function mutate(changes) {
    var next = {}
    var source = root.current
    for (var key in source) next[key] = source[key]
    for (var change in changes) next[change] = changes[change]

    if (root.editing === "active") root.active = next
    else root.inactive = next

    root.dirty = true
    preview.restart()
  }

  function setStopColor(value, alpha) {
    var hex = value.toString().substring(0, 7)
    mutate(root.stop === "a" ? { a: hex, aAlpha: alpha } : { b: hex, bAlpha: alpha })
  }

  // ------------------------------------------------------------ processes
  Process {
    id: loader
    command: ["omaborder-theme", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  function applyState(json) {
    try {
      var state = JSON.parse(json)
      Theme.colors = state.palette || ({})
      root.themeName = state.name || "Unknown"
      root.themeEditable = state.editable !== false
      root.active = parseSpec(state.active, root.active)
      root.inactive = parseSpec(state.inactive, root.inactive)
      root.dirty = false
      root.loaded = true
    } catch (error) {
      console.warn("omaborder: could not read theme state:", error)
      root.loaded = true
    }
  }

  Process { id: applier }
  Process { id: reverter; command: ["hyprctl", "reload"] }

  // Repainting the compositor on every slider pixel is wasteful; one frame of
  // coalescing is imperceptible and keeps hyprctl calls down.
  Timer {
    id: preview
    interval: 40
    onTriggered: {
      livePreview.command = ["hyprctl", "eval",
        "hl.config({ general = { col = { active_border = " + root.specLua(root.active) +
        ", inactive_border = " + root.specLua(root.inactive) +
        " } }, group = { col = { border_active = " + root.specLua(root.active) +
        ", border_inactive = " + root.specLua(root.inactive) + " } } })"]
      livePreview.running = true
    }
  }

  Process { id: livePreview }

  function apply() {
    applier.command = ["omaborder-theme", "set",
                       "--active", specString(root.active),
                       "--inactive", specString(root.inactive)]
    applier.running = true
    root.dirty = false
  }

  function revert() {
    reverter.running = true
    loader.running = true
  }

  function resetToTheme() {
    applier.command = ["omaborder-theme", "reset", "--all"]
    applier.running = true
    root.dirty = false
    reloadAfterApply.restart()
  }

  // `omarchy theme set` regenerates and reloads config; re-read once it has.
  Timer {
    id: reloadAfterApply
    interval: 600
    onTriggered: loader.running = true
  }

  Component.onCompleted: loader.running = true

  // ------------------------------------------------------------------ ui
  FloatingWindow {
    id: window

    title: "Omaborder"
    implicitWidth: 460
    implicitHeight: 566
    minimumSize: Qt.size(420, 520)
    color: Theme.background

    onVisibleChanged: if (!visible) Quickshell.quit()

    Item {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: { root.revert(); Quickshell.quit() }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: Theme.gap

        // ---- header
        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: "Window border"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 17
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          Rectangle {
            implicitWidth: themeLabel.implicitWidth + 18
            implicitHeight: 24
            radius: Theme.radius
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)

            Text {
              id: themeLabel
              anchors.centerIn: parent
              text: root.themeName
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: 11
            }
          }
        }

        // ---- preview / target picker
        RowLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: 112
          Layout.maximumHeight: 112
          spacing: 12

          BorderPreview {
            Layout.fillWidth: true
            Layout.fillHeight: true
            caption: "Focused"
            colorA: Qt.rgba(Qt.color(root.active.a).r, Qt.color(root.active.a).g, Qt.color(root.active.a).b, root.active.aAlpha)
            colorB: Qt.rgba(Qt.color(root.active.b).r, Qt.color(root.active.b).g, Qt.color(root.active.b).b, root.active.bAlpha)
            gradient: root.active.gradient
            angle: root.active.angle
            selected: root.editing === "active"
            onClicked: { root.editing = "active"; root.stop = "a" }
          }

          BorderPreview {
            Layout.fillWidth: true
            Layout.fillHeight: true
            caption: "Unfocused"
            colorA: Qt.rgba(Qt.color(root.inactive.a).r, Qt.color(root.inactive.a).g, Qt.color(root.inactive.a).b, root.inactive.aAlpha)
            colorB: Qt.rgba(Qt.color(root.inactive.b).r, Qt.color(root.inactive.b).g, Qt.color(root.inactive.b).b, root.inactive.bAlpha)
            gradient: root.inactive.gradient
            angle: root.inactive.angle
            selected: root.editing === "inactive"
            onClicked: { root.editing = "inactive"; root.stop = "a" }
          }
        }

        // ---- solid / gradient
        Segmented {
          Layout.fillWidth: true
          options: [{ key: "solid", label: "Solid" }, { key: "gradient", label: "Gradient" }]
          current: root.current.gradient ? "gradient" : "solid"
          onSelected: key => {
            root.mutate({ gradient: key === "gradient" })
            if (key === "solid") root.stop = "a"
          }
        }

        // ---- stop picker, only meaningful for a gradient
        Segmented {
          Layout.fillWidth: true
          visible: root.current.gradient
          options: [{ key: "a", label: "From" }, { key: "b", label: "To" }]
          current: root.stop
          onSelected: key => root.stop = key
        }

        // ---- colour
        ColorEditor {
          Layout.fillWidth: true
          value: root.stop === "a" ? root.current.a : root.current.b
          alpha: root.stop === "a" ? root.current.aAlpha : root.current.bAlpha
          onChanged: (value, alpha) => root.setStopColor(value, alpha)
        }

        // ---- angle
        LabeledSlider {
          Layout.fillWidth: true
          visible: root.current.gradient
          label: "Angle"
          from: 0
          to: 360
          value: root.current.angle
          readout: Math.round(root.current.angle) + "°"
          trackStops: [
            GradientStop { position: 0.0; color: Qt.color(root.current.a) },
            GradientStop { position: 1.0; color: Qt.color(root.current.b) }
          ]
          onMoved: v => root.mutate({ angle: Math.round(v) })
        }

        Item { Layout.fillHeight: true }

        Text {
          Layout.fillWidth: true
          visible: !root.themeEditable
          text: "Applying creates a user overlay for this stock theme."
          color: Theme.dim
          font.family: Theme.fontFamily
          font.pixelSize: 11
          wrapMode: Text.WordWrap
        }

        // ---- actions
        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          TextButton {
            label: "Theme default"
            onClicked: root.resetToTheme()
          }

          Item { Layout.fillWidth: true }

          TextButton {
            label: "Revert"
            enabled: root.dirty
            onClicked: root.revert()
          }

          TextButton {
            label: "Apply"
            primary: true
            enabled: root.dirty
            onClicked: root.apply()
          }
        }
      }
    }
  }
}
