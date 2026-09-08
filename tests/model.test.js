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
