function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return String(Math.round(scaleUnits / 120 * 1000000) / 1000000)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (normalizeScale(cleanScale(scales[i], width, height)) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || !(Number(width) > 0 && Number(height) > 0)
      || !isFinite(Number(width)) || !isFinite(Number(height))) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

// monitor-switcher fork: keep a custom current scale as an exact slider stop.
function scaleStops(presets, current, width, height) {
  var values = presets.slice()
  if (isFinite(Number(current)) && Number(current) >= 0.25 && Number(current) <= 5)
    values.push(String(current))
  values.sort(function(a, b) { return Number(a) - Number(b) })
  return availableScales(values, width, height)
}

function brightnessName(percent) {
  var p = Math.round(percent)
  if (p >= 95) return "Sun blast"
  if (p >= 80) return "Solar flare"
  if (p >= 65) return "Golden hour"
  if (p >= 45) return "Even day"
  if (p >= 30) return "Soft glow"
  if (p >= 20) return "Lamp light"
  if (p >= 10) return "Candlelit"
  return "Night owl"
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

// monitor-switcher fork: live refresh matching and display illustration geometry.
function formatRefreshRate(value) {
  if (value === null || value === undefined || Number(value) <= 0 || !isFinite(Number(value))) return "--"
  return String(Math.round(Number(value) * 100) / 100)
}

function matchingRefreshIndex(modes, rate) {
  if (!Array.isArray(modes) || Number(rate) <= 0 || !isFinite(Number(rate))) return -1
  for (var i = 0; i < modes.length; i++) {
    if (Math.round(Number(modes[i].rate) * 100) === Math.round(Number(rate) * 100)) return i
  }
  return -1
}

function displayAspectRatio(display) {
  var w = Number(display && (display.configuredWidth || display.width))
  var h = Number(display && (display.configuredHeight || display.height))
  if (!(w > 0 && h > 0 && isFinite(w) && isFinite(h))) return 16 / 9
  return Number(display.transform || 0) % 2 === 1 ? h / w : w / h
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    scaleStops: scaleStops,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays,
    formatRefreshRate: formatRefreshRate,
    matchingRefreshIndex: matchingRefreshIndex,
    displayAspectRatio: displayAspectRatio
  }
}
