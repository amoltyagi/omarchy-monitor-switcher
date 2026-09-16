.pragma library

// Panel.qml is instantiated once per screen. Only one owns the IPC target;
// route requests to the focused screen and hand ownership over on hotplug.
var panels = []
var generation = 0
var readSerial = 0
var publishedSerial = 0
var actionOwner = null
var reconciling = false
var snapshot = null
var snapshotError = ""
var nightLightSnapshot = null
var nightLightBusy = false

function updateBusy() {
  panels.forEach(function(p) { p.sharedActionRunning = actionOwner !== null || reconciling })
}

function refreshAll() { panels.forEach(function(p) { p.refresh() }) }

function synchronize() {
  // Reopening a panel must not act on a cached snapshot from before a CLI or
  // shortcut change. An in-flight action already owns the stronger fence.
  if (actionOwner === null) {
    reconciling = true
    generation++
    updateBusy()
  }
  refreshAll()
}

function register(panel) {
  if (panels.indexOf(panel) < 0) panels.push(panel)
  panel.ipcOwner = panels[0] === panel
  panel.sharedActionRunning = actionOwner !== null || reconciling
  if (snapshot !== null) panel.acceptSnapshot(snapshot)
  panel.stateError = snapshotError
  panel.nightLightBusy = nightLightBusy
  if (nightLightSnapshot !== null) panel.acceptNightLight(nightLightSnapshot)
}

function unregister(panel) {
  panel.ipcOwner = false
  panels = panels.filter(function(p) { return p !== panel })
  if (panels.length) panels[0].ipcOwner = true
  if (actionOwner === panel) {
    // A power change can destroy the initiating screen. Reconcile on a survivor
    // rather than leaving its action lock behind or guessing that it completed.
    actionOwner = null
    reconciling = true
    generation++
    updateBusy()
    refreshAll()
  }
}

function beginAction(panel) {
  if (actionOwner !== null || reconciling) return false
  actionOwner = panel
  generation++
  updateBusy()
  return true
}

function actionFinished(panel) {
  if (actionOwner !== panel) return
  actionOwner = null
  reconciling = true
  generation++
  updateBusy()
  // Controls stay disabled until a read STARTED AFTER this exit has completed.
  refreshAll()
}

function startRead() { return {generation: generation, serial: ++readSerial} }
function outdated(ticket) { return ticket.generation !== generation }

function publishSnapshot(state, ticket) {
  if (outdated(ticket) || actionOwner !== null || ticket.serial < publishedSerial) return false
  publishedSerial = ticket.serial
  snapshot = state
  snapshotError = ""
  panels.forEach(function(p) { p.acceptSnapshot(state) })
  reconciling = false
  updateBusy()
  return true
}

function readFailed(message, ticket) {
  if (outdated(ticket) || actionOwner !== null || ticket.serial < publishedSerial) return
  publishedSerial = ticket.serial
  snapshotError = message
  panels.forEach(function(p) { p.stateError = message })
  reconciling = false
  updateBusy()
}

function activePanel(screenName) {
  return panels.find(function(p) { return p.screenName === screenName })
    || panels.find(function(p) { return p.opened }) || panels[0]
}


function publishNightLight(state) {
  nightLightSnapshot = state
  nightLightBusy = false
  panels.forEach(function(p) { p.nightLightBusy = false; p.acceptNightLight(state) })
}

function setNightLight(output, value) {
  if (nightLightBusy) return
  var owner = panels.find(function(p) { return p.ipcOwner })
  if (!owner) return
  nightLightBusy = true
  panels.forEach(function(p) { p.nightLightBusy = true })
  owner.writeNightLight(output, value)
}
