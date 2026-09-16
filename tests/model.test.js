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
