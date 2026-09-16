import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import "Model.js" as Model

// A setting should look editable before hover, not like a plain specification.
Rectangle {
  id: chip
  property string text: ""
  property string tooltipText: ""
  property string fontFamily: "sans-serif"
  property real fontSize: Style.font.caption
  property real horizontalPadding: Style.space(11)
  property bool chevron: true
  property bool selected: false
  property bool primary: false
  property bool hasCursor: false
  property color foreground: Color.foreground
  signal clicked()
  signal hovered(bool isHovered)
  readonly property color labelColor: primary ? Model.contrastText(Color.accent) : foreground
  readonly property bool hot: pointer.containsMouse || activeFocus || hasCursor

  implicitWidth: label.implicitWidth + (chevron && enabled ? Style.space(16) : 0) + horizontalPadding * 2
  implicitHeight: Math.max(Style.space(27), label.implicitHeight + Style.space(10))
  radius: Style.space(8)
  color: primary ? Color.accent
    : Util.alpha(foreground, hot ? 0.14 : selected ? 0.1 : 0.055)
  border.width: hot && primary ? 2 : 1
  border.color: primary ? (hot ? labelColor : Color.accent)
    : hot || selected ? Util.alpha(Color.accent, 0.7) : Util.alpha(foreground, 0.22)
  opacity: enabled ? 1 : 0.6
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: tooltipText || text
  Accessible.onPressAction: if (enabled) clicked()
  Keys.onReturnPressed: clicked()
  Keys.onEnterPressed: clicked()
  Keys.onSpacePressed: clicked()
  Behavior on color { ColorAnimation { duration: 130 } }
  Behavior on border.color { ColorAnimation { duration: 130 } }

  Text {
    id: label
    anchors.left: parent.left
    anchors.leftMargin: chip.horizontalPadding
    anchors.right: parent.right
    anchors.rightMargin: chip.horizontalPadding + (chip.chevron && chip.enabled ? Style.space(14) : 0)
    anchors.verticalCenter: parent.verticalCenter
    text: chip.text
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: chip.labelColor
    font.family: chip.fontFamily
    font.pixelSize: chip.fontSize
    font.weight: chip.selected || chip.primary ? Font.DemiBold : Font.Medium
    horizontalAlignment: chip.chevron ? Text.AlignLeft : Text.AlignHCenter
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    visible: chip.chevron && chip.enabled
    text: chip.selected ? "⌃" : "⌄"
    font.family: chip.fontFamily
    font.pixelSize: chip.fontSize
    color: Util.alpha(chip.labelColor, chip.hot ? 1 : 0.8)
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
    onContainsMouseChanged: chip.hovered(containsMouse)
  }
  Controls.ToolTip {
    visible: pointer.containsMouse && chip.tooltipText !== ""
    delay: 500
    text: chip.tooltipText
    contentItem: Text { text: chip.tooltipText; color: Color.foreground; font.family: chip.fontFamily; font.pixelSize: Style.font.caption }
    background: Rectangle { radius: Style.space(7); color: Color.background; border.color: Util.alpha(Color.foreground, 0.2) }
  }
}
