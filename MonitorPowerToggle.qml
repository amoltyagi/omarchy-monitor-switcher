import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

Item {
  id: toggle
  property bool checked: false
  property bool pending: false
  property bool requestedOn: false
  property string tooltipText: ""
  property string fontFamily: "sans-serif"
  signal clicked()
  signal hovered(bool isHovered)
  implicitWidth: switchTrack.width + caption.implicitWidth + Style.space(8)
  implicitHeight: Style.space(26)
  opacity: enabled || pending ? 1 : 0.55
  activeFocusOnTab: true
  Accessible.role: Accessible.CheckBox
  Accessible.name: tooltipText
  Accessible.checked: checked
  Accessible.onToggleAction: if (enabled) clicked()
  Keys.onSpacePressed: clicked()
  Keys.onReturnPressed: clicked()

  Rectangle {
    id: switchTrack
    width: Style.space(34)
    height: Style.space(20)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    radius: height / 2
    color: toggle.checked ? Util.alpha(Color.accent, 0.8) : Util.alpha(Color.foreground, 0.15)
    border.width: 1
    border.color: pointer.containsMouse || toggle.activeFocus ? Color.accent : Util.alpha(Color.foreground, 0.16)
    Behavior on color { ColorAnimation { duration: 150 } }
    Rectangle {
      width: Style.space(14)
      height: width
      radius: width / 2
      x: toggle.checked ? switchTrack.width - width - Style.space(3) : Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      color: toggle.checked ? Color.background : Color.foreground
      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }
  Text {
    id: caption
    anchors.left: switchTrack.right
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: toggle.pending ? (toggle.requestedOn ? "Turning on…" : "Turning off…") : toggle.checked ? "On" : "Off"
    color: Util.alpha(Color.foreground, toggle.pending ? 0.9 : 0.7)
    font.family: toggle.fontFamily
    font.pixelSize: Style.font.caption
    font.weight: Font.Medium
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: toggle.clicked()
    onContainsMouseChanged: toggle.hovered(containsMouse)
  }
  Controls.ToolTip {
    visible: pointer.containsMouse && toggle.tooltipText !== ""
    text: toggle.tooltipText
    delay: 450
  }
}
