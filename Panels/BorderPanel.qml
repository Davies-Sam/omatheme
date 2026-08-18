import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Ui"

// Window border: the colours Hyprland draws around focused and unfocused
// windows.
//
// Quattro derives every border from the active theme's colors.toml
// (`hyprland_active_border` / `hyprland_inactive_border`), so this edits that
// -- through omatheme-border -- rather than writing Hyprland config. The same
// key feeds the bar, notifications and the lock screen, so a change lands
// everywhere at once.
//
// While you drag, the border is pushed into the running compositor with
// `hyprctl eval`; Quattro's Lua parser rejects `hyprctl keyword`, so eval is
// the only live path. Nothing is written until Apply.
ColumnLayout {
  id: root

  property string editing: "active"   // which border the controls drive
  property string stop: "a"           // which gradient stop is selected
  property bool dirty: false

  property var active: ({ gradient: true, a: "#33ccff", aAlpha: 0.93, b: "#00ff99", bAlpha: 0.93, angle: 45 })
  property var inactive: ({ gradient: false, a: "#595959", aAlpha: 0.67, b: "#595959", bAlpha: 0.67, angle: 45 })

  readonly property var current: editing === "active" ? active : inactive

  spacing: Theme.gap

  // ------------------------------------------------------------- spec I/O
  //
  // Hyprland writes colours as rgba(RRGGBBAA); a gradient is two of them plus
  // an angle. Both directions live together so parser and serialiser cannot
  // drift apart.

  function toHex2(value) {
    const hex = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16)
    return hex.length < 2 ? "0" + hex : hex
  }

  function rgbaLiteral(hex, alpha) {
    return "rgba(" + hex.replace("#", "") + toHex2(alpha) + ")"
  }

  function specString(spec) {
    const first = rgbaLiteral(spec.a, spec.aAlpha)
    if (!spec.gradient) return first
    return first + " " + rgbaLiteral(spec.b, spec.bAlpha) + " " + Math.round(spec.angle) + "deg"
  }

  function specLua(spec) {
    const first = '"' + rgbaLiteral(spec.a, spec.aAlpha) + '"'
    if (!spec.gradient) return first
    return '{ colors = { ' + first + ', "' + rgbaLiteral(spec.b, spec.bAlpha) + '" }, angle = ' + Math.round(spec.angle) + ' }'
  }

  function parseSpec(text, fallback) {
    if (!text) return fallback

    const found = []
    const pattern = /(?:rgba|rgb)\(\s*([0-9a-fA-F]{6,8})\s*\)|#([0-9a-fA-F]{6,8})/g
    let match
    while ((match = pattern.exec(text)) !== null) found.push(match[1] || match[2])
    if (found.length === 0) return fallback

    function hexOf(raw) { return "#" + raw.substring(0, 6).toLowerCase() }
    function alphaOf(raw) { return raw.length >= 8 ? parseInt(raw.substring(6, 8), 16) / 255 : 1 }

    const degrees = /(-?\d+(?:\.\d+)?)\s*deg/.exec(text)
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
    const next = {}
    const source = root.current
    for (const key in source) next[key] = source[key]
    for (const change in changes) next[change] = changes[change]

    if (root.editing === "active") root.active = next
    else root.inactive = next

    root.dirty = true
    preview.restart()
  }

  function setStopColor(value, alpha) {
    const hex = value.toString().substring(0, 7)
    mutate(root.stop === "a" ? { a: hex, aAlpha: alpha } : { b: hex, bAlpha: alpha })
  }

  // ------------------------------------------------------------ processes
  Process {
    id: loader
    command: [Session.bin("omatheme-border"), "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  function applyState(json) {
    try {
      const state = JSON.parse(json)
      root.active = parseSpec(state.active, root.active)
      root.inactive = parseSpec(state.inactive, root.inactive)
      root.dirty = false
    } catch (error) {
      console.warn("omatheme: could not read border state:", error)
    }
  }

  // Setting `command` on a running Process is inert and `running = true` is
  // a no-op, so a second action fired mid-apply would silently vanish. The
  // queue keeps the latest request and replays it on exit; the re-read is
  // driven by the exit itself rather than a wall-clock guess that loses to a
  // slow `omarchy theme set`.
  Process {
    id: applier
    property var pending: null
    onExited: {
      if (pending) {
        command = pending
        pending = null
        running = true
        return
      }
      loader.running = true
      Session.reloaded()
    }
  }

  function runApplier(cmd) {
    if (applier.running) applier.pending = cmd
    else {
      applier.command = cmd
      applier.running = true
    }
  }

  Process {
    id: reverter
    command: ["hyprctl", "reload"]
    onExited: loader.running = true
  }

  Process { id: livePreview }

  // Repainting the compositor on every slider pixel is wasteful; one frame of
  // coalescing is imperceptible and keeps hyprctl calls down. If hyprctl is
  // still busy from the previous frame, retry instead of dropping the value
  // -- otherwise the compositor is left showing a stale mid-drag state.
  Timer {
    id: preview
    interval: 40
    onTriggered: {
      if (livePreview.running) {
        preview.restart()
        return
      }
      livePreview.command = ["hyprctl", "eval",
        "hl.config({ general = { col = { active_border = " + root.specLua(root.active) +
        ", inactive_border = " + root.specLua(root.inactive) +
        " } }, group = { col = { border_active = " + root.specLua(root.active) +
        ", border_inactive = " + root.specLua(root.inactive) + " } } })"]
      livePreview.running = true
    }
  }

  function apply() {
    runApplier([Session.bin("omatheme-border"), "set",
                "--active", specString(root.active),
                "--inactive", specString(root.inactive)])
    root.dirty = false
  }

  function revert() {
    reverter.running = true
  }

  function resetToTheme() {
    runApplier([Session.bin("omatheme-border"), "reset", "--all"])
    root.dirty = false
  }

  // Border colors live in colors.toml, so any reload -- a palette apply,
  // or an external theme switch spotted by the shell's state watch --
  // can move them. After this panel's own applies the loader is already
  // running, so the extra nudge is a no-op.
  Connections {
    target: Session
    function onReloaded() { loader.running = true }
  }

  Component.onCompleted: loader.running = true

  // ------------------------------------------------------------------- ui
  RowLayout {
    spacing: 12
    Layout.fillWidth: true
    Layout.preferredHeight: Theme.size(112)
    Layout.maximumHeight: Theme.size(112)

    BorderPreview {
      caption: "Focused"
      colorA: Qt.alpha(root.active.a, root.active.aAlpha)
      colorB: Qt.alpha(root.active.b, root.active.bAlpha)
      twoStop: root.active.gradient
      angle: root.active.angle
      selected: root.editing === "active"
      Layout.fillWidth: true
      Layout.fillHeight: true
      onClicked: { root.editing = "active"; root.stop = "a" }
    }

    BorderPreview {
      caption: "Unfocused"
      colorA: Qt.alpha(root.inactive.a, root.inactive.aAlpha)
      colorB: Qt.alpha(root.inactive.b, root.inactive.bAlpha)
      twoStop: root.inactive.gradient
      angle: root.inactive.angle
      selected: root.editing === "inactive"
      Layout.fillWidth: true
      Layout.fillHeight: true
      onClicked: { root.editing = "inactive"; root.stop = "a" }
    }
  }

  Segmented {
    options: [{ key: "solid", label: "Solid" }, { key: "gradient", label: "Gradient" }]
    current: root.current.gradient ? "gradient" : "solid"
    Layout.fillWidth: true
    onSelected: key => {
      root.mutate({ gradient: key === "gradient" })
      if (key === "solid") root.stop = "a"
    }
  }

  Segmented {
    visible: root.current.gradient
    options: [{ key: "a", label: "From" }, { key: "b", label: "To" }]
    current: root.stop
    Layout.fillWidth: true
    onSelected: key => root.stop = key
  }

  ColorEditor {
    value: root.stop === "a" ? root.current.a : root.current.b
    alpha: root.stop === "a" ? root.current.aAlpha : root.current.bAlpha
    Layout.fillWidth: true
    onChanged: (value, alpha) => root.setStopColor(value, alpha)
  }

  LabeledSlider {
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
    Layout.fillWidth: true
    onMoved: v => root.mutate({ angle: Math.round(v) })
  }

  Item { Layout.fillHeight: true }

  Text {
    visible: !Session.editable
    text: "Applying creates a user overlay for this stock theme."
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(11)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  RowLayout {
    spacing: 8
    Layout.fillWidth: true

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
