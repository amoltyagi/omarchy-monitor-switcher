// monitor-switcher fork: a process-free, theme-aware illustration of managed displays.
import QtQuick
import qs.Ui
import qs.Commons
import "Model.js" as Model

Item {
  id: gallery
  property var monitors: []
  property string focusedMonitor: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool busy: false
  property int enabledCount: 0
  property int cursorIndex: -1
  signal toggleRequested(string output, bool currentlyEnabled)
  signal cursorRequested(int index)
  signal cursorItemChanged(var item)
  readonly property int columns: Math.max(1, Math.min(3, monitors.length))
  implicitHeight: displayGrid.implicitHeight + Style.space(28)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    gradient: Gradient {
      GradientStop { position: 0; color: Util.alpha(Color.accent, 0.08) }
      GradientStop { position: 1; color: Util.alpha(Color.accent, 0.015) }
    }
  }

  Grid {
    id: displayGrid
    x: Style.space(12)
    y: Style.space(14)
    width: parent.width - Style.space(24)
    columns: gallery.columns
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(12)

    Repeater {
      model: gallery.monitors

      Item {
        id: displayCard
        required property var modelData
        required property int index
        readonly property bool activeDisplay: modelData.enabled === true
        readonly property bool canToggle: !gallery.busy && (!activeDisplay || gallery.enabledCount > 1)
        readonly property bool focusedDisplay: modelData.output === gallery.focusedMonitor && activeDisplay
        readonly property real aspect: Model.displayAspectRatio(modelData)
        width: (displayGrid.width - displayGrid.columnSpacing * (gallery.columns - 1)) / gallery.columns
        height: illustration.height + displayLabels.implicitHeight + Style.space(8)

        Item {
          id: illustration
          width: parent.width
          height: Style.space(104)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(90)
            width: bezel.width * 0.78
            height: Style.space(5)
            radius: height / 2
            color: Util.alpha(gallery.foreground, 0.08)
          }

          Rectangle {
            id: stem
            anchors.horizontalCenter: parent.horizontalCenter
            y: bezel.y + bezel.height - Style.space(1)
            width: Math.max(Style.space(8), bezel.width * 0.13)
            height: Style.space(15)
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(gallery.foreground, 0.18) }
              GradientStop { position: 1; color: Util.alpha(gallery.foreground, 0.4) }
            }
          }

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: stem.y + stem.height
            width: bezel.width * 0.4
            height: Style.space(3)
            radius: height / 2
            color: Util.alpha(gallery.foreground, 0.45)
          }

          Rectangle {
            id: bezel
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(74) - height
            width: Math.min(parent.width - Style.space(4), Style.space(68) * displayCard.aspect)
            height: width / displayCard.aspect
            radius: Style.space(4)
            color: Color.background
            border.width: Math.max(1, Style.space(1))
            border.color: displayCard.focusedDisplay ? Color.accent : Util.alpha(gallery.foreground, displayCard.activeDisplay ? 0.45 : 0.22)

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: Style.space(2)
              clip: true
              gradient: Gradient {
                GradientStop { position: 0; color: displayCard.activeDisplay ? Qt.darker(Color.accent, 1.6) : Color.background }
                GradientStop { position: 1; color: Color.background }
              }

              // Static wallpaper-like curves, not an FPS simulation or animation loop.
              Rectangle {
                visible: displayCard.activeDisplay
                width: parent.width * 1.6
                height: parent.height * 1.9
                x: -parent.width * 0.3
                y: parent.height * 0.42
                radius: width / 2
                rotation: -22
                color: Util.alpha(Color.accent, 0.32)
                border.width: Style.space(1)
                border.color: Util.alpha(Color.accent, 0.55)
              }
              Rectangle {
                visible: displayCard.activeDisplay
                width: parent.width * 1.9
                height: parent.height * 1.7
                x: parent.width * 0.05
                y: parent.height * 0.65
                radius: width / 2
                rotation: -30
                color: Util.alpha(Color.accent, 0.18)
              }

              Text {
                anchors.centerIn: parent
                text: String(displayCard.modelData.num || displayCard.index + 1)
                color: displayCard.focusedDisplay ? Color.accent : Util.alpha(gallery.foreground, 0.65)
                font.family: gallery.fontFamily
                font.pixelSize: Math.min(parent.height * 0.55, Style.space(26))
                font.weight: Font.DemiBold
              }
            }
          }
        }

        Column {
          id: displayLabels
          y: illustration.height
          width: parent.width
          spacing: Style.space(3)

          Text {
            width: parent.width
            text: displayCard.modelData.alias || displayCard.modelData.output
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: displayCard.focusedDisplay ? Color.accent : gallery.foreground
            font.family: gallery.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: displayCard.focusedDisplay
          }
          Text {
            width: parent.width
            text: (displayCard.modelData.inches > 0 ? displayCard.modelData.inches + "\"" : "Size unknown")
              + (displayCard.focusedDisplay ? " / Focused" : "")
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: Util.alpha(gallery.foreground, 0.6)
            font.family: gallery.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            text: (displayCard.modelData.configuredWidth || displayCard.modelData.width || "?") + " x "
              + (displayCard.modelData.configuredHeight || displayCard.modelData.height || "?")
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: Util.alpha(gallery.foreground, 0.6)
            font.family: gallery.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            text: (displayCard.activeDisplay ? Model.formatRefreshRate(displayCard.modelData.refreshRate) + " Hz / " : "")
              + (displayCard.modelData.scale || 1) + "x"
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: Util.alpha(gallery.foreground, 0.6)
            font.family: gallery.fontFamily
            font.pixelSize: Style.font.caption
          }
          Button {
            id: powerButton
            objectName: "power-" + displayCard.modelData.output
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            text: displayCard.activeDisplay ? "On" : "Off"
            active: displayCard.activeDisplay
            bordered: true
            enabled: displayCard.canToggle
            opacity: enabled ? 1 : 0.5
            foreground: gallery.foreground
            fontFamily: gallery.fontFamily
            fontSize: Style.font.caption
            tooltipText: displayCard.activeDisplay && gallery.enabledCount <= 1 ? "Keep at least one display on"
              : "Turn " + (displayCard.modelData.alias || displayCard.modelData.output) + (displayCard.activeDisplay ? " off" : " on")
            hasCursor: gallery.cursorIndex === displayCard.index
            onHasCursorChanged: if (hasCursor) gallery.cursorItemChanged(displayCard)
            onClicked: gallery.toggleRequested(displayCard.modelData.output, displayCard.activeDisplay)
            onHovered: function(hovered) { if (hovered) gallery.cursorRequested(displayCard.index) }
          }
        }
      }
    }
  }
}
