// Monitor illustrations own their details, editors and trial confirmation.
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import "Model.js" as Model

Item {
  id: gallery
  property var monitors: []
  property string focusedMonitor: ""
  property color foreground: Color.foreground
  property string fontFamily: "sans-serif"
  property bool busy: false
  property bool stale: false
  property int enabledCount: 0
  property int cursorIndex: -1
  property var pending: null
  property int seconds: 0
  property int confirmationIndex: -1
  property string pendingPowerOutput: ""
  property bool pendingPowerOn: false
  property string editorOutput: ""
  property string editorField: ""
  property int editorIndex: 0
  property int editorInitialIndex: 0
  readonly property var editorMonitor: monitors.find(function(m) { return m.output === gallery.editorOutput }) || ({})
  readonly property var choices: Model.cardChoices(editorMonitor, editorField)
  readonly property var layout: Model.galleryLayout(monitors, Math.max(0, width - Style.space(24)),
    Style.space(22), Style.space(190), Style.space(210), Style.space(58))
  implicitHeight: layout.height + Style.space(28)

  signal toggleRequested(string output, bool currentlyEnabled)
  signal focusRequested(string output)
  signal settingRequested(string verb, string output, string value)
  signal confirmRequested(bool keep)
  signal cursorRequested(int index)
  signal cursorItemChanged(var item)

  function closeEditor() {
    if (!editorOutput) return false
    editorOutput = ""
    editorField = ""
    return true
  }

  function openEditor(index, field) {
    var m = monitors[index]
    if (!m || busy || stale || !m.enabled || (field === "scale" && !m.usable)) return
    editorOutput = m.output
    editorField = field
    var size = Model.displayDimensions(m)
    var match = choices.findIndex(function(choice) {
      if (field === "scale") return Math.abs(Number(choice.value) - Number(m.scale || m.configuredScale)) < 0.0001
      if (field === "mode") return choice.label === size.width + " × " + size.height
      return Math.round(Number(choice.value.split("@")[1]) * 100) === Math.round(Number(m.refreshRate) * 100)
    })
    editorIndex = Math.max(0, match)
    editorInitialIndex = match
    cursorRequested(index)
  }

  function moveEditor(delta) {
    if (!editorOutput) return false
    editorIndex = Math.max(0, Math.min(choices.length - 1, editorIndex + delta))
    return true
  }

  function applyEditor() {
    if (!editorOutput || busy || stale || !choices[editorIndex]) return
    var output = editorOutput, field = editorField, value = choices[editorIndex].value
    closeEditor()
    // Mode selections include the exact advertised fractional refresh string.
    settingRequested(field === "scale" ? "scale-trial" : "mode", output, value)
  }

  onBusyChanged: if (busy) closeEditor()
  onStaleChanged: if (stale) closeEditor()
  onMonitorsChanged: if (editorOutput && !monitors.some(function(m) { return m.output === gallery.editorOutput && m.enabled })) closeEditor()

  Rectangle {
    anchors.fill: parent
    radius: Style.space(16)
    gradient: Gradient {
      GradientStop { position: 0; color: Util.alpha(Color.foreground, 0.045) }
      GradientStop { position: 1; color: Util.alpha(Color.foreground, 0.015) }
    }
  }

  Repeater {
    id: cards
    model: gallery.monitors
    Item {
      id: card
      required property var modelData
      required property int index
      readonly property var box: gallery.layout.boxes[index] || ({x: 0, y: 0, width: 0, height: 0})
      readonly property var dimensions: Model.displayDimensions(modelData)
      readonly property bool focusedDisplay: modelData.output === gallery.focusedMonitor && modelData.usable === true
      readonly property bool selected: gallery.cursorIndex === index
      readonly property bool editing: gallery.editorOutput === modelData.output
      readonly property bool confirming: gallery.pending !== null && gallery.pending.output === modelData.output
      readonly property bool canToggle: !gallery.busy && !gallery.stale && (!modelData.usable || gallery.enabledCount > 1)
      x: Style.space(12) + box.x
      y: Style.space(14) + box.y
      width: box.width
      height: box.height + Style.space(58)
      onSelectedChanged: if (selected) gallery.cursorItemChanged(card)

      Rectangle {
        x: Style.space(2)
        y: Style.space(4)
        width: bezel.width
        height: bezel.height
        radius: bezel.radius
        color: "#18000000"
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: card.box.height - Style.space(1)
        width: card.width * 0.12
        height: Style.space(14)
        color: Util.alpha(gallery.foreground, 0.24)
      }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: card.box.height + Style.space(12)
        width: card.width * 0.36
        height: Style.space(3)
        radius: height / 2
        color: Util.alpha(gallery.foreground, 0.38)
      }

      Rectangle {
        id: bezel
        width: parent.width
        height: card.box.height
        radius: Style.space(8)
        color: Color.background
        border.width: Style.space(card.selected ? 2 : 1)
        border.color: card.focusedDisplay || card.selected ? Color.accent : Util.alpha(gallery.foreground, 0.28)
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Rectangle {
          id: screen
          anchors.fill: parent
          anchors.margins: Style.space(4)
          anchors.bottomMargin: Style.space(25)
          radius: Style.space(4)
          clip: true
          gradient: Gradient {
            GradientStop { position: 0; color: card.modelData.usable ? Qt.tint(Color.background, Util.alpha(Color.accent, 0.2)) : Color.background }
            GradientStop { position: 1; color: Color.background }
          }

          MouseArea {
            anchors.fill: parent
            enabled: !gallery.busy && !gallery.stale && !card.editing && !card.confirming
            hoverEnabled: true
            cursorShape: card.modelData.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: gallery.cursorRequested(card.index)
            onClicked: if (card.modelData.usable) gallery.focusRequested(card.modelData.output)
          }

          // Diagonal measurement uses the actual illustration corners. Details
          // sit on opaque surfaces so the line never reduces their legibility.
          Rectangle {
            visible: !card.editing && !card.confirming
            x: Style.space(6)
            y: parent.height - Style.space(7)
            width: Math.sqrt(Math.pow(parent.width - Style.space(12), 2) + Math.pow(parent.height - Style.space(14), 2))
            height: 1
            transformOrigin: Item.Left
            rotation: -Math.atan2(parent.height - Style.space(14), parent.width - Style.space(12)) * 180 / Math.PI
            color: Util.alpha(gallery.foreground, 0.12)
          }

          Item {
            anchors.fill: parent
            visible: !card.editing && !card.confirming

            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: Style.space(7)
              width: parent.width - sizeLabel.width - Style.space(23)
              text: (card.modelData.num || card.index + 1) + "  " + (card.modelData.alias || card.modelData.output)
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: card.focusedDisplay ? Color.accent : gallery.foreground
              font.family: gallery.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Text {
              id: sizeLabel
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(7)
              text: card.modelData.inches > 0 ? "↗ " + card.modelData.inches + "″" : "↗ ?"
              color: Util.alpha(gallery.foreground, 0.65)
              font.family: gallery.fontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(4)
              width: parent.width - Style.space(10)
              spacing: 0
              Text {
                width: parent.width
                visible: gallery.stale || !card.dimensions.live
                text: gallery.stale ? "State unavailable" : card.modelData.status + " · saved settings"
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                color: !card.dimensions.live && card.modelData.enabled ? Color.urgent : Util.alpha(gallery.foreground, 0.65)
                font.family: gallery.fontFamily
                font.pixelSize: Style.space(9)
              }
              SettingChip {
                objectName: "resolution-" + card.modelData.output
                anchors.horizontalCenter: parent.horizontalCenter
                text: (card.dimensions.width || "?") + " × " + (card.dimensions.height || "?")
                fontFamily: gallery.fontFamily
                fontSize: Style.font.caption
                foreground: gallery.foreground
                enabled: !gallery.busy && !gallery.stale && card.modelData.enabled
                tooltipText: card.dimensions.live ? "Output pixels. Click to change resolution (M)." : "Saved resolution; no live mode. Click to restore a supported mode."
                onClicked: gallery.openEditor(card.index, "mode")
              }
            }

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(4)
              spacing: Style.space(5)
              SettingChip {
                objectName: "refresh-" + card.modelData.output
                width: (parent.width - parent.spacing) / 2
                text: Model.formatRefreshRate(card.modelData.enabled ? card.modelData.refreshRate : Number(String(card.modelData.mode).split("@")[1])) + " Hz"
                fontFamily: gallery.fontFamily
                foreground: gallery.foreground
                enabled: !gallery.busy && !gallery.stale && card.modelData.enabled
                tooltipText: "Change refresh rate (R)"
                onClicked: gallery.openEditor(card.index, "refresh")
              }
              SettingChip {
                objectName: "scale-" + card.modelData.output
                width: (parent.width - parent.spacing) / 2
                text: Math.round(Number(card.modelData.scale || card.modelData.configuredScale || 1) * 1000) / 10 + "%"
                fontFamily: gallery.fontFamily
                foreground: gallery.foreground
                enabled: !gallery.busy && !gallery.stale && card.modelData.usable
                tooltipText: card.dimensions.live ? "Change desktop scaling (S)" : "Saved desktop scaling"
                onClicked: gallery.openEditor(card.index, "scale")
              }
            }
          }

          // A settings picker replaces only this screen, rather than adding a
          // permanent detail section below the gallery. Wheel scrolls choices.
          Rectangle {
            anchors.fill: parent
            visible: card.editing
            color: Color.background
            Text {
              id: editorTitle
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.margins: Style.space(5)
              text: gallery.editorField === "mode" ? "Resolution" : gallery.editorField === "refresh" ? "Refresh rate" : "Scale"
              color: Color.accent
              font.family: gallery.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            SettingChip {
              anchors.right: parent.right
              text: "×"
              chevron: false
              width: Style.space(24)
              height: Style.space(22)
              horizontalPadding: Style.space(4)
              fontFamily: gallery.fontFamily
              fontSize: Style.font.caption
              tooltipText: "Close settings (Esc)"
              onClicked: gallery.closeEditor()
            }
            ListView {
              id: options
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: editorTitle.bottom
              anchors.topMargin: Style.space(5)
              anchors.bottom: parent.bottom
              clip: true
              model: card.editing ? gallery.choices : []
              currentIndex: gallery.editorIndex
              onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
              Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
              delegate: SettingChip {
                required property var modelData
                required property int index
                width: options.width
                text: (index === gallery.editorInitialIndex ? "✓  " : "    ") + modelData.label
                chevron: false
                foreground: gallery.foreground
                fontFamily: gallery.fontFamily
                fontSize: Style.font.caption
                hasCursor: index === gallery.editorIndex
                onClicked: { gallery.editorIndex = index; gallery.applyEditor() }
                onHovered: function(hovered) { if (hovered) gallery.editorIndex = index }
              }
            }
          }

          Rectangle {
            anchors.fill: parent
            visible: card.confirming
            color: Color.background
            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(10)
              spacing: Style.space(4)
              Text {
                width: parent.width
                text: gallery.pending && gallery.pending.reverting ? "Restoring…" : "Keep these settings?"
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: gallery.foreground
                font.family: gallery.fontFamily
                font.pixelSize: Style.font.caption
              }
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(4)
                SettingChip {
                  text: "Revert " + gallery.seconds + "s"
                  chevron: false
                  fontFamily: gallery.fontFamily
                  fontSize: Style.font.caption
                  hasCursor: gallery.confirmationIndex === 0
                  onClicked: gallery.confirmRequested(false)
                }
                SettingChip {
                  text: "Keep"
                  chevron: false
                  fontFamily: gallery.fontFamily
                  fontSize: Style.font.caption
                  primary: true
                  enabled: gallery.pending !== null && !gallery.pending.reverting && gallery.seconds > 0
                  hasCursor: gallery.confirmationIndex === 1
                  onClicked: gallery.confirmRequested(true)
                }
              }
            }
          }
        }

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(8)
          text: card.focusedDisplay ? "●  Focused" : card.modelData.usable ? "Click display to focus" : ""
          color: card.focusedDisplay ? Color.accent : Util.alpha(gallery.foreground, 0.4)
          font.family: gallery.fontFamily
          font.pixelSize: Style.space(9)
        }
      }
      MonitorPowerToggle {
        objectName: "power-" + card.modelData.output
        anchors.horizontalCenter: parent.horizontalCenter
        y: card.box.height + Style.space(22)
        checked: card.modelData.enabled
        pending: gallery.pendingPowerOutput === card.modelData.output
        requestedOn: gallery.pendingPowerOn
        enabled: card.canToggle
        fontFamily: gallery.fontFamily
        tooltipText: card.modelData.usable && gallery.enabledCount <= 1 ? "Keep at least one usable display on"
          : "Toggle " + (card.modelData.alias || card.modelData.output) + " · Super + Shift + Ctrl + " + card.modelData.num
        onClicked: gallery.toggleRequested(card.modelData.output, card.modelData.enabled)
        onHovered: function(hovered) { if (hovered) gallery.cursorRequested(card.index) }
      }
    }
  }
}
