// === monitor-switcher fork =================================================
// Vendored from Omarchy 4.0.0: shell/plugins/panels/monitor/Panel.qml
// Upstream: https://github.com/basecamp/omarchy (MIT, (c) David Heinemeier
// Hansson). See UPSTREAM.md for the full patch list and re-sync procedure.
// Every local change is marked with a "monitor-switcher fork" comment —
// grep for that phrase to audit the delta against upstream.
// ===========================================================================
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  // monitor-switcher fork: own ids so coexisting with omarchy.monitor can
  // never collide on the shell's single-handler IPC targets.
  moduleName: "case.monitor-switcher"
  ipcTarget: "case.monitor-switcher"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0

  // monitor-switcher fork: supported refresh stops and independent backend confirmation.
  readonly property var focusedMeta: switcherMeta[focusedMonitor] || ({})
  readonly property var refreshModes: focusedMeta.enabled ? (focusedMeta.refreshModes || []) : []
  readonly property var galleryMonitors: Object.keys(switcherMeta)
    .map(function(key) { return root.switcherMeta[key] })
    .filter(function(m) { return m.connected })
    .sort(function(a, b) { return a.num - b.num })
  property var refreshPending: null
  property double refreshClock: Date.now() / 1000
  property int refreshPreviewIndex: -1
  property string refreshPreviewOutput: ""
  property real refreshPreviewRate: 0
  property string actionError: ""
  readonly property bool layoutBusy: actionProc.running || refreshProc.running || refreshPending !== null
  readonly property int refreshSeconds: refreshPending ? Math.max(0, Math.ceil(refreshPending.expiresAt - refreshClock)) : 0
  readonly property int liveRefreshIndex: Model.matchingRefreshIndex(refreshModes, focusedMeta.refreshRate)
  readonly property int refreshIndex: refreshPreviewIndex >= 0 ? refreshPreviewIndex : Math.max(0, liveRefreshIndex)

  function previewRefresh(index) {
    if (layoutBusy || !refreshModes[index]) return
    if (refreshPreviewOutput !== "" && refreshPreviewOutput !== focusedMonitor) return
    refreshPreviewOutput = focusedMonitor
    refreshPreviewRate = refreshModes[index].rate
    refreshPreviewIndex = index
  }

  function commitRefresh() {
    if (layoutBusy || refreshPreviewIndex < 0) return
    var output = refreshPreviewOutput
    var rate = refreshPreviewRate
    refreshPreviewOutput = ""
    if (!output || output !== focusedMonitor
        || Math.round(Number(focusedMeta.refreshRate) * 100) === Math.round(rate * 100)) {
      refreshPreviewIndex = -1
      return
    }
    runRefreshAction("refresh", output, String(rate))
  }

  function runRefreshAction(verb, id, value) {
    if (refreshProc.running || actionProc.running) return
    actionError = ""
    // pipefail preserves backend failures despite the bounded collector.
    refreshProc.command = ["bash", "-o", "pipefail", "-c", "\"$1\" \"$2\" \"$3\" ${4:+\"$4\"} 2>&1 | head -c 65536",
      "monitor-switcher", root.scriptPath, verb, id, value || ""]
    refreshProc.running = true
  }

  // monitor-switcher fork: gallery buttons and sliders share the keyboard cursor.
  // Slider rows use -1; gallery and confirmation buttons use their item index.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  readonly property var scaleValues: Model.scaleStops(scalePresets, focusedMeta.scale,
    focusedMeta.configuredWidth, focusedMeta.configuredHeight)
  property int scalePreviewIndex: -1
  property string scalePreviewOutput: ""
  property string scalePreviewValue: ""
  readonly property int scaleIndex: scalePreviewIndex >= 0 ? scalePreviewIndex : Math.max(0, activeScaleIndex())
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    if (refreshPending) list.push("confirmation") // monitor-switcher fork
    if (galleryMonitors.length > 0) list.push("monitors")
    if (refreshModes.length > 0) list.push("refresh")
    if (brightnessAvailable) list.push("brightness")
    list.push("textsize")
    list.push("scale")
    return list
  }

  function sectionCount(section) {
    if (section === "confirmation") return 2 // monitor-switcher fork: Revert / Keep
    if (section === "refresh") return 0
    if (section === "brightness") return 0  // only the slider sentinel at -1
    if (section === "textsize") return 0    // slider sentinel at -1, like brightness
    if (section === "scale") return 0
    if (section === "monitors") return galleryMonitors.length
    return 0
  }

  function sectionIsSingleRow(section) {
    // Keep j/k walking every monitor, as in the original display list.
    return section === "brightness" || section === "textsize" || section === "scale"
      || section === "refresh" || section === "confirmation"
  }

  function sectionFirstIndex(section) {
    if (section === "brightness" || section === "textsize" || section === "refresh" || section === "scale") return -1
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l walks gallery and confirmation buttons without activating them.
  function moveCursorH(delta) {
    if (focusSection !== "monitors" && focusSection !== "confirmation") return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > sectionCount(focusSection) - 1) next = sectionCount(focusSection) - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    // monitor-switcher fork: keyboard previews refresh with h/l, Enter applies.
    if (focusSection === "refresh") { commitRefresh(); return }
    if (focusSection === "confirmation" && refreshPending) {
      runRefreshAction(selectedIndex === 1 ? "confirm" : "revert", refreshPending.token, "")
      return
    }
    if (focusSection === "scale") { commitScale(); return }
    if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < galleryMonitors.length) {
      var d = galleryMonitors[selectedIndex]
      if (d) toggleDisplay(d.output, d.enabled)
    }
    // brightness: no separate action; the slider value is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      if (focusSection === "brightness" || focusSection === "textsize" || focusSection === "refresh" || focusSection === "scale") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function scrollPanel(pixels) {
    var flick = scrollArea.contentItem
    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY - pixels))
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      scale: root.monitorScale,
      refreshRate: root.focusedMeta.refreshRate || null, // monitor-switcher fork
      refreshModes: root.refreshModes,
      refreshPending: root.refreshPending,
      actionError: root.actionError,
      displays: root.displays
    })
  }

  IpcHandler {
    target: "case.monitor-switcher" // monitor-switcher fork

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!switcherProc.running) switcherProc.running = true // monitor-switcher fork
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    // monitor-switcher fork: bound collector input (StdioCollector has no limit)
    setBrightnessProc.command = ["bash", "-c", "omarchy-brightness-display --no-osd --monitor \"$1\" \"$2\" | head -c 65536", "monitor-switcher", root.focusedMonitor, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    return Model.matchingScaleIndex(scaleValues, focusedMeta.scale,
      focusedMeta.configuredWidth, focusedMeta.configuredHeight)
  }

  function effectiveScale(scale) {
    return Model.cleanScale(scale, focusedMeta.configuredWidth, focusedMeta.configuredHeight)
  }

  function previewScale(index) {
    if (layoutBusy || !scaleValues[index]) return
    if (scalePreviewOutput !== "" && scalePreviewOutput !== focusedMonitor) return
    scalePreviewOutput = focusedMonitor
    scalePreviewValue = scaleValues[index]
    scalePreviewIndex = index
  }

  function commitScale() {
    if (layoutBusy || scalePreviewIndex < 0) return
    var output = scalePreviewOutput
    var value = scalePreviewValue
    scalePreviewOutput = ""
    if (!output || output !== focusedMonitor || normalizeScale(effectiveScale(value)) === normalizeScale(focusedMeta.scale)) {
      scalePreviewIndex = -1
      return
    }
    setScale(value)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  // === monitor-switcher fork: persistent toggles ===========================
  // Upstream ran `hyprctl keyword monitor X,disable` here — runtime-only,
  // reverted by omarchy-hyprland-monitor-watch, and re-enabling forgot the
  // monitor's position (auto placement). Route through the plugin backend
  // instead: state is written to a generated Lua file in Omarchy's toggle
  // directory, so off-states survive reloads/reboots and each monitor keeps
  // its position/scale/mode. actionProc's exit already triggers refresh(),
  // and the backend's hyprctl reload has settled state by then.
  readonly property string scriptPath: {
    var u = Qt.resolvedUrl("bin/monitor-switcher").toString()
    return u.replace(/^file:\/\//, "")
  }

  // The backend persists via hyprctl reload; when a toggle changes the
  // enabled-screen count the bar remaps and this popup's surface closes.
  // Reopen it once the action settles so multi-toggle flows stay in place.
  // (If the toggled-off monitor owned this bar, this instance is gone and
  // nothing reopens — the surface it lived on no longer exists.)
  property bool reopenAfterAction: false

  Timer {
    id: reopenTimer
    interval: 600
    repeat: false
    onTriggered: root.open()
  }

  function toggleDisplay(name, enabled) {
    if (!name || root.layoutBusy) return // monitor-switcher fork: serialize layout actions
    if (enabled && root.enabledDisplayCount <= 1) return

    root.reopenAfterAction = root.opened
    // Bound the collector input at the source: the installed StdioCollector
    // has no size limit, so cap bytes here (SIGPIPE contains a flood).
    actionError = ""
    actionProc.command = ["bash", "-o", "pipefail", "-c", "\"$1\" toggle \"$2\" 2>&1 | head -c 65536", "monitor-switcher", root.scriptPath, name]
    if (!actionProc.running) actionProc.running = true
  }
  // === end monitor-switcher fork ===========================================

  function setScale(scale) {
    if (root.layoutBusy) return // monitor-switcher fork
    // monitor-switcher fork: route scale through the backend — persisted in
    // config.json and re-applied through the overlap validator, instead of
    // the upstream tool's runtime-only position="auto" poke that our
    // generated layout reverts on the next reload (and whose mode string,
    // built from the live refresh rate, some panels reject outright).
    // Still bounded: StdioCollector has no limit.
    actionError = ""
    actionProc.command = ["bash", "-o", "pipefail", "-c", "\"$1\" scale \"$2\" \"$3\" 2>&1 | head -c 65536", "monitor-switcher", root.scriptPath, root.focusedMonitor, scale]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(Style.font.baseSize)
  }

  // px shown in the header: the pending stop if any, else the true base-size
  // (which may be an off-notch value set from the CLI).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSize(px) {
    // monitor-switcher fork: bound collector input (StdioCollector has no limit)
    textScaleProc.command = ["bash", "-c", "omarchy-display-text-size \"$1\" | head -c 65536", "monitor-switcher", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    markReflowing()
    textSizePreviewIndex = idx
    setTextSize(textSizeStops[idx])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // monitor-switcher fork: re-read state on hotplug. Quickshell.screens
  // tracks enabled outputs, so plug/unplug (and external keybind toggles)
  // refresh promptly instead of waiting for open-time / the 5s open-poll.
  readonly property int enabledScreenCount: Quickshell.screens.length
  onEnabledScreenCountChanged: root.refresh()

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      refresh()
      if (refreshPending) { // monitor-switcher fork: prioritize safe confirmation
        focusSection = "confirmation"
        selectedIndex = 0
      } else if (galleryMonitors.length > 0) {
        focusSection = "monitors"
        selectedIndex = Math.max(0, galleryMonitors.findIndex(function(m) { return m.output === root.focusedMonitor }))
      } else if (brightnessAvailable) {
        focusSection = "brightness"
        selectedIndex = -1
      } else {
        focusSection = "scale"
        selectedIndex = -1
      }
      cursorActive = false
    } else if (!refreshProc.running) {
      refreshPreviewIndex = -1
      refreshPreviewOutput = ""
      if (!actionProc.running) {
        scalePreviewIndex = -1
        scalePreviewOutput = ""
      }
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: clampCursor()
  onScaleValuesChanged: clampCursor()
  onGalleryMonitorsChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()
  // monitor-switcher fork: an uncommitted keyboard preview must not follow focus.
  onFocusedMonitorChanged: {
    if (!scaleSlider.dragging) {
      scalePreviewIndex = -1
      scalePreviewOutput = ""
    }
    if (!refreshSlider.dragging) {
      refreshPreviewIndex = -1
      refreshPreviewOutput = ""
    }
  }
  onRefreshPendingChanged: {
    refreshClock = Date.now() / 1000
    if (refreshPending) {
      refreshPreviewIndex = -1
      refreshPreviewOutput = ""
      focusSection = "confirmation"
      selectedIndex = 0
      cursorActive = true
    }
  }

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    // monitor-switcher fork: bound collector input (StdioCollector has no limit)
    command: ["bash", "-c", "omarchy-monitor-state | head -c 65536"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
      }
    }
  }

  // === monitor-switcher fork: alias + resolution row metadata ==============
  // Upstream rows show only the output name. Merge the backend's per-monitor
  // metadata (alias + configured scale) keyed by output name; rows render
  // "alias · focused" plus a "WxH @scalex" caption, and the BRIGHTNESS header
  // names its target. All upstream state logic (guards, focus, counts) still
  // runs on root.displays — this map is display-only.
  property var switcherMeta: ({})

  Process {
    id: switcherProc
    // monitor-switcher fork: bound collector input (StdioCollector has no limit)
    command: ["bash", "-o", "pipefail", "-c", "\"$1\" state --json | head -c 262144", "monitor-switcher", root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var map = {}
        try {
          var parsed = JSON.parse(String(text || ""))
          var list = parsed && parsed.monitors
          if (!Array.isArray(list)) return
          if (list) {
            for (var i = 0; i < list.length; i++) {
              var m = list[i]
              if (m && m.output) map[m.output] = m
            }
          }
          // monitor-switcher fork: do not reset the keyboard cursor on each countdown poll.
          var pending = parsed.refreshPending || null
          if (JSON.stringify(pending) !== JSON.stringify(root.refreshPending)) root.refreshPending = pending
        } catch (e) { return }
        root.switcherMeta = map
      }
    }
  }
  // === end monitor-switcher fork ===========================================

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0 —
    // visible as a "bounce to zero" after h/l keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
    // monitor-switcher fork: reopen the popup after a successful toggle
    // (the backend's reload closed the surface). Failed toggles (e.g. the
    // last-display guard) never closed anything, so nothing reopens.
    onExited: function(exitCode) {
      if (exitCode !== 0) root.actionError = String(actionOutput.text || "Display change failed").trim()
      root.scalePreviewIndex = -1
      root.scalePreviewOutput = ""
      if (root.reopenAfterAction) {
        root.reopenAfterAction = false
        if (exitCode === 0) reopenTimer.restart()
      }
    }
  }

  // monitor-switcher fork: the backend watchdog outlives this popup and the shell.
  Process {
    id: refreshProc
    stdout: StdioCollector { id: refreshOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.actionError = String(refreshOutput.text || "Refresh change failed").trim()
      root.refreshPreviewIndex = -1
      root.refreshPreviewOutput = ""
      root.refresh()
      if (exitCode === 0 && !root.opened) reopenTimer.restart()
    }
  }

  Timer {
    interval: 1000
    running: root.refreshPending !== null
    repeat: true
    onTriggered: {
      root.refreshClock = Date.now() / 1000
      if (!switcherProc.running) switcherProc.running = true
    }
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once Style's base-size catches up to the pending choice, drop the preview
  // so the slider tracks the live value again. The change itself reflows the
  // panel, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextStop(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // monitor-switcher fork: stable vector identity, independent of font glyphs.
    iconComponent: Component {
      MonitorLogo {
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      }
    }
    tooltipText: "Monitor Switcher" // monitor-switcher fork
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420)) // monitor-switcher fork: gallery breathing room
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else if (root.focusSection === "refresh") root.previewRefresh(Math.max(0, Math.min(root.refreshModes.length - 1, root.refreshIndex + dx)))
          else if (root.focusSection === "scale") root.previewScale(Math.max(0, Math.min(root.scaleValues.length - 1, root.scaleIndex + dx)))
          else if (root.focusSection === "monitors" || root.focusSection === "confirmation") root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- monitor-switcher fork: display gallery / live readout ----------
          Item {
            width: parent.width
            implicitHeight: heroTitle.implicitHeight

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
              text: "Monitor Switcher"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.left: heroLogo.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: desktopStatus.left
              anchors.rightMargin: Style.space(10)
              elide: Text.ElideRight
            }

            Text {
              id: desktopStatus
              text: root.enabledDisplayCount + " ACTIVE"
              color: Util.alpha(root.bar.foreground, 0.55)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Column {
            id: confirmationRow
            width: parent.width
            visible: root.refreshPending !== null
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: root.refreshPending && root.refreshPending.reverting ? "Restoring the previous display mode..."
                : root.refreshPending ? "Keep this refresh rate on " + ((root.switcherMeta[root.refreshPending.output] || {}).alias || root.refreshPending.output) + "?" : ""
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: ["Revert", "Keep"]
                Button {
                  required property string modelData
                  required property int index
                  width: (confirmationRow.width - Style.space(8)) / 2
                  text: modelData === "Revert" ? "Revert (" + root.refreshSeconds + "s)" : "Keep"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  fontSize: Style.font.body
                  bordered: true
                  active: index === 1
                  enabled: !refreshProc.running && !(index === 1 && root.refreshPending && root.refreshPending.reverting)
                  hasCursor: root.cursorActive && root.focusSection === "confirmation" && root.selectedIndex === index
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(confirmationRow)
                  onClicked: if (root.refreshPending) root.runRefreshAction(index === 1 ? "confirm" : "revert", root.refreshPending.token, "")
                  onHovered: function(hovered) {
                    if (!hovered || root.reflowingText) return
                    root.focusSection = "confirmation"
                    root.selectedIndex = index
                    root.cursorActive = true
                  }
                }
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(2)
              color: Util.alpha(Color.accent, 0.15)
              Rectangle {
                width: parent.width * Math.min(1, root.refreshSeconds / 20)
                height: parent.height
                color: Color.accent
                Behavior on width { NumberAnimation { duration: 180 } }
              }
            }
          }

          Text {
            visible: root.actionError !== ""
            width: parent.width
            text: root.actionError
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          DisplayGallery {
            width: parent.width
            monitors: root.galleryMonitors
            focusedMonitor: root.focusedMonitor
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            busy: root.layoutBusy
            enabledCount: root.enabledDisplayCount
            cursorIndex: root.cursorActive && root.focusSection === "monitors" ? root.selectedIndex : -1
            onToggleRequested: function(output, currentlyEnabled) { root.toggleDisplay(output, currentlyEnabled) }
            onCursorRequested: function(index) {
              if (root.reflowingText) return
              root.focusSection = "monitors"
              root.selectedIndex = index
              root.cursorActive = true
            }
            onCursorItemChanged: function(item) { root.ensureCursorVisible(item) }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(liveRate.implicitHeight, focusLabels.implicitHeight)

            Column {
              id: focusLabels
              anchors.left: parent.left
              anchors.right: liveRate.left
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                width: parent.width
                text: root.focusedMeta.alias || root.focusedMonitor || "Your display"
                textFormat: Text.PlainText
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.focusedMeta.width > 0 ? root.focusedMeta.width + " x " + root.focusedMeta.height + " / " + root.focusedMeta.scale + "x" : "Reading display..."
                color: Util.alpha(root.bar.foreground, 0.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Column {
              id: liveRate
              anchors.right: parent.right
              spacing: Style.space(2)

              Text {
                text: Model.formatRefreshRate(root.focusedMeta.refreshRate) + " Hz"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.space(34)
                font.weight: Font.DemiBold
                font.letterSpacing: -1
              }
              Text {
                anchors.right: parent.right
                text: root.refreshPending && root.refreshPending.reverting ? "REVERTING" : refreshProc.running ? "APPLYING" : "LIVE REFRESH"
                color: Util.alpha(root.bar.foreground, 0.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(5)
            visible: root.refreshModes.length > 0

            Item {
              width: parent.width
              implicitHeight: refreshHeader.implicitHeight

              PanelSectionHeader {
                id: refreshHeader
                text: "REFRESH RATE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }
              Text {
                anchors.right: parent.right
                text: root.refreshPreviewIndex >= 0 ? Model.formatRefreshRate(root.refreshPreviewRate) + " Hz preview" : ""
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            CursorSurface {
              id: refreshRow
              width: parent.width
              height: refreshSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "refresh"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(refreshRow)
              foreground: root.bar.foreground
              outline: true
              opacity: root.layoutBusy || root.refreshModes.length < 2 ? 0.45 : 1

              DragSlider {
                id: refreshSlider
                onScrollRequested: function(pixels) { root.scrollPanel(pixels) }
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                bar: root.bar
                enabled: !root.layoutBusy && root.refreshModes.length > 1
                minimum: 0
                maximum: Math.max(1, root.refreshModes.length - 1)
                integer: true
                step: 1
                tickCount: root.refreshModes.length
                fillColor: Color.accent
                knobColor: Color.accent
                value: root.refreshIndex
                onMoved: function(v) { root.previewRefresh(Math.round(v)) }
                onReleased: function(v) { root.commitRefresh() }
              }
              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText && !root.refreshPending) {
                  root.focusSection = "refresh"
                  root.selectedIndex = -1
                  root.cursorActive = true
                }
              }
            }

            Item {
              width: parent.width
              implicitHeight: Style.font.caption * 1.5
              Repeater {
                model: root.refreshModes
                Text {
                  required property var modelData
                  required property int index
                  readonly property real labelSpace: Math.max(1, (parent.width - Style.space(16)) / Math.max(1, root.refreshModes.length - 1))
                  width: Math.min(implicitWidth, labelSpace)
                  x: Math.max(Style.space(4), Math.min(parent.width - width - Style.space(4),
                    Style.space(8) + index * labelSpace - width / 2))
                  text: Model.formatRefreshRate(modelData.rate)
                  // Dense EDIDs still retain every stop; label endpoints and selection only.
                  visible: root.refreshModes.length <= 6 || index === 0 || index === root.refreshModes.length - 1 || index === root.refreshIndex
                  elide: Text.ElideRight
                  color: index === root.liveRefreshIndex ? Color.accent : Util.alpha(root.bar.foreground, 0.55)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: index === root.liveRefreshIndex
                }
              }
            }

            Text {
              width: parent.width
              text: root.refreshModes.length === 1 ? "Only one rate is advertised at this resolution."
                : root.refreshPreviewIndex >= 0 && !refreshSlider.dragging ? "Press Enter to try this rate."
                : "Supported at this resolution. Release to try; Keep to save."
              color: Util.alpha(root.bar.foreground, 0.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
          // ---------- end monitor-switcher fork ----------

          // ---------- Brightness ----------
          PanelSeparator {
            visible: root.brightnessAvailable
            foreground: root.bar.foreground
          }

          Column {
            visible: root.brightnessAvailable
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                // monitor-switcher fork: name the focused display the slider
                // controls, like the SCALE header does — the slider only ever
                // targets the focused monitor. Gated on managed displays (not
                // enabled ones): with some monitors toggled off, this label is
                // exactly what explains whose brightness this is.
                text: "BRIGHTNESS" + ((root.focusedMonitor !== "" && root.displays.length > 1)
                      ? " · " + String(((root.switcherMeta[root.focusedMonitor] || {}).alias
                        || root.focusedMonitor)).toUpperCase()
                      : "")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: brightnessPercent
                text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true

              DragSlider {
                id: brightnessSlider
                onScrollRequested: function(pixels) { root.scrollPanel(pixels) }
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                minimum: 1
                maximum: 100
                step: 1
                value: root.brightnessPercent
                integer: true
                onMoved: function(v) { root.previewBrightness(v) }
                onReleased: function(v) {
                  brightnessDebounce.stop()
                  root.setBrightness(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "brightness"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: textSizePx
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              DragSlider {
                id: textSizeSlider
                onScrollRequested: function(pixels) { root.scrollPanel(pixels) }
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSize(root.textSizeStops[Math.round(v)]) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Scale ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(scaleHeader.implicitHeight, scaleMonitor.implicitHeight)

              PanelSectionHeader {
                id: scaleHeader
                text: "SCALE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Scale previews and the live value use the same percentage notation.
              Text {
                id: scaleMonitor
                text: Math.round(Number(root.scalePreviewIndex >= 0 ? root.effectiveScale(root.scalePreviewValue) : root.focusedMeta.scale || 1) * 1000) / 10 + "%"
                visible: root.focusedMonitor !== ""
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: scaleRow
              width: parent.width
              height: scaleSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "scale"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(scaleRow)
              foreground: root.bar.foreground
              outline: true
              opacity: root.layoutBusy ? 0.45 : 1

              DragSlider {
                id: scaleSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                bar: root.bar
                enabled: !root.layoutBusy && root.focusedMeta.enabled === true
                minimum: 0
                maximum: Math.max(1, root.scaleValues.length - 1)
                step: 1
                integer: true
                tickCount: root.scaleValues.length
                value: root.scaleIndex
                onMoved: function(v) { root.previewScale(Math.round(v)) }
                onReleased: function(v) { root.commitScale() }
                onScrollRequested: function(pixels) { root.scrollPanel(pixels) }
              }
              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.focusSection = "scale"
                  root.selectedIndex = -1
                  root.cursorActive = true
                }
              }
            }

            Item {
              width: parent.width
              implicitHeight: Style.font.caption * 1.5
              Repeater {
                model: root.scaleValues
                Text {
                  required property string modelData
                  required property int index
                  readonly property real labelSpace: Math.max(1, (parent.width - Style.space(16)) / Math.max(1, root.scaleValues.length - 1))
                  width: Math.min(implicitWidth, labelSpace)
                  x: Math.max(Style.space(4), Math.min(parent.width - width - Style.space(4), Style.space(8) + index * labelSpace - width / 2))
                  text: Math.round(Number(root.effectiveScale(modelData)) * 1000) / 10 + "%"
                  elide: Text.ElideRight
                  color: index === root.activeScaleIndex() ? Color.accent : Util.alpha(root.bar.foreground, 0.55)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: index === root.activeScaleIndex()
                }
              }
            }

            Text {
              visible: root.scalePreviewIndex >= 0 && !scaleSlider.dragging
              width: parent.width
              text: "Press Enter to apply this scale."
              color: Util.alpha(root.bar.foreground, 0.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- monitor-switcher fork: keyboard hint footer ----------
          PanelSeparator {
            visible: root.displays.length > 1
            foreground: root.bar.foreground
          }

          Text {
            width: parent.width
            visible: root.displays.length > 1
            text: "Keyboard shortcut: SUPER+SHIFT+CTRL+1…" + root.displays.length
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

}
