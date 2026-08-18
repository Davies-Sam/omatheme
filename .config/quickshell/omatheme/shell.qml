pragma ComponentBehavior: Bound

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
    { key: "window", label: "Window", source: "Panels/WindowPanel.qml" },
    { key: "palette", label: "Palette", source: "Panels/PalettePanel.qml" },
    { key: "bg", label: "Backgrounds", source: "Panels/BackgroundsPanel.qml" }
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

  // A panel that writes a theme asks everyone to re-read; a panel can also
  // hand the user over to a sibling tab.
  Connections {
    target: Session
    function onReloaded() { session.running = true }
    function onPanelRequested(key) { root.panel = key }
  }

  // --------------------------------------------------------- text scaling
  //
  // `omarchy display text size` writes GNOME's text-scaling-factor. A plain
  // `gsettings monitor` block-buffers its stdout when piped -- lines sit in
  // a 4K buffer and never reach a parser, which once made polling look like
  // the only option -- so stdbuf forces line buffering and every change
  // arrives the moment it is made. monitor only reports changes, so one
  // initial `get` seeds the value.
  function applyScale(raw) {
    var match = /[\d.]+\s*$/.exec(String(raw))
    if (!match) return
    var parsed = parseFloat(match[0])
    if (!isNaN(parsed) && parsed > 0)
      Theme.textScale = Math.min(3, Math.max(0.5, parsed))
  }

  Process {
    id: scaleProbe
    command: ["gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScale(text)
    }
  }

  Process {
    id: scaleWatch
    command: ["stdbuf", "-oL", "gsettings", "monitor",
              "org.gnome.desktop.interface", "text-scaling-factor"]
    running: true
    stdout: SplitParser {
      onRead: line => root.applyScale(line)
    }
  }

  // Qt only ever grows a mapped floating window -- a smaller implicit size is
  // ignored once the compositor has committed one -- so ask Hyprland for the
  // exact size instead, the way omarchy-launch-about sizes the About window.
  Process { id: resizer }

  Timer {
    id: refit
    interval: 120
    onTriggered: {
      // A dispatch still in flight would swallow this one (command changes
      // on a running Process are inert); retry rather than lose the resize.
      if (resizer.running) {
        refit.restart()
        return
      }
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

  Component.onCompleted: { session.running = true; scaleProbe.running = true }

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
            text: "Omatheme"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.size(17)
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          Rectangle {
            // Theme names are arbitrary text (forks are user-named); cap and
            // elide instead of letting a long one push past the window edge.
            Layout.maximumWidth: Theme.size(200)
            implicitWidth: themeLabel.implicitWidth + Theme.size(18)
            implicitHeight: Theme.size(24)
            radius: Theme.radius
            color: Qt.alpha(Theme.accent, 0.15)

            Text {
              id: themeLabel
              anchors.fill: parent
              anchors.leftMargin: Theme.size(9)
              anchors.rightMargin: Theme.size(9)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
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
        //
        // The stack lives in a Flickable because the window clamps to the
        // screen: at a large text scale on a short display the content would
        // otherwise be squeezed until controls disappear. With room to spare
        // the stack fills the viewport and nothing moves; short of room, it
        // keeps its natural height and scrolls.
        Flickable {
          id: panelFlick

          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          contentWidth: width
          contentHeight: panelStack.height
          boundsBehavior: Flickable.StopAtBounds

          StackLayout {
            id: panelStack

            // The panel actually showing, not the stack's implicit height:
            // that is the tallest panel's, which would force every tab to
            // scroll because one of them is tall. Reading `count` first is
            // load-bearing -- itemAt() alone is a plain function call, so
            // without a reactive dependency the binding would evaluate once
            // against the not-yet-populated Repeater and stay null forever.
            readonly property real currentImplicit: {
              if (panelRepeater.count === 0) return 0
              var loader = panelRepeater.itemAt(currentIndex)
              if (!loader) return 0
              return loader.item ? loader.item.implicitHeight : loader.implicitHeight
            }
            // Panels squeeze gracefully by up to this much -- the preview
            // mocks give up height first -- and past it the content keeps
            // its height and scrolls. A fixed floor instead of the slack
            // would cap contentHeight and hide anything taller than the
            // floor with no way to scroll to it.
            readonly property real squeezeSlack: Theme.size(30)

            width: panelFlick.width
            height: Math.max(panelFlick.height, currentImplicit - squeezeSlack)
            currentIndex: Math.max(0, root.panels.findIndex(entry => entry.key === root.panel))

            Repeater {
              // id is load-bearing: panelStack.currentImplicit reads
              // count/itemAt through it. Do not strip it with a test rig.
              id: panelRepeater
              model: root.panels
              Loader {
                id: panelLoader
                required property var modelData
                source: modelData.source

                // A panel file that fails to parse must not be a silent
                // blank tab; the error itself only lands in Quickshell's log.
                Text {
                  anchors.centerIn: parent
                  visible: panelLoader.status === Loader.Error
                  text: "Failed to load " + panelLoader.modelData.source
                  color: Theme.value("red", "#f7768e")
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.size(12)
                }
              }
            }
          }
        }
      }
    }
  }
}
