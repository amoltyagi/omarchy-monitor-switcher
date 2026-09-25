// Pick legible text for a solid theme accent, including light themes.
function contrastText(color) {
  function channel(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
  }
  var luminance = 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
  return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? "#000000" : "#ffffff"
}

// Preserve failure codes through the output cap; arguments never become shell code.
function settingCommand(program, args, timeoutSeconds) {
  return ["bash", "-o", "pipefail", "-c",
    'timeout -k 1 "$1" "${@:2}" 2>&1 | head -c 65536',
    "monitor-switcher", String(timeoutSeconds === undefined ? 12 : timeoutSeconds), program].concat(args)
}

function settingError(label, exitCode, output, crashed) {
  if (exitCode === 0 && !crashed) return ""
  if (exitCode === 124 || exitCode === 137) return label + " timed out. Please try again."
  var detail = String(output || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").trim()
  if (detail.length > 240) detail = detail.slice(0, 237) + "…"
  return label + " failed." + (detail ? " " + detail : " Please try again.")
}

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

function displayDimensions(display) {
  var d = display || {}
  var live = Number(d.width) > 0 && Number(d.height) > 0 && d.enabled !== false
  return { width: Number(live ? d.width : d.configuredWidth) || 0,
    height: Number(live ? d.height : d.configuredHeight) || 0, live: live }
}

function physicalSize(display) {
  var w = Number(display.physicalWidth), h = Number(display.physicalHeight)
  if (!(w > 0 && h > 0 && isFinite(w) && isFinite(h))) {
    // Unknown EDID: a nominal illustration, never an invented size label.
    var aspect = displayAspectRatio(display)
    return { width: 600, height: 600 / aspect }
  }
  return Number(display.transform || 0) % 2 ? { width: h, height: w } : { width: w, height: h }
}

// A portrait illustration may be narrower than the controls beneath it, down
// to this fraction of the minimum card width; its screen uses a compact layout.
var PORTRAIT_MINIMUM_FRACTION = 0.62

// One shared physical-to-UI factor per gallery. Reduce columns rather than
// shrinking embedded controls into unreadable labels on narrow panels.
// Each card occupies a slot at least minimumWidth wide, so a portrait screen
// keeps its true proportions while the controls below it stay readable.
// Boxes: {x, y, width, height} is the illustration; {slotX, slotWidth} the card.
function galleryLayout(monitors, width, gap, minimumWidth, maximumHeight, footerHeight, minimumHeight) {
  if (!monitors.length || width <= 0) return { boxes: [], height: 0 }
  var sizes = monitors.map(physicalSize)
  var slotMinimum = Math.min(minimumWidth, width)
  function slot(s, f) { return Math.max(s.width * f, slotMinimum) }
  function rowWidth(group, f) {
    return group.reduce(function(n, s) { return n + slot(s, f) }, 0) + gap * (group.length - 1)
  }
  // Largest factor for which a row fits: exact, since each slot is either
  // proportional or pinned at the minimum. Pin slots until the set is stable.
  function rowFactor(group) {
    var pinned = group.map(function() { return false })
    for (;;) {
      var free = 0, fixed = gap * (group.length - 1)
      group.forEach(function(s, i) { if (pinned[i]) fixed += slotMinimum; else free += s.width })
      if (free <= 0) return Infinity
      var f = Math.max(0, (width - fixed) / free), changed = false
      group.forEach(function(s, i) { if (!pinned[i] && s.width * f < slotMinimum) { pinned[i] = true; changed = true } })
      if (!changed) return f
    }
  }
  var tallest = Math.max.apply(null, sizes.map(function(s) { return s.height }))
  // A portrait beside landscapes makes the shared factor height-bound; allow
  // extra height (bounded) so landscape screens keep room for their controls.
  var landscapeHeights = sizes.filter(function(s) { return s.width >= s.height }).map(function(s) { return s.height })
  var heightCap = maximumHeight
  if (minimumHeight && landscapeHeights.length && landscapeHeights.length < sizes.length)
    heightCap = Math.min(maximumHeight * 1.5, Math.max(maximumHeight, minimumHeight * tallest / Math.min.apply(null, landscapeHeights)))
  var heightFactor = heightCap / tallest
  var columns = Math.min(3, monitors.length), factor = 1
  while (columns >= 1) {
    factor = heightFactor
    for (var start = 0; start < sizes.length; start += columns)
      factor = Math.min(factor, rowFactor(sizes.slice(start, start + columns)))
    var fits = true
    for (var r = 0; r < sizes.length; r += columns)
      if (rowWidth(sizes.slice(r, r + columns), 0) > width + 0.001) fits = false
    var roomy = fits && sizes.every(function(s) {
      var minimum = s.height > s.width ? minimumWidth * PORTRAIT_MINIMUM_FRACTION : minimumWidth
      return s.width * factor >= minimum && s.height * factor >= (minimumHeight || 0)
    })
    // Fewer columns only help when width limits the factor.
    if (columns === 1 || roomy || (fits && factor >= heightFactor)) break
    columns--
  }
  var footer = footerHeight === undefined ? gap * 2 : footerHeight
  var rowHeight = tallest * factor + footer
  var boxes = []
  for (var row = 0; row * columns < sizes.length; row++) {
    var first = row * columns, count = Math.min(columns, sizes.length - first)
    var x = (width - rowWidth(sizes.slice(first, first + count), factor)) / 2
    for (var i = first; i < first + count; i++) {
      var w = Math.min(width, sizes[i].width * factor), h = sizes[i].height * factor, sw = slot(sizes[i], factor)
      boxes.push({ x: x + (sw - w) / 2, y: Math.max(0, row * rowHeight + rowHeight - footer - h), width: w, height: h,
        slotX: x, slotWidth: sw })
      x += sw + gap
    }
  }
  return { boxes: boxes, height: Math.ceil(sizes.length / columns) * rowHeight }
}

// Rotation. Hyprland/wl_output transforms 0–3 turn the desktop in 90° steps;
// 4–7 add mirroring and are kept (never offered) by the panel.
// ROTATION_90_TURNS names the physical direction a monitor is turned for
// transform 1, as verified on real hardware.
var ROTATION_90_TURNS = "right"

function rotationDegrees(transform) {
  return (Number(transform || 0) & 3) * 90
}

function rotationLabel(degrees) {
  var d = Number(degrees) % 360
  var other = ROTATION_90_TURNS === "left" ? "right" : "left"
  if (d === 90) return "Portrait · turned " + ROTATION_90_TURNS
  if (d === 180) return "Landscape · upside down"
  if (d === 270) return "Portrait · turned " + other
  return "Landscape · standard"
}

function rotationChoices() {
  return [0, 90, 180, 270].map(function(d) {
    return { label: rotationLabel(d), detail: d + "°", value: String(d), degrees: d }
  })
}

// On-screen angle (Qt: positive is clockwise) for a monitor glyph turned the
// way the physical monitor is turned for this rotation, in (-180, 180].
function rotationGlyphAngle(degrees) {
  var d = ((Number(degrees) || 0) % 360 + 360) % 360
  var sign = ROTATION_90_TURNS === "left" ? -1 : 1
  if (d === 180) return 180
  if (d === 90) return sign * 90
  if (d === 270) return -sign * 90
  return 0
}

function resolutionChoices(display) {
  var groups = {}, currentRate = Number(display.refreshRate) || Number(String(display.mode || '').split('@')[1]) || 60
  ;(display.availableModes || []).forEach(function(m) {
    var key = m.width + 'x' + m.height
    if (!groups[key] || Math.abs(m.rate - currentRate) < Math.abs(groups[key].rate - currentRate)) groups[key] = m
  })
  return Object.keys(groups).map(function(key) { return groups[key] })
    .sort(function(a, b) { return b.width * b.height - a.width * a.height || b.width - a.width })
    .map(function(m) { return { label: m.width + ' × ' + m.height, value: m.mode } })
}

function cardChoices(display, field) {
  var size = displayDimensions(display)
  if (field === 'nightlight') return [
    {label: "Off · daylight", value: "off"},
    {label: "Mild · 5000 K", value: "5000"},
    {label: "Warm · 4000 K", value: "4000"},
    {label: "Warmer · 3500 K", value: "3500"},
    {label: "Amber · 2500 K", value: "2500"}
  ]
  if (field === 'rotation') return rotationChoices()
  if (field === 'mode') return resolutionChoices(display)
  if (field === 'refresh') return (display.availableModes || [])
    .filter(function(m) { return m.width === size.width && m.height === size.height })
    .sort(function(a, b) { return a.rate - b.rate })
    .map(function(m) { return { label: formatRefreshRate(m.rate) + ' Hz', value: m.mode } })
  if (field === 'scale') return scaleStops(['1', '1.25', '1.5', '1.6', '2', '3', '4'],
    display.scale || display.configuredScale, size.width, size.height)
    .map(function(s) {
      var clean = cleanScale(s, size.width, size.height)
      return { label: Math.round(Number(clean) * 1000) / 10 + '%', value: clean }
    })
  return []
}

function settingIsCurrent(display, field, value) {
  if (!display || !display.usable) return false
  if (field === 'nightlight') {
    var state = display.nightLight || {}
    return value === 'off' ? !state.enabled : state.active && Number(value) === state.temperature
  }
  if (field === 'scale') return Math.abs(Number(value) - Number(display.scale)) < 0.0001
  if (field === 'rotation') return Number(value) === rotationDegrees(display.liveTransform)
  var mode = /^(\d+)x(\d+)@([\d.]+)$/.exec(String(value))
  return !!mode && Number(mode[1]) === Number(display.width) && Number(mode[2]) === Number(display.height)
    && Math.round(Number(mode[3]) * 100) === Math.round(Number(display.refreshRate) * 100)
}

function actionFeedback(exitCode, output) {
  var text = String(output || '').trim()
  if (exitCode === 0) return {error: '', notice: '', kind: ''}
  if (exitCode === 75 || /^(?:monitor-switcher: )?(?:refresh|display) change pending;/.test(text))
    return {error: '', notice: 'Confirm or revert the current display change first.', kind: 'pending'}
  if (exitCode === 76)
    return {error: '', notice: 'The preview has ended. Your previous settings were restored.', kind: 'complete'}
  if (exitCode === 77)
    return {error: '', notice: '', kind: ''}
  return {error: text.replace(/^monitor-switcher:\s*/gm, '') || 'The display change could not be applied.', notice: '', kind: ''}
}

function arrangementBoxes(monitors) {
  return monitors.filter(function(m) { return m.usable }).map(function(m) {
    var rotated = Number(m.liveTransform || 0) % 2
    return { output: m.output, name: m.alias || m.output, num: m.num,
      x: Number(m.x) || 0, y: Number(m.y) || 0,
      w: Math.round(Number(rotated ? m.height : m.width) / Number(m.scale || 1)),
      h: Math.round(Number(rotated ? m.width : m.height) / Number(m.scale || 1)) }
  })
}

function arrangementView(boxes, width, height, padding) {
  if (!boxes.length) return { scale: 1, x: width / 2, y: height / 2 }
  var left = Math.min.apply(null, boxes.map(function(b) { return b.x }))
  var top = Math.min.apply(null, boxes.map(function(b) { return b.y }))
  var right = Math.max.apply(null, boxes.map(function(b) { return b.x + b.w }))
  var bottom = Math.max.apply(null, boxes.map(function(b) { return b.y + b.h }))
  var scale = Math.max(0.001, Math.min((width - padding * 2) / (right - left), (height - padding * 2) / (bottom - top)))
  return { scale: scale, x: (width - (right - left) * scale) / 2 - left * scale,
    y: (height - (bottom - top) * scale) / 2 - top * scale }
}

function boxesTouch(a, b) {
  return ((a.x + a.w === b.x || b.x + b.w === a.x) && Math.min(a.y + a.h, b.y + b.h) > Math.max(a.y, b.y))
    || ((a.y + a.h === b.y || b.y + b.h === a.y) && Math.min(a.x + a.w, b.x + b.w) > Math.max(a.x, b.x))
}

function arrangementError(boxes) {
  if (boxes.length < 2) return 'Turn on another display to arrange your desktop.'
  for (var i = 0; i < boxes.length; i++) for (var j = i + 1; j < boxes.length; j++) {
    var a = boxes[i], b = boxes[j]
    if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h)
      return 'Move the displays apart; their screens overlap.'
  }
  var seen = [0]
  for (var round = 0; round < boxes.length; round++) {
    boxes.forEach(function(box, index) {
      if (seen.indexOf(index) < 0 && seen.some(function(s) { return boxesTouch(box, boxes[s]) })) seen.push(index)
    })
  }
  return seen.length === boxes.length ? '' : 'Bring the edges together so your pointer can cross between displays.'
}

function placeDisplay(boxes, index, reference, direction) {
  var result = boxes.map(function(b) { return Object.assign({}, b) })
  var a = result[index], b = result[reference]
  if (!a || !b || index === reference) return result
  a.x = direction === 'left' ? b.x - a.w : direction === 'right' ? b.x + b.w : b.x
  a.y = direction === 'above' ? b.y - a.h : direction === 'below' ? b.y + b.h : b.y
  return result
}

function snapDisplay(boxes, index, x, y, threshold) {
  var result = boxes.map(function(b) { return Object.assign({}, b) })
  var a = result[index]
  if (!a) return result
  a.x = Math.round(x); a.y = Math.round(y)
  var best = null, distance = threshold * threshold
  function candidate(cx, cy) {
    var d = Math.pow(cx - a.x, 2) + Math.pow(cy - a.y, 2)
    if (d <= distance) { distance = d; best = { x: Math.round(cx), y: Math.round(cy) } }
  }
  result.forEach(function(b, i) {
    if (i === index) return
    var ys = [b.y, b.y + b.h - a.h, Math.round(b.y + (b.h - a.h) / 2)]
    var xs = [b.x, b.x + b.w - a.w, Math.round(b.x + (b.w - a.w) / 2)]
    if (a.y < b.y + b.h && a.y + a.h > b.y) ys.push(a.y)
    if (a.x < b.x + b.w && a.x + a.w > b.x) xs.push(a.x)
    ys.forEach(function(cy) { candidate(b.x - a.w, cy); candidate(b.x + b.w, cy) })
    xs.forEach(function(cx) { candidate(cx, b.y - a.h); candidate(cx, b.y + b.h) })
  })
  if (best) { a.x = best.x; a.y = best.y }
  return result
}

function packDisplays(boxes) {
  var x = 0
  return boxes.map(function(b) {
    var next = Object.assign({}, b, { x: x, y: 0 })
    x += b.w
    return next
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    contrastText: contrastText,
    settingCommand: settingCommand,
    settingError: settingError,
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
    displayAspectRatio: displayAspectRatio,
    displayDimensions: displayDimensions,
    physicalSize: physicalSize,
    galleryLayout: galleryLayout,
    PORTRAIT_MINIMUM_FRACTION: PORTRAIT_MINIMUM_FRACTION,
    ROTATION_90_TURNS: ROTATION_90_TURNS,
    rotationDegrees: rotationDegrees,
    rotationLabel: rotationLabel,
    rotationChoices: rotationChoices,
    rotationGlyphAngle: rotationGlyphAngle,
    resolutionChoices: resolutionChoices,
    cardChoices: cardChoices,
    settingIsCurrent: settingIsCurrent,
    actionFeedback: actionFeedback,
    arrangementBoxes: arrangementBoxes,
    arrangementView: arrangementView,
    boxesTouch: boxesTouch,
    arrangementError: arrangementError,
    placeDisplay: placeDisplay,
    snapDisplay: snapDisplay,
    packDisplays: packDisplays
  }
}
