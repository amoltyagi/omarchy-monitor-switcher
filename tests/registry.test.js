const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const vm = require('node:vm')

function fixture() {
  const registry = {}
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../PanelRegistry.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), registry)
  function panel(screenName) {
    const p = { screenName, opened: false, reads: 0, stateError: '',
      refresh() { this.reads++ },
      acceptNightLight(state) { this.nightLight = state },
      writeNightLight(output, value) { this.request = {output, value} },
      acceptSnapshot(state) { this.state = state; this.stateError = '' } }
    registry.register(p)
    return p
  }
  return { registry, panel }
}

test('all panels stay busy through action exit until a post-action snapshot arrives', () => {
  const { registry: r, panel } = fixture()
  const lg = panel('LG'), msi = panel('MSI')
  const before = r.startRead()
  assert.equal(r.beginAction(lg), true)
  assert.equal(lg.sharedActionRunning, true)
  assert.equal(msi.sharedActionRunning, true)
  assert.equal(r.beginAction(msi), false)
  const during = r.startRead()
  r.actionFinished(lg)
  assert.equal(msi.sharedActionRunning, true, 'process exit must not reopen the click race')
  assert.equal(r.publishSnapshot({ refreshPending: null }, before), false)
  assert.equal(r.publishSnapshot({ refreshPending: null }, during), false)
  assert.equal(r.beginAction(msi), false)
  const state = { refreshPending: { token: 'current' }, monitors: [] }
  assert.equal(r.publishSnapshot(state, r.startRead()), true)
  assert.equal(lg.state, state)
  assert.equal(msi.state, state)
  assert.equal(msi.sharedActionRunning, false)
  assert.ok(lg.reads && msi.reads)
})

test('late reads cannot erase a newer pending confirmation or resurrect an expired one', () => {
  const { registry: r, panel } = fixture()
  const lg = panel('LG')
  const old = r.startRead(), current = r.startRead()
  const pending = { refreshPending: { token: 'new' }, monitors: [] }
  r.publishSnapshot(pending, current)
  assert.equal(r.publishSnapshot({ refreshPending: null }, old), false)
  assert.equal(lg.state, pending)
  const oldPending = r.startRead(), cleared = r.startRead()
  const complete = { refreshPending: null, monitors: [] }
  r.publishSnapshot(complete, cleared)
  assert.equal(r.publishSnapshot(pending, oldPending), false)
  assert.equal(lg.state, complete)
})

test('removing the action-owning monitor transfers IPC and reconciles on a survivor', () => {
  const { registry: r, panel } = fixture()
  const msi = panel('MSI'), lg = panel('LG')
  r.beginAction(msi)
  const obsolete = r.startRead()
  r.unregister(msi)
  assert.equal(lg.ipcOwner, true)
  assert.equal(lg.sharedActionRunning, true)
  assert.ok(lg.reads > 0)
  assert.equal(r.publishSnapshot({ refreshPending: null }, obsolete), false)
  r.publishSnapshot({ refreshPending: null, monitors: [] }, r.startRead())
  assert.equal(lg.sharedActionRunning, false)
  assert.equal(r.activePanel('LG'), lg)
})

test('read failures release reconciliation and never discard a concurrent in-flight success', () => {
  const { registry: r, panel } = fixture()
  const lg = panel('LG'), msi = panel('MSI')
  r.beginAction(lg)
  r.actionFinished(lg)
  const inflight = r.startRead(), failed = r.startRead()
  r.readFailed('Compositor unavailable', failed)
  assert.equal(lg.sharedActionRunning, false)
  assert.equal(msi.stateError, 'Compositor unavailable')
  // The success started before the failure but carries valid data: it publishes.
  const good = { monitors: [{ output: 'DP-1' }] }
  assert.equal(r.publishSnapshot(good, inflight), true)
  assert.equal(msi.state, good)
  assert.equal(msi.stateError, '')
  // A failure newer than the last published success still surfaces.
  r.readFailed('Compositor unavailable again', r.startRead())
  assert.equal(msi.stateError, 'Compositor unavailable again')
  // A failure older than the last published success is ignored.
  const oldFail = r.startRead()
  r.publishSnapshot({ monitors: [] }, r.startRead())
  r.readFailed('stale failure', oldFail)
  assert.equal(msi.stateError, '')
})

test('new panels inherit the pending snapshot and current operation fence', () => {
  const { registry: r, panel } = fixture()
  const first = panel('LG')
  const pending = { refreshPending: { token: 'current' }, monitors: [] }
  r.publishSnapshot(pending, r.startRead())
  r.beginAction(first)
  const next = panel('MSI')
  assert.equal(next.state, pending)
  assert.equal(next.sharedActionRunning, true)
  assert.equal(r.beginAction(next), false)
})

test('reopening synchronizes external changes before cached controls can run', () => {
  const { registry: r, panel } = fixture()
  const lg = panel('LG')
  r.publishSnapshot({ refreshPending: null, monitors: [] }, r.startRead())
  const old = r.startRead()
  r.synchronize()
  assert.equal(lg.sharedActionRunning, true)
  assert.equal(r.beginAction(lg), false)
  assert.equal(r.publishSnapshot({ refreshPending: null }, old), false)
  r.publishSnapshot({ refreshPending: { token: 'external' }, monitors: [] }, r.startRead())
  assert.equal(lg.state.refreshPending.token, 'external')
  assert.equal(lg.sharedActionRunning, false)
})


test('night light routes to one owner and publishes independent monitor state to every panel', () => {
  const {registry: r, panel} = fixture()
  const a = panel('DP-1'), b = panel('DP-2')
  r.setNightLight('DP-2', '4000')
  assert.deepEqual(a.request, {output: 'DP-2', value: '4000'})
  assert.equal(b.request, undefined)
  assert.equal(b.nightLightBusy, true)
  const state = {ready: true, monitors: {'DP-2': {active: true, temperature: 4000}}}
  r.publishNightLight(state)
  assert.equal(a.nightLight, state)
  assert.equal(b.nightLight, state)
  assert.equal(b.nightLightBusy, false)
})
