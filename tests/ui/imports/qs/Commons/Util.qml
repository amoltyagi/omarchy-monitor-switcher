pragma Singleton
import QtQuick

QtObject {
  function alpha(value, opacity) {
    var color = Qt.color(value)
    return Qt.rgba(color.r, color.g, color.b, opacity)
  }
}
