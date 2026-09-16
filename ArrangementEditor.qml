import QtQuick
import qs.Commons
import "Model.js" as Model

Column {
  id: editor
  property var monitors: []
  property bool busy: false
  property var pending: null
  property int seconds: 0
  property int confirmationIndex: -1
  property string fontFamily: "sans-serif"
  property var draft: []
  property var original: []
  property var viewBoxes: []
  property int selectedIndex: 0
  property int referenceIndex: 1
  property bool dragging: false
  property string notice: ""
  readonly property string liveSignature: JSON.stringify(Model.arrangementBoxes(monitors))
  readonly property bool confirming: pending !== null && pending.kind === "arrangement"
  readonly property bool dirty: JSON.stringify(draft) !== JSON.stringify(original)
  readonly property string problem: Model.arrangementError(draft)
  readonly property var view: Model.arrangementView(viewBoxes, canvas.width, canvas.height, Style.space(64))
  readonly property var selectedDisplay: draft[selectedIndex] || ({})
  signal applyRequested(string positions)
  signal confirmRequested(bool keep)
  spacing: Style.space(12)

  function reset() {
    original = Model.arrangementBoxes(monitors)
    draft = original.map(function(b) { return Object.assign({}, b) })
    viewBoxes = draft
    selectedIndex = Math.min(Math.max(0, selectedIndex), Math.max(0, draft.length - 1))
    referenceIndex = selectedIndex === 0 ? 1 : 0
    dragging = false
  }
  function select(index) {
    selectedIndex = index
    if (referenceIndex === index) referenceIndex = index === 0 ? 1 : 0
  }
  function place(direction) {
    if (busy || draft.length < 2) return
    draft = Model.placeDisplay(draft, selectedIndex, referenceIndex, direction)
    viewBoxes = draft
    notice = ""
  }
  function apply() {
    if (busy || !dirty || problem) return
    applyRequested(JSON.stringify(draft.map(function(b) { return {output: b.output, x: b.x, y: b.y} })))
  }
  onVisibleChanged: if (visible) { reset(); notice = "" }
  onLiveSignatureChanged: {
    if (visible && dirty && !busy) notice = "Display layout changed. The preview has been refreshed."
    reset()
  }
  Component.onCompleted: reset()

  Rectangle {
    id: canvas
    width: parent.width
    height: Style.space(235)
    radius: Style.space(15)
    color: Util.alpha(Color.foreground, 0.025)
    border.color: Util.alpha(Color.foreground, 0.1)
    clip: true

    // Restrained dot grid helps positioning without looking like an engineering tool.
    Canvas {
      anchors.fill: parent
      property color dotColor: Util.alpha(Color.foreground, 0.12)
      onDotColorChanged: requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var c = getContext("2d")
        c.clearRect(0, 0, width, height)
        c.fillStyle = dotColor
        for (var x = Style.space(18); x < width; x += Style.space(18))
          for (var y = Style.space(18); y < height; y += Style.space(18)) c.fillRect(x, y, 1, 1)
      }
    }
    Repeater {
      model: editor.draft.length
      Rectangle {
        id: display
        required property int index
        readonly property var box: editor.draft[index] || ({x: 0, y: 0, w: 0, h: 0})
        objectName: "arrangement-" + (box.output || "")
        readonly property bool selected: index === editor.selectedIndex
        x: editor.view.x + box.x * editor.view.scale
        y: editor.view.y + box.y * editor.view.scale
        width: box.w * editor.view.scale
        height: box.h * editor.view.scale
        radius: Style.space(7)
        color: Color.background
        border.width: selected ? 2 : 1
        border.color: selected ? Color.accent : Util.alpha(Color.foreground, 0.4)
        z: selected ? 2 : 1
        Behavior on x { enabled: !editor.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !editor.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(4)
          radius: Style.space(4)
          color: Util.alpha(Color.accent, display.selected ? 0.15 : 0.06)
        }
        Column {
          anchors.centerIn: parent
          width: parent.width - Style.space(10)
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: display.box.num + "  " + display.box.name
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: Color.foreground
            font.family: editor.fontFamily
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            visible: parent.parent.height > Style.space(55)
            text: display.selected ? "Drag to position" : "Click to select"
            horizontalAlignment: Text.AlignHCenter
            color: Util.alpha(Color.foreground, 0.55)
            font.family: editor.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        MouseArea {
          anchors.fill: parent
          enabled: !editor.busy && editor.draft.length > 1
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          property point pressPoint
          property point initialPosition
          onPressed: function(mouse) {
            editor.select(display.index)
            editor.dragging = true
            pressPoint = mapToItem(canvas, mouse.x, mouse.y)
            initialPosition = Qt.point(display.box.x, display.box.y)
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var p = mapToItem(canvas, mouse.x, mouse.y)
            var x = initialPosition.x + (p.x - pressPoint.x) / editor.view.scale
            var y = initialPosition.y + (p.y - pressPoint.y) / editor.view.scale
            x = Math.max(-editor.view.x / editor.view.scale, Math.min((canvas.width - editor.view.x) / editor.view.scale - display.box.w, x))
            y = Math.max(-editor.view.y / editor.view.scale, Math.min((canvas.height - editor.view.y) / editor.view.scale - display.box.h, y))
            editor.draft = Model.snapDisplay(editor.draft, display.index, x, y, Style.space(20) / editor.view.scale)
          }
          onReleased: { editor.dragging = false; editor.viewBoxes = editor.draft; editor.notice = "" }
          onCanceled: { editor.dragging = false; editor.reset() }
        }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(12)
      text: "Desktop space · edges snap together"
      color: Util.alpha(Color.foreground, 0.45)
      font.family: editor.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Flow {
    width: parent.width
    spacing: Style.space(6)
    visible: draft.length > 1 && !editor.confirming
    Text {
      height: Style.space(29)
      text: (editor.selectedDisplay.name || "Display") + " relative to"
      color: Util.alpha(Color.foreground, 0.65)
      verticalAlignment: Text.AlignVCenter
      font.family: editor.fontFamily
      font.pixelSize: Style.font.caption
    }
    Repeater {
      model: editor.draft
      SettingChip {
        required property var modelData
        required property int index
        visible: index !== editor.selectedIndex
        text: modelData.name
        chevron: false
        selected: index === editor.referenceIndex
        enabled: !editor.busy
        fontFamily: editor.fontFamily
        onClicked: editor.referenceIndex = index
      }
    }
    Repeater {
      model: [{label: "← Left", direction: "left"}, {label: "Right →", direction: "right"},
        {label: "↑ Above", direction: "above"}, {label: "↓ Below", direction: "below"}]
      SettingChip {
        required property var modelData
        text: modelData.label
        chevron: false
        enabled: !editor.busy
        fontFamily: editor.fontFamily
        onClicked: editor.place(modelData.direction)
      }
    }
  }

  Text {
    width: parent.width
    text: editor.confirming ? "Keep this arrangement? Reverting in " + editor.seconds + " seconds."
      : editor.notice || editor.problem || "Drag displays to match your desk, then apply."
    wrapMode: Text.WordWrap
    color: editor.problem && editor.dirty ? Color.urgent : Util.alpha(Color.foreground, 0.65)
    font.family: editor.fontFamily
    font.pixelSize: Style.font.caption
  }
  Row {
    width: parent.width
    spacing: Style.space(8)
    SettingChip {
      text: editor.confirming ? "Revert" : "Reset"
      chevron: false
      enabled: editor.confirming || (editor.dirty && !editor.busy)
      hasCursor: editor.confirming && editor.confirmationIndex === 0
      fontFamily: editor.fontFamily
      onClicked: editor.confirming ? editor.confirmRequested(false) : editor.reset()
    }
    SettingChip {
      visible: !editor.confirming
      text: "Align in a row"
      chevron: false
      enabled: !editor.busy && editor.draft.length > 1
      fontFamily: editor.fontFamily
      onClicked: { editor.draft = Model.packDisplays(editor.draft); editor.viewBoxes = editor.draft; editor.notice = "" }
    }
    SettingChip {
      text: editor.confirming ? "Keep arrangement" : "Apply arrangement"
      chevron: false
      primary: true
      enabled: editor.confirming ? !editor.pending.reverting && editor.seconds > 0 : editor.dirty && !editor.problem && !editor.busy
      hasCursor: editor.confirming && editor.confirmationIndex === 1
      fontFamily: editor.fontFamily
      onClicked: editor.confirming ? editor.confirmRequested(true) : editor.apply()
    }
  }
}
