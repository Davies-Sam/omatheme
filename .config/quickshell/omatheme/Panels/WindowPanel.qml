import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui

// Window chrome that Hyprland owns rather than the theme: border width,
// corner rounding, gaps and opacity.
//
// Reads and writes go through omatheme-window, which edits the six keys it
// owns in ~/.config/hypr/looknfeel.lua and leaves the rest of that file
// alone. While you drag, values are pushed into the running compositor with
// `hyprctl eval`; Quattro's Lua parser rejects `hyprctl keyword`, so eval is
// the only live path. Nothing is written until Apply.
ColumnLayout {
  id: root

  property bool dirty: false
  property var values: ({
    border_size: 2, rounding: 0, gaps_in: 8, gaps_out: 14,
    active_opacity: 1, inactive_opacity: 1
  })

  spacing: Theme.gap

  // ------------------------------------------------------------- mutation
  function mutate(changes) {
    var next = {}
    for (var key in root.values) next[key] = root.values[key]
    for (var change in changes) next[change] = changes[change]
    root.values = next
    root.dirty = true
    preview.restart()
  }

  function luaBody(v) {
    return "hl.config({ general = { border_size = " + Math.round(v.border_size) +
           ", gaps_in = " + Math.round(v.gaps_in) +
           ", gaps_out = " + Math.round(v.gaps_out) +
           " }, decoration = { rounding = " + Math.round(v.rounding) +
           ", active_opacity = " + v.active_opacity.toFixed(2) +
           ", inactive_opacity = " + v.inactive_opacity.toFixed(2) + " } })"
  }

  function percent(v) {
    return Math.round(v * 100) + "%"
  }

  // ------------------------------------------------------------ processes
  Process {
    id: loader
    command: ["omatheme-window", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  function applyState(json) {
    try {
      root.values = JSON.parse(json)
      root.dirty = false
    } catch (error) {
      console.warn("omatheme: could not read window state:", error)
    }
  }

  // Setting `command` on a running Process is inert and `running = true` is
  // a no-op, so a second action fired mid-apply would silently vanish. The
  // queue keeps the latest request and replays it on exit; the re-read is
  // driven by the exit itself (the helper reloads Hyprland before exiting)
  // rather than a wall-clock guess.
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
      livePreview.command = ["hyprctl", "eval", root.luaBody(root.values)]
      livePreview.running = true
    }
  }

  function apply() {
    runApplier(["omatheme-window", "set",
                "--border-size", String(Math.round(root.values.border_size)),
                "--rounding", String(Math.round(root.values.rounding)),
                "--gaps-in", String(Math.round(root.values.gaps_in)),
                "--gaps-out", String(Math.round(root.values.gaps_out)),
                "--active-opacity", root.values.active_opacity.toFixed(2),
                "--inactive-opacity", root.values.inactive_opacity.toFixed(2)])
    root.dirty = false
  }

  function revert() {
    reverter.running = true
  }

  function resetToDefault() {
    runApplier(["omatheme-window", "reset", "--all"])
    root.dirty = false
  }

  Component.onCompleted: loader.running = true

  // ------------------------------------------------------------------- ui
  LabeledSlider {
    Layout.fillWidth: true
    label: "Border"
    from: 0
    to: 10
    value: root.values.border_size
    readout: Math.round(root.values.border_size) + " px"
    onMoved: v => root.mutate({ border_size: Math.round(v) })
  }

  LabeledSlider {
    Layout.fillWidth: true
    label: "Round"
    from: 0
    to: 30
    value: root.values.rounding
    readout: Math.round(root.values.rounding) + " px"
    onMoved: v => root.mutate({ rounding: Math.round(v) })
  }

  LabeledSlider {
    Layout.fillWidth: true
    label: "Gap in"
    from: 0
    to: 30
    value: root.values.gaps_in
    readout: Math.round(root.values.gaps_in) + " px"
    onMoved: v => root.mutate({ gaps_in: Math.round(v) })
  }

  LabeledSlider {
    Layout.fillWidth: true
    label: "Gap out"
    from: 0
    to: 60
    value: root.values.gaps_out
    readout: Math.round(root.values.gaps_out) + " px"
    onMoved: v => root.mutate({ gaps_out: Math.round(v) })
  }

  // The floor stops a drag from turning every window invisible mid-preview.
  LabeledSlider {
    Layout.fillWidth: true
    label: "Focus"
    from: 0.5
    to: 1
    value: root.values.active_opacity
    readout: percent(root.values.active_opacity)
    onMoved: v => root.mutate({ active_opacity: v })
  }

  LabeledSlider {
    Layout.fillWidth: true
    label: "Unfocus"
    from: 0.5
    to: 1
    value: root.values.inactive_opacity
    readout: percent(root.values.inactive_opacity)
    onMoved: v => root.mutate({ inactive_opacity: v })
  }

  Item { Layout.fillHeight: true }

  Text {
    Layout.fillWidth: true
    text: "Saved to looknfeel.lua, not the theme."
    color: Theme.dim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.size(11)
    wrapMode: Text.WordWrap
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 8

    TextButton {
      label: "Default"
      onClicked: root.resetToDefault()
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
