// monitor-switcher fork: wheel gestures scroll the panel, never change settings.
import QtQuick
import qs.Ui
import qs.Commons

PanelSlider {
  id: slider
  signal scrollRequested(real pixels)
  fillColor: Color.accent
  knobColor: Color.accent

  MouseArea {
    anchors.fill: parent
    z: 1
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) {
      wheel.accepted = true
      slider.scrollRequested(wheel.pixelDelta.y || wheel.angleDelta.y / 120 * Style.space(40))
    }
  }
}
