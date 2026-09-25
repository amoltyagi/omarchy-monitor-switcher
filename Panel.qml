// Monitor Switcher: per-screen popup, one authoritative backend snapshot.
// Originally vendored from Omarchy's monitor panel; see UPSTREAM.md.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "PanelRegistry.js" as PanelRegistry

Panel {
  id: root
  moduleName: "case.monitor-switcher"
  ipcTarget: "case.monitor-switcher"
  manageIpc: false
  property bool ipcOwner: false
  readonly property string uiFontFamily: "sans-serif"
  property bool arranging: false
  property bool shortcutsExpanded: false
  readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
  readonly property string liveFocusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  readonly property string scriptPath: Qt.resolvedUrl("bin/monitor-switcher").toString().replace(/^file:\/\//, "")

  property var displays: []
  property var switcherMeta: ({})
  property string focusedMonitor: ""
  property int enabledDisplayCount: 0
  readonly property var focusedMeta: switcherMeta[focusedMonitor] || ({})
  property var nightLightStates: ({})
  property bool nightLightReady: false
  property bool nightLightBusy: false
  property string nightLightError: ""
  readonly property var galleryMonitors: displays.filter(function(m) { return m.connected }).map(function(m) {
    return Object.assign({}, m, {nightLight: root.nightLightStates[m.output] || ({enabled: false, active: false, available: false, temperature: 4000})})
  })
  property var refreshPending: null
  property double refreshClock: Date.now() / 1000
  readonly property int refreshSeconds: refreshPending ? Math.max(0, Math.ceil(refreshPending.expiresAt - refreshClock)) : 0
  property string stateError: ""
  property string actionError: ""
  property string brightnessError: ""
  property string textSizeError: ""
  readonly property string visibleError: [stateError, actionError, brightnessError, textSizeError, nightLightError].filter(function(message) { return message !== "" }).join("\n")
  property string actionVerb: ""
  property string actionTarget: ""
  property string actionNotice: ""
  property string noticeKind: ""
  property bool sharedActionRunning: false
  property var readTicket: null
  property bool refreshQueued: false
  property bool reopenAfterAction: false
  readonly property bool layoutBusy: sharedActionRunning || refreshPending !== null

  property int brightnessPercent: 0
  property bool brightnessAvailable: false
  property string brightnessReadTarget: ""
  property string brightnessWriteTarget: ""
  property int pendingBrightnessPercent: 0
  property string pendingBrightnessTarget: ""
  property bool brightnessSetQueued: false
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1
  property bool reflowingText: false

  property string focusSection: "monitors"
  property int selectedIndex: 0
  property bool cursorActive: false
  readonly property var visibleSections: {
    var result = []
    if (refreshPending) result.push("confirmation")
    if (arranging) result.push("arrangement")
    else if (galleryMonitors.length) result.push("monitors")
    if (!arranging) {
      if (brightnessAvailable) result.push("brightness")
      result.push("textsize")
    }
    return result
  }

  function refresh() {
    if (switcherProc.running) { refreshQueued = true; return }
    readTicket = PanelRegistry.startRead()
    switcherProc.running = true
  }

  function acceptSnapshot(state) {
    var map = {}, focused = ""
    state.monitors.forEach(function(m) { map[m.output] = m; if (m.focused) focused = m.output })
    switcherMeta = map
    if (JSON.stringify(displays) !== JSON.stringify(state.monitors)) displays = state.monitors
    enabledDisplayCount = state.enabledCount
    focusedMonitor = focused
    stateError = ""
    var pending = state.refreshPending || null
    if (JSON.stringify(pending) !== JSON.stringify(refreshPending)) {
      refreshPending = pending
      if (pending && pending.kind === "arrangement") arranging = true
      if (pending) { focusSection = "confirmation"; selectedIndex = 0; cursorActive = true }
    }
    // A blocked second action is a transient status, not an error to leave behind.
    if (noticeKind === "pending" && !pending) { actionNotice = ""; noticeKind = "" }
    refreshClock = Date.now() / 1000
    refreshBrightness()
  }

  function acceptNightLight(state) {
    nightLightReady = state.ready === true
    nightLightStates = state.monitors || ({})
    var errors = Object.keys(nightLightStates).filter(function(name) { return nightLightStates[name].error })
      .map(function(name) { return name + ": " + nightLightStates[name].error })
    nightLightError = [state.error || ""].concat(errors).filter(function(message) { return message }).join("\n")
  }

  function writeNightLight(output, value) {
    if (!nightLightProc.running || !nightLightReady) {
      // Preserve a healthy shared snapshot's ready flag; only report the error.
      PanelRegistry.publishNightLight({ready: nightLightReady, monitors: nightLightStates, error: "Night Light is unavailable. Reopen the panel to retry."})
      return
    }
    nightLightProc.write(JSON.stringify({output: output, value: value}) + "\n")
  }

  function refreshBrightness() {
    if (!focusedMonitor || !focusedMeta.usable || brightnessProc.running || setBrightnessProc.running || brightnessDebounce.running) return
    brightnessReadTarget = focusedMonitor
    brightnessProc.command = ["bash", "-o", "pipefail", "-c",
      "omarchy-brightness-display --monitor \"$1\" 2>/dev/null | head -c 65536", "monitor-switcher", brightnessReadTarget]
    brightnessProc.running = true
  }

  function runAction(verb, output, value) {
    var confirmation = verb === "confirm" || verb === "revert"
    if (actionProc.running || sharedActionRunning
        || (!confirmation && (stateError !== "" || (verb !== "focus" && refreshPending !== null)))) return
    if (!PanelRegistry.beginAction(root)) return
    actionError = ""
    actionNotice = ""
    noticeKind = ""
    actionVerb = verb
    actionTarget = output
    reopenAfterAction = opened && verb !== "focus"
    // argv carries all user/output values; none are interpolated into shell code.
    // Bounded so onExited (and with it PanelRegistry.actionFinished) always runs.
    actionProc.command = ["timeout", "-k", "1", "45", "bash",
      Qt.resolvedUrl("bin/monitor-action").toString().replace(/^file:\/\//, ""), verb, output, value || ""]
    // Keep optional arguments absent, rather than forwarding an empty fourth argument.
    if (!value) actionProc.command = actionProc.command.slice(0, -1)
    if (verb === "focus") close()
    actionProc.running = true
  }

  function toggleDisplay(output, enabled) {
    var m = switcherMeta[output]
    if (!m || (enabled && m.usable && enabledDisplayCount <= 1)) return
    runAction(enabled ? "disable" : "enable", output, "")
  }

  function setBrightness(value) {
    if (!focusedMonitor || !brightnessAvailable) return
    var percent = Model.clampBrightness(value)
    brightnessPercent = percent
    pendingBrightnessPercent = percent
    pendingBrightnessTarget = focusedMonitor
    if (setBrightnessProc.running) { brightnessSetQueued = true; return }
    brightnessSetQueued = false
    brightnessWriteTarget = focusedMonitor
    setBrightnessProc.command = Model.settingCommand("omarchy-brightness-display",
      ["--no-osd", "--monitor", brightnessWriteTarget, percent + "%"])
    setBrightnessProc.running = true
  }

  function nearestTextStop(px) {
    var best = 0
    for (var i = 1; i < textSizeStops.length; i++)
      if (Math.abs(textSizeStops[i] - px) < Math.abs(textSizeStops[best] - px)) best = i
    return best
  }
  function currentTextIndex() { return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize) }
  function setTextSize(index) {
    if (textScaleProc.running) return
    textSizePreviewIndex = Math.max(0, Math.min(textSizeStops.length - 1, index))
    reflowingText = true
    reflowSettle.restart()
    textScaleProc.command = Model.settingCommand("omarchy-display-text-size",
      [String(textSizeStops[textSizePreviewIndex])])
    textScaleProc.running = true
  }

  function sectionCount(section) {
    return section === "monitors" ? galleryMonitors.length : section === "confirmation" ? 2 : 1
  }
  function clampCursor() {
    if (visibleSections.indexOf(focusSection) < 0) focusSection = visibleSections[0]
    selectedIndex = Math.max(0, Math.min(selectedIndex, sectionCount(focusSection) - 1))
  }
  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    if (arranging && !refreshPending) {
      arrangement.place(dx < 0 ? "left" : dx > 0 ? "right" : dy < 0 ? "above" : "below")
      return
    }
    if (gallery.moveEditor(dy || dx)) return
    if (dx) {
      if (focusSection === "brightness") setBrightness(brightnessPercent + dx * 5)
      else if (focusSection === "textsize") setTextSize(currentTextIndex() + dx)
      else selectedIndex = Math.max(0, Math.min(sectionCount(focusSection) - 1, selectedIndex + dx))
      return
    }
    if (focusSection === "monitors" && selectedIndex + dy >= 0 && selectedIndex + dy < galleryMonitors.length) {
      selectedIndex += dy
      return
    }
    var index = Math.max(0, Math.min(visibleSections.length - 1, visibleSections.indexOf(focusSection) + dy))
    focusSection = visibleSections[index]
    selectedIndex = dy < 0 ? sectionCount(focusSection) - 1 : 0
  }
  function activateCursor() {
    if (gallery.editorOutput) { gallery.applyEditor(); return }
    if (focusSection === "confirmation" && refreshPending) {
      runAction(selectedIndex === 1 ? "confirm" : "revert", refreshPending.token, "")
    } else if (arranging) arrangement.apply()
    else if (focusSection === "monitors") {
      var m = galleryMonitors[selectedIndex]
      if (m && m.usable) runAction("focus", m.output, "")
    }
  }
  function textKey(text) {
    text = text.toLowerCase()
    if (text === "?") { shortcutsExpanded = !shortcutsExpanded; return }
    if (text.toLowerCase() === "a" && !layoutBusy) { cursorActive = true; arranging = !arranging; gallery.closeEditor(); return }
    if (arranging) {
      if (text.toLowerCase() === "n" && arrangement.draft.length)
        arrangement.select((arrangement.selectedIndex + 1) % arrangement.draft.length)
      return
    }
    if (focusSection !== "monitors") return
    cursorActive = true
    if (text === "m") gallery.openEditor(selectedIndex, "mode")
    else if (text === "r") gallery.openEditor(selectedIndex, "refresh")
    else if (text === "s") gallery.openEditor(selectedIndex, "scale")
    else if (text === "t") gallery.openEditor(selectedIndex, "nightlight")
    else if (text === "o") gallery.openEditor(selectedIndex, "rotation")
    else if (text === "p") {
      var m = galleryMonitors[selectedIndex]
      if (m) toggleDisplay(m.output, m.enabled)
    }
  }
  function hoverSection(section) {
    if (reflowingText || gallery.editorOutput) return
    focusSection = section
    selectedIndex = 0
    cursorActive = true
  }
  function ensureCursorVisible(item) {
    if (!item || !scrollArea.contentItem) return
    var flick = scrollArea.contentItem
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    if (pt.y < flick.contentY) flick.contentY = Math.max(0, pt.y - 6)
    else if (pt.y + item.height > flick.contentY + flick.height)
      flick.contentY = Math.max(0, pt.y + item.height - flick.height + 6)
  }
  function scrollPanel(pixels) {
    var flick = scrollArea.contentItem
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY - pixels))
  }
  function stateIpc() {
    return JSON.stringify({brightness: brightnessPercent, brightnessAvailable: brightnessAvailable,
      focusedMonitor: focusedMonitor, scale: focusedMeta.scale, refreshRate: focusedMeta.refreshRate,
      refreshPending: refreshPending, actionError: actionError, actionNotice: actionNotice,
      brightnessError: brightnessError, textSizeError: textSizeError,
      nightLight: nightLightStates, nightLightError: nightLightError, nightLightReady: nightLightReady,
      actionRunning: sharedActionRunning, stateError: stateError, displays: displays,
      ui: {arranging: arranging, focusSection: focusSection, selectedIndex: selectedIndex,
        popup: {screen: screenName, x: panel.cardOrigin.x, y: panel.cardOrigin.y, width: panel.contentWidth, height: panel.contentHeight},
        editorOutput: gallery.editorOutput, editorField: gallery.editorField, editorIndex: gallery.editorIndex,
        arrangement: arrangement.draft, arrangementError: arrangement.problem, arrangementDirty: arrangement.dirty}})
  }
  function ipcPanel() { return PanelRegistry.activePanel(liveFocusedName) || root }

  IpcHandler {
    enabled: root.ipcOwner
    target: root.ipcTarget
    function brightness(percent: string): string { var p = root.ipcPanel(); p.setBrightness(Number(percent)); return "got " + p.brightnessPercent }
    function state(): string { return root.ipcPanel().stateIpc() }
    function open() { root.ipcPanel().open() }
    function close() { root.ipcPanel().close() }
    function toggle() { root.ipcPanel().toggle() }
    function show() { root.ipcPanel().open() }
    function hide() { root.ipcPanel().close() }
  }

  Component.onCompleted: { PanelRegistry.register(root); refresh() }
  Component.onDestruction: PanelRegistry.unregister(root)
  readonly property int enabledScreenCount: Quickshell.screens.length
  onEnabledScreenCountChanged: refresh()
  onLiveFocusedNameChanged: refresh()
  onVisibleSectionsChanged: clampCursor()
  onShortcutsExpandedChanged: {
    if (shortcutsExpanded) shortcutScroll.restart()
    else if (scrollArea.contentItem) scrollArea.contentItem.contentY = 0
  }
  onFocusedMonitorChanged: {
    brightnessDebounce.stop()
    brightnessSetQueued = false
    brightnessAvailable = false
  }
  onOpenedChanged: {
    if (opened) {
      if (root.ipcOwner && !nightLightProc.running) nightLightProc.running = true
      nightLightStartWatch.restart()
      PanelRegistry.synchronize()
      focusSection = refreshPending ? "confirmation" : arranging ? "arrangement" : galleryMonitors.length ? "monitors" : "textsize"
      selectedIndex = refreshPending ? 0 : Math.max(0, galleryMonitors.findIndex(function(m) { return m.output === root.focusedMonitor }))
      cursorActive = false
    } else { gallery.closeEditor(); shortcutsExpanded = false }
  }

  Process {
    id: nightLightProc
    command: ["python3", Qt.resolvedUrl("bin/monitor-nightlight.py").toString().replace(/^file:\/\//, "")]
    running: root.ipcOwner
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(data) {
        try { PanelRegistry.publishNightLight(JSON.parse(data)) }
        catch (error) { PanelRegistry.publishNightLight({ready: false, monitors: {}, error: "Could not read Night Light state."}) }
      }
    }
    onExited: if (root.ipcOwner) PanelRegistry.publishNightLight({ready: false, monitors: {}, error: "Night Light stopped. Reopen the panel to retry."})
  }
  // Quickshell does not emit exited on FailedToStart (e.g. missing python3):
  // detect a service that never came up instead of leaving chips silently dead.
  Timer {
    id: nightLightStartWatch
    interval: 4000
    onTriggered: if (root.ipcOwner && !nightLightReady)
      PanelRegistry.publishNightLight({ready: false, monitors: {}, error: "Night Light could not start (is python3 available?)"})
  }

  Process {
    id: switcherProc
    // Bounded: a wedged backend lock must surface as an error, not stall the panel.
    command: ["bash", "-o", "pipefail", "-c", "timeout -k 1 35 \"$1\" state --json 2> >(head -c 65536 >&2) | head -c 262144", "monitor-switcher", root.scriptPath]
    stdout: StdioCollector { id: stateOutput; waitForEnd: true }
    stderr: StdioCollector { id: stateErrors; waitForEnd: true }
    onExited: function(exitCode) {
      var ticket = root.readTicket
      var again = root.refreshQueued
      root.refreshQueued = false
      if (exitCode !== 0) {
        PanelRegistry.readFailed(String(stateErrors.text || "Could not read monitor state").trim(), ticket)
      } else {
        try {
          var state = JSON.parse(String(stateOutput.text || ""))
          if (!Array.isArray(state.monitors)) throw new Error("Invalid monitor snapshot")
          PanelRegistry.publishSnapshot(state, ticket)
        } catch (error) {
          PanelRegistry.readFailed("Could not read monitor state: " + error.message, ticket)
        }
      }
      if (again || PanelRegistry.outdated(ticket)) root.refresh()
    }
  }
  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    onExited: function(exitCode) {
      var feedback = Model.actionFeedback(exitCode, actionOutput.text)
      root.actionError = feedback.error
      root.actionNotice = feedback.notice
      root.noticeKind = feedback.kind
      if (feedback.kind === "complete") noticeTimer.restart()
      PanelRegistry.actionFinished(root)
      if (root.reopenAfterAction && !root.opened) reopenTimer.restart()
      root.reopenAfterAction = false
    }
  }
  Process {
    id: brightnessProc
    stdout: StdioCollector { id: brightnessOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.brightnessReadTarget !== root.focusedMonitor || setBrightnessProc.running || brightnessDebounce.running) return
      var n = parseInt(String(brightnessOutput.text || "").trim(), 10)
      root.brightnessAvailable = exitCode === 0 && isFinite(n)
      if (root.brightnessAvailable) root.brightnessPercent = Model.clampBrightness(n)
    }
  }
  Process {
    id: setBrightnessProc
    stdout: StdioCollector { id: brightnessWriteOutput; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      root.brightnessError = Model.settingError("Brightness for " + root.brightnessWriteTarget,
        exitCode, brightnessWriteOutput.text, exitStatus !== 0)
      if (root.brightnessSetQueued && root.pendingBrightnessTarget === root.focusedMonitor) {
        root.setBrightness(root.pendingBrightnessPercent)
      } else {
        root.brightnessSetQueued = false
        root.refreshBrightness()
      }
    }
  }
  Process {
    id: textScaleProc
    stdout: StdioCollector { id: textSizeOutput; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      root.textSizeError = Model.settingError("Text size", exitCode, textSizeOutput.text, exitStatus !== 0)
      root.textSizePreviewIndex = -1
    }
  }
  Timer { id: reopenTimer; interval: 600; onTriggered: root.open() }
  Timer { id: brightnessDebounce; interval: 180; onTriggered: root.setBrightness(root.brightnessPercent) }
  Timer { id: reflowSettle; interval: 350; onTriggered: root.reflowingText = false }
  Timer {
    id: noticeTimer
    interval: 6000
    onTriggered: if (root.noticeKind === "complete") { root.actionNotice = ""; root.noticeKind = "" }
  }
  Timer {
    id: shortcutScroll
    interval: 80
    onTriggered: {
      var flick = scrollArea.contentItem
      if (root.shortcutsExpanded && flick) flick.contentY = Math.max(0, flick.contentHeight - flick.height)
    }
  }
  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  Timer {
    interval: 1000
    running: root.refreshPending !== null
    repeat: true
    onTriggered: { root.refreshClock = Date.now() / 1000; root.refresh() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component { MonitorLogo { color: button.active && button.useActiveColor ? button.activeColor : button.foreground } }
    tooltipText: "Monitor Switcher"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    borderSpec: Border.flat(Util.alpha(Color.foreground, 0.18), 1)
    contentWidth: panel.fittedContentWidth(Style.space(1160))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(root.shortcutsExpanded ? 820 : 600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Omarchy 4.x nests the content holder directly inside its popup card.
      // Scope the softer corners to this instance; leave the global theme alone.
      readonly property var popupSurface: parent && parent.parent && parent.parent.radius !== undefined ? parent.parent : null
      Binding {
        target: keyCatcher.popupSurface
        property: "radius"
        value: Style.space(18)
        when: keyCatcher.popupSurface !== null
      }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onTextKey: function(text) { root.textKey(text) }
      onCloseRequested: {
        if (gallery.closeEditor()) return
        if (root.arranging && !root.refreshPending) root.arranging = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        contentHeight: panelColumn.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding { target: scrollArea.contentItem; property: "interactive"; value: panelColumn.implicitHeight > scrollArea.height }
        // Scrolling moves the control beneath its open popup (Night Light or
        // rotation), whose above/below placement cannot track that: close it.
        Connections {
          target: scrollArea.contentItem
          function onContentYChanged() {
            if (gallery.popupEditor) gallery.closeEditor()
          }
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Style.space(38)
            MonitorLogo {
              id: heroLogo
              width: heroTitle.implicitHeight
              height: width
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: Color.accent
            }
            Text {
              id: heroTitle
              anchors.left: heroLogo.right
              anchors.leftMargin: Style.space(10)
              anchors.right: desktopStatus.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Displays"
              elide: Text.ElideRight
              color: root.bar.foreground
              font.family: root.uiFontFamily
              font.pixelSize: Style.space(22)
              font.weight: Font.DemiBold
            }
            Text {
              id: desktopStatus
              anchors.right: arrangeButton.left
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: root.stateError ? "Unavailable" : root.enabledDisplayCount + " active"
              color: Util.alpha(root.bar.foreground, 0.88)
              font.family: root.uiFontFamily
              font.pixelSize: Style.font.caption
            }
            SettingChip {
              id: arrangeButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.arranging ? "Done" : "Arrange…"
              chevron: false
              selected: root.arranging
              enabled: !root.layoutBusy && root.stateError === ""
              tooltipText: "Rearrange display positions (A)"
              fontFamily: root.uiFontFamily
              onClicked: { gallery.closeEditor(); root.arranging = !root.arranging }
            }
          }

          Text {
            width: parent.width
            text: root.arranging ? "Match your desktop to the displays on your desk."
              : "Click a setting to edit. Click a display to focus."
            color: Util.alpha(root.bar.foreground, 0.88)
            font.family: root.uiFontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            visible: root.visibleError !== ""
            text: root.visibleError
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: Color.urgent
            font.family: root.uiFontFamily
            font.pixelSize: Style.font.caption
          }

          SettingChip {
            visible: root.actionError !== "" || root.brightnessError !== "" || root.textSizeError !== "" || root.nightLightError !== ""
            text: "Dismiss"
            chevron: false
            onClicked: { root.actionError = ""; root.brightnessError = ""; root.textSizeError = ""; root.nightLightError = "" }
          }

          Text {
            width: parent.width
            visible: root.actionNotice !== ""
            text: root.actionNotice
            wrapMode: Text.WordWrap
            color: Util.alpha(root.bar.foreground, 0.88)
            font.family: root.uiFontFamily
            font.pixelSize: Style.font.caption
          }

          SettingChip {
            visible: root.shortcutsExpanded || root.actionError !== ""
            text: "Restore working layout…"
            chevron: false
            enabled: !root.layoutBusy && root.stateError === ""
            tooltipText: "Preview the last verified layout saved for these connected monitors"
            onClicked: root.runAction("recover", "", "")
          }

          DisplayGallery {
            id: gallery
            width: parent.width
            visible: !root.arranging
            monitors: root.galleryMonitors
            focusedMonitor: root.focusedMonitor
            foreground: root.bar.foreground
            fontFamily: root.uiFontFamily
            busy: root.layoutBusy || root.nightLightBusy
            focusBlocked: root.sharedActionRunning
            stale: root.stateError !== ""
            enabledCount: root.enabledDisplayCount
            pending: root.refreshPending
            pendingPowerOutput: actionProc.running && (root.actionVerb === "enable" || root.actionVerb === "disable") ? root.actionTarget : ""
            pendingPowerOn: root.actionVerb === "enable"
            seconds: root.refreshSeconds
            confirmationIndex: root.cursorActive && root.focusSection === "confirmation" ? root.selectedIndex : -1
            cursorIndex: root.cursorActive && root.focusSection === "monitors" ? root.selectedIndex : -1
            onToggleRequested: function(output, currentlyEnabled) { root.toggleDisplay(output, currentlyEnabled) }
            onFocusRequested: function(output) { root.runAction("focus", output, "") }
            onNightLightRequested: function(output, value) { PanelRegistry.setNightLight(output, value) }
            onSettingRequested: function(verb, output, value) { root.runAction(verb, output, value) }
            onConfirmRequested: function(keep) { if (root.refreshPending) root.runAction(keep ? "confirm" : "revert", root.refreshPending.token, "") }
            onCursorRequested: function(index) {
              if (root.reflowingText) return
              root.focusSection = "monitors"
              root.selectedIndex = index
              root.cursorActive = true
            }
            onCursorItemChanged: function(item) { root.ensureCursorVisible(item) }
          }

          ArrangementEditor {
            id: arrangement
            width: parent.width
            visible: root.arranging
            monitors: root.displays
            busy: root.layoutBusy || root.stateError !== ""
            pending: root.refreshPending
            seconds: root.refreshSeconds
            fontFamily: root.uiFontFamily
            confirmationIndex: root.cursorActive && root.focusSection === "confirmation" ? root.selectedIndex : -1
            onApplyRequested: function(positions) { root.runAction("arrange", positions, "") }
            onConfirmRequested: function(keep) { if (root.refreshPending) root.runAction(keep ? "confirm" : "revert", root.refreshPending.token, "") }
          }

          Column {
            width: parent.width
            visible: root.brightnessAvailable && !root.arranging
            spacing: Style.space(4)
            Item {
              width: parent.width
              implicitHeight: brightnessHeader.implicitHeight
              PanelSectionHeader {
                id: brightnessHeader
                text: "Brightness · " + (root.focusedMeta.alias || root.focusedMonitor)
                foreground: root.bar.foreground
                fontFamily: root.uiFontFamily
              }
              Text {
                anchors.right: parent.right
                text: root.brightnessPercent + "%"
                color: Util.alpha(root.bar.foreground, 0.88)
                font.family: root.uiFontFamily
                font.pixelSize: Style.font.caption
              }
            }
            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight
              hasCursor: root.cursorActive && root.focusSection === "brightness"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true
              DragSlider {
                id: brightnessSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                bar: root.bar
                minimum: 1
                maximum: 100
                step: 1
                integer: true
                value: root.brightnessPercent
                onMoved: function(v) { root.brightnessPercent = Model.clampBrightness(v); brightnessDebounce.restart() }
                onReleased: function(v) { brightnessDebounce.stop(); root.setBrightness(v) }
                onScrollRequested: function(pixels) { root.scrollPanel(pixels) }
              }
              HoverHandler { onHoveredChanged: if (hovered) root.hoverSection("brightness") }
            }
          }

          Column {
            width: parent.width
            visible: !root.arranging
            spacing: Style.space(4)
            Item {
              width: parent.width
              implicitHeight: textHeader.implicitHeight
              PanelSectionHeader {
                id: textHeader
                text: "Text size"
                foreground: root.bar.foreground
                fontFamily: root.uiFontFamily
              }
              Text {
                anchors.right: parent.right
                text: (root.textSizePreviewIndex >= 0 ? root.textSizeStops[root.textSizePreviewIndex] : Style.font.baseSize) + "px"
                color: Util.alpha(root.bar.foreground, 0.88)
                font.family: root.uiFontFamily
                font.pixelSize: Style.font.caption
              }
            }
            CursorSurface {
              id: textRow
              width: parent.width
              height: textSlider.implicitHeight
              hasCursor: root.cursorActive && root.focusSection === "textsize"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textRow)
              foreground: root.bar.foreground
              outline: true
              DragSlider {
                id: textSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                bar: root.bar
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(Math.round(v)) }
                onScrollRequested: function(pixels) { root.scrollPanel(pixels) }
              }
              HoverHandler { onHoveredChanged: if (hovered) root.hoverSection("textsize") }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(shortcutLabel.implicitHeight, shortcutButton.implicitHeight)
            Text {
              id: shortcutLabel
              anchors.left: parent.left
              anchors.right: shortcutButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: "Keyboard shortcut: Super + Shift + Ctrl + 1…" + Math.max(1, root.displays.length)
              color: Util.alpha(root.bar.foreground, 0.88)
              font.family: root.uiFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            SettingChip {
              id: shortcutButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.shortcutsExpanded ? "Fewer shortcuts" : "More shortcuts"
              selected: root.shortcutsExpanded
              tooltipText: "Show optional keyboard controls (?)"
              fontFamily: root.uiFontFamily
              onClicked: root.shortcutsExpanded = !root.shortcutsExpanded
            }
          }

          Rectangle {
            width: parent.width
            visible: root.shortcutsExpanded
            implicitHeight: shortcutHelp.implicitHeight + Style.space(20)
            radius: Style.space(12)
            color: Util.alpha(Color.foreground, 0.035)
            Column {
              id: shortcutHelp
              x: Style.space(12)
              y: Style.space(10)
              width: parent.width - Style.space(24)
              spacing: Style.space(6)
              Repeater {
                model: root.arranging ? [
                  ["Arrow keys", "Place the selected display relative to the reference display"],
                  ["N", "Select the next display"],
                  ["Enter", "Apply the preview, or activate the selected Keep/Revert button"],
                  ["Esc", "Return to display settings"]
                ] : [
                  ["↑ / ↓ or J / K", "Select a display or control"],
                  ["← / → or H / L", "Select an option or adjust a slider"],
                  ["Enter / Space", "Focus a display or apply the selected option"],
                  ["M / R / S", "Open resolution / refresh rate / scaling settings"],
                  ["T", "Open Night Light temperature for this display"],
                  ["O", "Rotate the selected display (portrait or landscape)"],
                  ["P", "Turn the selected display on or off"],
                  ["A", "Open display arrangement"],
                  ["Esc", "Close settings, then close the panel"]
                ]
                Item {
                  required property var modelData
                  width: shortcutHelp.width
                  implicitHeight: Math.max(shortcutKeys.implicitHeight, shortcutDescription.implicitHeight)
                  Text {
                    id: shortcutKeys
                    width: Style.space(125)
                    text: modelData[0]
                    color: Color.foreground
                    font.family: root.uiFontFamily
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                  }
                  Text {
                    id: shortcutDescription
                    anchors.left: shortcutKeys.right
                    anchors.right: parent.right
                    text: modelData[1]
                    wrapMode: Text.WordWrap
                    color: Util.alpha(Color.foreground, 0.65)
                    font.family: root.uiFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
