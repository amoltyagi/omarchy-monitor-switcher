.pragma library

// Panel.qml is instantiated once per screen. Only one owns the IPC target;
// route requests to the focused screen and hand ownership over on hotplug.
var panels = []

function register(panel) {
  if (panels.indexOf(panel) < 0) panels.push(panel)
  panel.ipcOwner = panels[0] === panel
}

function unregister(panel) {
  panel.ipcOwner = false
  panels = panels.filter(function(p) { return p !== panel })
  if (panels.length) panels[0].ipcOwner = true
}

function activePanel(screenName) {
  return panels.find(function(p) { return p.screenName === screenName })
    || panels.find(function(p) { return p.opened }) || panels[0]
}
