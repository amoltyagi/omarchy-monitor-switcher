pragma Singleton
import QtQuick

// Theme tokens only. The real interactive components run without a shell,
// monitor backend or permission to touch the live compositor.
QtObject {
  readonly property color background: "#151515"
  readonly property color foreground: "#eeeeee"
  readonly property color accent: "#8ab4f8"
  readonly property color urgent: "#ff7777"
}
