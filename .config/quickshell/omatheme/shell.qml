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
      const state = JSON.parse(json)
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
    const match = /[\d.]+\s*$/.exec(String(raw))
    if (!match) return
    const parsed = parseFloat(match[0])
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

  // ----------------------------------------------------- external changes
  //
  // The theme can change under the app: SUPER+SHIFT+CTRL+SPACE, `omarchy
  // theme bg next`, a helper run from a terminal. Omarchy churns
  // ~/.local/state/omarchy/current/ on every apply (symlinks repointed,
  // next-theme regenerated), so one watch there catches them all, and the
  // panels that show theme-owned state re-read on Session.reloaded. The
  // Window panel deliberately does not: looknfeel.lua is not theme-owned,
  // and reloading it would discard un-applied slider edits every time a
  // palette preview fires. A theme set rewrites 20+ files, so events
  // coalesce through the debounce; stdbuf for the same reason as the
  // gsettings monitor above.
  Process {
    id: stateWatch
    command: ["stdbuf", "-oL", "inotifywait", "-m", "-q",
              "-e", "create,moved_to,delete,modify",
              Quickshell.env("HOME") + "/.local/state/omarchy/current"]
    running: true
    stdout: SplitParser {
      onRead: () => externalChange.restart()
    }
  }

  Timer {
    id: externalChange
    interval: 400
    onTriggered: Session.reloaded()
  }

  // Qt only ever grows a mapped floating window -- a smaller implicit size is
  // ignored once the compositor has committed one -- so ask Hyprland for the
  // exact size instead, the way omarchy-launch-about sizes the About window.
  Process { id: resizer }

  // Quickshell's ScreenInfo knows nothing about the bar's reserved strip,
  // so ask Hyprland for the real one instead of guessing an allowance: a
  // guess high enough to be safe (the old fixed 70) costs the tallest
  // panel its action row on a short screen. Re-probed on text scale
  // changes, since the bar resizes with the font.
  Process {
    id: reservedProbe
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const monitors = JSON.parse(text)
          let top = 0
          let bottom = 0
          for (const monitor of monitors) {
            top = Math.max(top, monitor.reserved[1])
            bottom = Math.max(bottom, monitor.reserved[3])
          }
          window.reservedVertical = top + bottom
        } catch (error) {
          console.warn("omatheme: could not read the reserved area:", error)
        }
      }
    }
  }

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
    function onTextScaleChanged() {
      reservedProbe.running = true
      refit.restart()
    }
  }

  Component.onCompleted: {
    session.running = true
    scaleProbe.running = true
    reservedProbe.running = true
  }

  // ------------------------------------------------------------------- ui
  FloatingWindow {
    id: window

    // Cap growth to the screen: the bar's true reserved strip (see
    // reservedProbe; the pre-probe fallback matches the old guess) plus a
    // scale-aware breathing margin so the float never kisses an edge.
    property int reservedVertical: Theme.size(46)

    title: "Omatheme"
    color: Theme.background

    readonly property int roomWidth: screen ? screen.width - Theme.size(40) : Theme.size(460)
    readonly property int roomHeight: screen
      ? screen.height - reservedVertical - Theme.size(24)
      : Theme.size(566)

    implicitWidth: Math.min(Theme.size(460), roomWidth)

    // Height follows the content. A fixed cap left the panels' bottom
    // action rows just past the fold -- reaching Apply took a scroll.
    // Chrome is the column margins, the header, the switcher and two
    // spacings; the stack contributes its tallest panel (not the current
    // one, or the window would jump on every tab switch). The screen
    // still wins, and the Flickable scrolls in whatever will not fit.
    readonly property real contentNeed: 36 + headerRow.implicitHeight
      + switcher.implicitHeight + 2 * Theme.gap + panelStack.tallestImplicit
    implicitHeight: Math.min(Math.max(Theme.size(566), Math.ceil(contentNeed)),
                             roomHeight)

    // The floor has to yield to the screen as well, or it re-inflates the
    // window past the clamp above at large text scales.
    minimumSize: Qt.size(Math.min(Theme.size(420), roomWidth),
                         Math.min(Theme.size(520), roomHeight))

    // Growth is automatic, but Qt ignores a smaller implicit size once the
    // compositor has committed one -- shrinking goes through the resizer.
    onImplicitHeightChanged: refit.restart()
    // Qt.quit, not Quickshell.quit: QuickshellGlobal 0.3.0 has no quit()
    // method, so the old call threw a TypeError and left a windowless
    // process holding the instance lock -- which made every later
    // launch-or-focus exit silently (no window to focus, and the new
    // qs -n deferred to the zombie instance).
    onVisibleChanged: if (!visible) Qt.quit()

    Item {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: Qt.quit()

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: Theme.gap

        RowLayout {
          id: headerRow
          spacing: 8
          Layout.fillWidth: true

          Text {
            text: "Omatheme"
            color: Theme.foreground
            font {
              family: Theme.fontFamily
              pixelSize: Theme.size(17)
              bold: true
            }
          }

          Item { Layout.fillWidth: true }

          Rectangle {
            implicitWidth: themeLabel.implicitWidth + Theme.size(18)
            implicitHeight: Theme.size(24)
            radius: Theme.radius
            color: Qt.alpha(Theme.accent, 0.15)
            // Theme names are arbitrary text (forks are user-named); cap and
            // elide instead of letting a long one push past the window edge.
            Layout.maximumWidth: Theme.size(200)

            Text {
              id: themeLabel
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: Session.name
              color: Theme.accent
              font.family: Theme.fontFamily
              font.pixelSize: Theme.size(11)
              anchors {
                fill: parent
                leftMargin: Theme.size(9)
                rightMargin: Theme.size(9)
              }
            }
          }
        }

        // One panel needs no switcher; the strip appears as soon as a second
        // one is registered above.
        Segmented {
          id: switcher
          visible: root.panels.length > 1
          options: root.panels.map(entry => ({ key: entry.key, label: entry.label }))
          current: root.panel
          Layout.fillWidth: true
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

          // A Flickable does not clip by default; without it the panel
          // content paints over the header while scrolled.
          clip: true
          contentWidth: width
          contentHeight: panelStack.height
          boundsBehavior: Flickable.StopAtBounds
          Layout.fillWidth: true
          Layout.fillHeight: true

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
              const loader = panelRepeater.itemAt(currentIndex)
              if (!loader) return 0
              return loader.item?.implicitHeight ?? loader.implicitHeight
            }
            // The tallest panel, for the window's own height (see
            // contentNeed above). itemAt() needs the same reactive-read
            // discipline as currentImplicit; the per-item implicitHeight
            // reads keep this current as panels populate.
            readonly property real tallestImplicit: {
              let tallest = 0
              for (let i = 0; i < panelRepeater.count; i++) {
                const loader = panelRepeater.itemAt(i)
                const h = loader?.item?.implicitHeight ?? 0
                if (h > tallest) tallest = h
              }
              return tallest
            }
            // The content gets its full implicit height -- no "squeeze
            // tolerance". An earlier version subtracted a small slack on the
            // theory that panels compress gracefully; that only holds for
            // panels with yielding content (the Border mocks), and for a
            // panel of fixed-height rows it pushed the bottom action row
            // permanently past max scroll.
            width: panelFlick.width
            height: Math.max(panelFlick.height, currentImplicit)
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
