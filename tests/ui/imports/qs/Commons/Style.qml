pragma Singleton
import QtQuick

QtObject {
  readonly property QtObject font: QtObject {
    readonly property int caption: 11
    readonly property int body: 14
  }
  function space(value) { return value }
}
