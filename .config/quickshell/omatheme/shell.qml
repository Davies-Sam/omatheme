import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui

// Omatheme -- theme designer for Omarchy Quattro.
//
// The shell owns only what every panel shares: the window, the session state
// (which theme is current), the tokens the app paints itself with, and the
// switcher. Each panel is self-contained and talks to its own helper on PATH,
// so everything the GUI can do is also reachable from a terminal.
//
// Adding a panel:
//   1. write Panels/<Name>Panel.qml -- a ColumnLayout owning its own state,
//      processes and action buttons, like Panels/BorderPanel.qml
//   2. add a small `omatheme-<domain>` helper next to omatheme-border for the
//      reads and writes it needs
//   3. add one entry to `panels` below
ShellRoot {
  id: root

  readonly property var panels: [
    { key: "border", label: "Border", source: "Panels/BorderPanel.qml" },
    { key: "window", label: "Window", source: "Panels/WindowPanel.qml" }
  ]

  property string panel: "border"

  // ------------------------------------------------------- session state
  Process {
    id: session
    command: ["omatheme-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySession(text)
    }
  }

  function applySession(json) {
    try {
      var state = JSON.parse(json)
      Theme.colors = state.palette || ({})
      if (state.font) Theme.fontFamily = state.font
      if (state.textScale) Theme.textScale = state.textScale
      Session.slug = state.slug || ""
      Session.name = state.name || "Unknown"
      Session.editable = state.editable !== false
      Session.ready = true
    } catch (error) {
      console.warn("omatheme: could not read session state:", error)
    }
  }

  // A panel that writes a theme asks everyone to re-read.
  Connections {
    target: Session
    function onReloaded() { session.running = true }
  }

  // --------------------------------------------------------- text scaling
  //
  // `omarchy display text size` writes GNOME's text-scaling-factor. dconf
  // exposes no signal Quickshell can subscribe to (`gsettings monitor` never
  // delivered a line through a parser), so poll it the way omarchy-shell
  // polls hyprctl -- cheap, and only while the window is open.
  Process {
    id: scaleProbe
    command: ["gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = parseFloat(String(text).trim())
        if (!isNaN(parsed) && parsed > 0)
          Theme.textScale = Math.min(3, Math.max(0.5, parsed))
      }
    }
  }

  Timer {
    id: scaleTimer
    interval: 2000
    repeat: true
    onTriggered: scaleProbe.running = true
  }

  // Qt only ever grows a mapped floating window -- a smaller implicit size is
  // ignored once the compositor has committed one -- so ask Hyprland for the
  // exact size instead, the way omarchy-launch-about sizes the About window.
  Process { id: resizer }

  Timer {
    id: refit
    interval: 120
    onTriggered: {
      resizer.command = ["hyprctl", "dispatch",
        'hl.dsp.window.resize({ window = "title:Omatheme", x = ' + window.implicitWidth +
        ', y = ' + window.implicitHeight + ' })']
      resizer.running = true
    }
  }

  Connections {
    target: Theme
    function onTextScaleChanged() { refit.restart() }
  }

  Component.onCompleted: { session.running = true; scaleTimer.start() }

  // ------------------------------------------------------------------- ui
  FloatingWindow {
    id: window

    title: "Omatheme"
    color: Theme.background

    // Cap growth to the screen. Quickshell's ScreenInfo knows nothing about
    // the bar's reserved strip, so leave a scale-aware allowance for it --
    // otherwise a large text scale grows the window under the bar and off
    // the bottom of the display.
    readonly property int roomWidth: screen ? screen.width - Theme.size(40) : Theme.size(460)
    readonly property int roomHeight: screen ? screen.height - Theme.size(70) : Theme.size(566)

    implicitWidth: Math.min(Theme.size(460), roomWidth)
    implicitHeight: Math.min(Theme.size(566), roomHeight)

    // The floor has to yield to the screen as well, or it re-inflates the
    // window past the clamp above at large text scales.
    minimumSize: Qt.size(Math.min(Theme.size(420), roomWidth),
                         Math.min(Theme.size(520), roomHeight))

    onVisibleChanged: if (!visible) Quickshell.quit()

    Item {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: Quickshell.quit()

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: Theme.gap

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: root.panels.length > 1
              ? "Omatheme"
              : root.panels[0].label === "Border" ? "Window border" : root.panels[0].label
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(17)
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          Rectangle {
            implicitWidth: themeLabel.implicitWidth + Theme.size(18)
            implicitHeight: Theme.size(24)
            radius: Theme.radius
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)

            Text {
              id: themeLabel
              anchors.centerIn: parent
              text: Session.name
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: Theme.size(11)
            }
          }
        }

        // One panel needs no switcher; the strip appears as soon as a second
        // one is registered above.
        Segmented {
          Layout.fillWidth: true
          visible: root.panels.length > 1
          options: root.panels.map(entry => ({ key: entry.key, label: entry.label }))
          current: root.panel
          onSelected: key => root.panel = key
        }

        // Every panel is instantiated once and kept alive; a Loader whose
        // source follows the switcher would destroy a panel's unsaved edits
        // the moment you tab away from it.
        StackLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          currentIndex: Math.max(0, root.panels.findIndex(entry => entry.key === root.panel))

          Repeater {
            model: root.panels
            Loader {
              required property var modelData
              source: modelData.source
            }
          }
        }
      }
    }
  }
}
