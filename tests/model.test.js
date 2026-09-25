const { test } = require('node:test')
const assert = require('node:assert/strict')
const Model = require('../Model.js')

test('Hz labels retain fractional modes without live timing noise', () => {
  assert.equal(Model.formatRefreshRate(59.997), '60')
  assert.equal(Model.formatRefreshRate(59.94), '59.94')
  assert.equal(Model.formatRefreshRate(239.999), '240')
  for (const value of [null, undefined, NaN, Infinity, 0, -1])
    assert.equal(Model.formatRefreshRate(value), '--')
})

test('refresh selection matches advertised precision, not nearby fractional modes', () => {
  const modes = [{ rate: 59.94 }, { rate: 60 }, { rate: 120 }, { rate: 240 }]
  assert.equal(Model.matchingRefreshIndex(modes, 59.997), 1)
  assert.equal(Model.matchingRefreshIndex(modes, 59.939), 0)
  assert.equal(Model.matchingRefreshIndex(modes, 240.001), 3)
  assert.equal(Model.matchingRefreshIndex(modes, 75), -1)
  assert.equal(Model.matchingRefreshIndex([], 60), -1)
  assert.equal(Model.matchingRefreshIndex(modes, null), -1)
  assert.equal(Model.matchingRefreshIndex([{ rate: 59.99 }, { rate: 60 }], 59.997), 1)
  assert.equal(Model.matchingRefreshIndex([{ rate: 60 }], 59.99), -1)
})

test('gallery uses configured dimensions for disabled screens and honors rotation', () => {
  assert.equal(Model.displayAspectRatio({ configuredWidth: 3840, configuredHeight: 1600, width: 0, height: 0 }), 2.4)
  assert.equal(Model.displayAspectRatio({ configuredWidth: 3840, configuredHeight: 2160, transform: 1 }), 2160 / 3840)
  assert.equal(Model.displayAspectRatio({ width: 1920, height: 1080, transform: 2 }), 16 / 9)
  assert.equal(Model.displayAspectRatio(null), 16 / 9)
  assert.equal(Model.displayAspectRatio({ width: Infinity, height: 1 }), 16 / 9)
})

test('existing scale and display helpers still work', () => {
  assert.equal(Model.cleanScale('1.875', 3840, 2160), '1.875')
  assert.equal(Model.clampBrightness(101), 100)
  assert.equal(Model.parseDisplays('[{"enabled":true},{"enabled":false}]').enabledDisplayCount, 1)
  assert.deepEqual(Model.parseDisplays('invalid').displays, [])
})

test('scale slider includes a custom current scale exactly and keeps sorted unique stops', () => {
  const presets = ['1', '1.25', '1.6', '2', '3', '4']
  const stops = Model.scaleStops(presets, 1.875, 3840, 2160)
  assert.deepEqual(stops, ['1', '1.25', '1.6', '1.875', '2', '3', '4'])
  assert.equal(Model.matchingScaleIndex(stops, 1.875, 3840, 2160), 3)
  assert.equal(Model.scaleStops(presets, 2, 3840, 2160).filter(s => s === '2').length, 1)
  assert.deepEqual(presets, ['1', '1.25', '1.6', '2', '3', '4'])
})

test('screen contents use running dimensions, while off/modeless screens explicitly use saved geometry', () => {
  const m = { enabled: true, width: 1920, height: 1080, configuredWidth: 3840, configuredHeight: 2160 }
  assert.deepEqual(Model.displayDimensions(m), { width: 1920, height: 1080, live: true })
  assert.deepEqual(Model.displayDimensions({ ...m, width: 0, height: 0 }), { width: 3840, height: 2160, live: false })
  assert.equal(Model.displayDimensions({ ...m, enabled: false }).live, false)
})

test('physical gallery preserves relative size and fits narrow/multi-row layouts without overlap', () => {
  const monitors = [{ physicalWidth: 590, physicalHeight: 330 }, { physicalWidth: 890, physicalHeight: 390 },
    { physicalWidth: 600, physicalHeight: 340 }]
  for (const width of [736, 500, 260]) {
    const { boxes, height } = Model.galleryLayout(monitors, width, 18, 182, 185)
    assert.equal(boxes.length, 3)
    assert.ok(Math.abs(boxes[1].width / boxes[0].width - 890 / 590) < 0.00001)
    for (const box of boxes) {
      assert.ok(box.x >= 0 && box.x + box.width <= width + 0.001)
      assert.ok(box.y >= 0 && box.y + box.height < height)
    }
    for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i], b = boxes[j]
      assert.ok(a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y)
    }
  }
  assert.deepEqual(Model.physicalSize({ physicalWidth: 590, physicalHeight: 330, transform: 1 }), { width: 330, height: 590 })
  assert.deepEqual(Model.galleryLayout([], 500, 18, 182, 185), { boxes: [], height: 0 })
})

test('card selectors target the running resolution and retain exact fractional modes', () => {
  const m = { enabled: true, width: 1920, height: 1080, configuredWidth: 3840, configuredHeight: 2160,
    refreshRate: 59.94, scale: 1.875, availableModes: [
      { width: 3840, height: 2160, rate: 240, mode: '3840x2160@240.00' },
      { width: 1920, height: 1080, rate: 60, mode: '1920x1080@60.00' },
      { width: 1920, height: 1080, rate: 59.94, mode: '1920x1080@59.94' },
    ] }
  assert.deepEqual(Model.cardChoices(m, 'refresh').map(c => c.value), ['1920x1080@59.94', '1920x1080@60.00'])
  assert.equal(Model.resolutionChoices(m)[1].value, '1920x1080@59.94')
  assert.ok(Model.cardChoices(m, 'scale').some(c => c.label === '187.5%' && c.value === '1.875'))
})

test('arrangement uses logical, rotated desktop geometry and ignores off displays', () => {
  const boxes = Model.arrangementBoxes([
    { output: 'DP-1', usable: true, width: 3840, height: 2160, scale: 1.875, liveTransform: 1, x: -1152, y: 0 },
    { output: 'DP-2', usable: true, width: 3840, height: 1600, scale: 1.25, x: 0, y: 0 },
    { output: 'HDMI-A-1', usable: false, width: 0, height: 0 },
  ])
  assert.equal(boxes.length, 2)
  assert.equal(boxes[0].w, 1152)
  assert.equal(boxes[0].h, 2048)
  assert.equal(boxes[1].w, 3072)
  assert.equal(Model.arrangementError(boxes), '')
  const view = Model.arrangementView(boxes, 800, 240, 40)
  for (const box of boxes) {
    assert.ok(view.x + box.x * view.scale >= 39.99)
    assert.ok(view.y + box.y * view.scale >= 39.99)
    assert.ok(view.x + (box.x + box.w) * view.scale <= 760.01)
    assert.ok(view.y + (box.y + box.h) * view.scale <= 200.01)
  }
})

test('arrangement snaps to edges and validates a connected non-overlapping desktop', () => {
  const boxes = [{ output: 'A', x: 0, y: 0, w: 1920, h: 1080 }, { output: 'B', x: 1920, y: 0, w: 2560, h: 1440 }]
  const snapped = Model.snapDisplay(boxes, 1, 1930, 8, 40)
  assert.equal(snapped[1].x, 1920)
  assert.equal(Model.arrangementError(snapped), '')
  assert.match(Model.arrangementError(Model.snapDisplay(boxes, 1, 1700, 0, 20)), /overlap/)
  assert.match(Model.arrangementError(Model.snapDisplay(boxes, 1, 2600, 200, 20)), /edges/)
  assert.match(Model.arrangementError([{ ...boxes[0] }, { ...boxes[1], y: 1080 }]), /edges/)
  for (const direction of ['left', 'right', 'above', 'below']) {
    const placed = Model.placeDisplay(boxes, 1, 0, direction)
    assert.equal(Model.arrangementError(placed), '')
    assert.ok(Model.boxesTouch(placed[0], placed[1]))
  }
  assert.deepEqual(Model.packDisplays([{ ...boxes[0], x: 300 }, { ...boxes[1], x: -600 }]), boxes)
  assert.equal(boxes[1].x, 1920, 'preview helpers must not mutate their input')
})

test('normal confirmation conflicts and expired previews are statuses, genuine failures remain errors', () => {
  for (const result of [Model.actionFeedback(75, 'display change pending'),
    Model.actionFeedback(1, 'monitor-switcher: refresh change pending; confirm or revert its token before other commands')]) {
    assert.equal(result.error, '')
    assert.equal(result.kind, 'pending')
  }
  assert.equal(Model.actionFeedback(76, 'confirmation refused').kind, 'complete')
  assert.equal(Model.actionFeedback(77, 'no display change is pending').error, '')
  assert.equal(Model.actionFeedback(1, 'monitor-switcher: rollback failed').error, 'rollback failed')
  assert.equal(Model.actionFeedback(0, 'ok').notice, '')
})

test('selecting the running setting is a no-op, but nearby fractional modes still start a trial', () => {
  const display = { usable: true, width: 3840, height: 1600, refreshRate: 74.977, scale: 1.25 }
  assert.equal(Model.settingIsCurrent(display, 'refresh', '3840x1600@74.98'), true)
  assert.equal(Model.settingIsCurrent(display, 'mode', '3840x1600@59.99'), false)
  assert.equal(Model.settingIsCurrent(display, 'scale', '1.25'), true)
  assert.equal(Model.settingIsCurrent(display, 'scale', '1.5'), false)
  assert.equal(Model.settingIsCurrent({ ...display, usable: false }, 'scale', '1.25'), false)
})


test('solid action labels select the higher-contrast black or white text', () => {
  assert.equal(Model.contrastText({r: 0.49, g: 0.68, b: 0.64}), '#000000')
  assert.equal(Model.contrastText({r: 0.12, g: 0.37, b: 0.65}), '#ffffff')
  assert.equal(Model.contrastText({r: 0, g: 0, b: 0}), '#ffffff')
  assert.equal(Model.contrastText({r: 1, g: 1, b: 1}), '#000000')
})

test('setting failures retain context, distinguish timeouts and bound diagnostics', () => {
  assert.equal(Model.settingError('Text size', 0, 'done', false), '')
  assert.match(Model.settingError('Brightness for DP-2', 1, 'DDC unavailable', false), /Brightness for DP-2 failed.*DDC unavailable/)
  assert.match(Model.settingError('Text size', 124, '', false), /timed out/)
  assert.match(Model.settingError('Text size', 137, '', false), /timed out/)
  assert.match(Model.settingError('Text size', 0, '', true), /failed/)
  assert.ok(Model.settingError('Text size', 1, 'x'.repeat(10000), false).length < 300)
})

test('setting commands preserve failures, stderr and literal arguments through the output cap', () => {
  const {spawnSync} = require('node:child_process')
  function run(command) { return spawnSync(command[0], command.slice(1), {encoding: 'utf8'}) }
  const failure = run(Model.settingCommand('bash', ['-c', 'printf "unavailable" >&2; exit 7']))
  assert.equal(failure.status, 7)
  assert.equal(failure.stdout, 'unavailable')
  const literal = 'DP-1; $(printf injected)'
  const success = run(Model.settingCommand('printf', ['%s', literal]))
  assert.equal(success.status, 0)
  assert.equal(success.stdout, literal)
  const timeout = run(Model.settingCommand('sleep', ['5'], 0.05))
  assert.equal(timeout.status, 124)
})


test('gallery wraps before physical monitor illustrations crowd their controls', () => {
  const monitors = [{physicalWidth: 590, physicalHeight: 330},
    {physicalWidth: 890, physicalHeight: 390}, {physicalWidth: 600, physicalHeight: 340}]
  for (const width of [456, 736, 1036]) {
    const {boxes} = Model.galleryLayout(monitors, width, 22, 190, 230, 94, 160)
    for (const box of boxes) assert.ok(box.height >= 160)
  }
})

test('portrait cards keep true proportions inside a readable slot, without overlap', () => {
  const landscape = {physicalWidth: 600, physicalHeight: 340}
  const portrait = {physicalWidth: 600, physicalHeight: 340, transform: 1}
  const ultrawide = {physicalWidth: 890, physicalHeight: 390}
  for (const monitors of [[landscape, portrait, ultrawide], [portrait, portrait], [portrait]]) {
    for (const width of [456, 736, 1036]) {
      const {boxes, height} = Model.galleryLayout(monitors, width, 22, 190, 230, 94, 160)
      assert.equal(boxes.length, monitors.length)
      boxes.forEach((box, i) => {
        const s = Model.physicalSize(monitors[i])
        assert.ok(Math.abs(box.width / box.height - s.width / s.height) < 1e-6, 'true proportions')
        assert.ok(box.slotWidth >= Math.min(190, width) - 1e-6, 'readable control slot')
        assert.ok(box.x >= box.slotX - 1e-6 && box.x + box.width <= box.slotX + box.slotWidth + 1e-6, 'art inside slot')
        assert.ok(box.slotX >= -1e-6 && box.slotX + box.slotWidth <= width + 1e-6, 'slot inside gallery')
        assert.ok(box.y >= 0 && box.y + box.height < height)
        if (s.height > s.width) assert.ok(box.width >= 190 * Model.PORTRAIT_MINIMUM_FRACTION - 1e-6)
        else assert.ok(box.height >= 160 - 1e-6 || boxes.length === 1)
      })
      for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
        const a = boxes[i], b = boxes[j]
        const apart = a.slotX + a.slotWidth <= b.slotX + 1e-6 || b.slotX + b.slotWidth <= a.slotX + 1e-6
          || a.y + a.height <= b.y || b.y + b.height <= a.y
        assert.ok(apart, `cards overlap at ${width}`)
      }
    }
  }
  // Landscape-only galleries keep their previous geometry: slot == art.
  const {boxes} = Model.galleryLayout([landscape, ultrawide], 1036, 22, 190, 230, 94, 160)
  for (const box of boxes) { assert.equal(box.slotX, box.x); assert.equal(box.slotWidth, box.width) }
})

test('rotation choices, labels and current-value matching', () => {
  const choices = Model.rotationChoices()
  assert.deepEqual(choices.map(c => c.value), ['0', '90', '180', '270'])
  assert.deepEqual(Model.cardChoices({}, 'rotation'), choices)
  assert.equal(new Set(choices.map(c => c.label)).size, 4)
  assert.match(Model.rotationLabel(0), /Landscape/)
  assert.match(Model.rotationLabel(90), /Portrait/)
  assert.match(Model.rotationLabel(180), /upside down/)
  assert.match(Model.rotationLabel(270), /Portrait/)
  assert.notEqual(Model.rotationLabel(90), Model.rotationLabel(270))
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6, 7].map(Model.rotationDegrees), [0, 90, 180, 270, 0, 90, 180, 270])
  assert.equal(Model.rotationDegrees(undefined), 0)
  const angles = [0, 90, 180, 270].map(Model.rotationGlyphAngle)
  assert.deepEqual(angles.map(Math.abs), [0, 90, 180, 90])
  assert.equal(angles[1], -angles[3], 'the two portrait glyphs turn opposite ways')
  assert.equal(Model.rotationGlyphAngle(-90), Model.rotationGlyphAngle(270))
  const display = {usable: true, liveTransform: 1}
  assert.equal(Model.settingIsCurrent(display, 'rotation', '90'), true)
  assert.equal(Model.settingIsCurrent(display, 'rotation', '0'), false)
  assert.equal(Model.settingIsCurrent({usable: true, liveTransform: 5}, 'rotation', '90'), true)
  assert.equal(Model.settingIsCurrent({usable: false, liveTransform: 1}, 'rotation', '90'), false)
})
