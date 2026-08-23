# Changelog

## 2.5.2 — 2026-08-24

- **Security hardening** (marketplace review on submission #1918): all
  backend file I/O now funnels through two guarded helpers. Reads refuse
  symlinks and non-regular files (a planted fifo would otherwise block a
  read forever), cap at 1 MB, and require valid JSON; writes refuse
  symlinked parents/targets and go through mktemp + atomic rename, so a
  link planted at a target path is *replaced*, never followed — and a crash
  mid-write never leaves a truncated file. Unreadable state degrades to the
  safe default with a warning; an unreadable config fails loudly with
  recovery guidance.
- Panel: every `Process` feeding a `StdioCollector` is output-capped at the
  command level (`| head -c N`, argv-safe) — the installed StdioCollector
  has no size limit, so the bound lives in the spawned command. Fork patch
  list grows to ten (UPSTREAM.md).

## 2.5.1 — 2026-08-23

- Popup footer simplified to a single line — "Keyboard shortcut:
  SUPER+SHIFT+CTRL+1…N" (shown with 2+ displays). The navigation-key
  rundown was crowded; the README already covers the keys.

## 2.5.0 — 2026-08-23

- **Numbered displays.** Every managed monitor now has a stable number — its
  place in the config/pack order (left-to-right). The CLI accepts it
  everywhere an output or alias works (`monitor-switcher toggle 2`), `state`
  prints it, and panel rows are prefixed with it (`2 · LG · focused`), so
  the keybind target is visible in-product. Numbers need no aliases and
  survive output renumbering, which makes generic keybinds possible:
  `SUPER+SHIFT+CTRL+1…N → monitor-switcher toggle 1…N` works on any
  multi-monitor setup with zero configuration.
- **Keybind discoverability**: the popup footer gains a second hint line
  suggesting exactly that convention ("keybind to adopt:
  SUPER+SHIFT+CTRL+1…N → toggle display N", shown when 2+ displays are
  managed), and the README now documents that described `o.bind` entries
  appear in Omarchy's `SUPER+K` keybindings sheet like first-party
  shortcuts.
- New preview.png: numbered rows, both footer hints, and a toggled-off
  monitor row (slashed glyph, no check).

## 2.4.0 — 2026-08-23

- **Keyboard hints footer in the popup** — a caption line under DISPLAYS
  (`↑↓ navigate · ←→ adjust · ⏎ toggle display · esc close`) so the
  keyboard-first flow is discoverable in-product, not just in the README.
  Fork patch list grows to nine; see UPSTREAM.md.
- New `preview.png`: real three-monitor battlestation data (aliases,
  physical sizes, resolution@scale) instead of generic content.
- README: leads with desktop multi-monitor switching and keyboard-driven
  on/off; documents the hints footer.

## 2.3.0 — 2026-08-23

- **Overlap-proof layouts.** `apply()` computes every monitor's box and
  validates the set before writing anything: a colliding layout is refused
  with a clear message and the last known-good generated file is kept, so
  Hyprland's "Monitor X overlaps with other monitor(s)" notification can no
  longer originate from this plugin. Refusals roll back config, state, and
  layout together (`move`/`swap`/`pack`/`toggle` all revert cleanly).
- **Geometry now comes from the config, never the live mode.** Packing
  previously measured each monitor's *currently running* mode while the
  generated rule applied the *configured* one — a monitor answering hyprctl
  with a transient fallback mode mid-toggle (hotplug re-enumeration, the
  watcher's modeless-recovery churn) shifted everything right of it and
  could produce an overlapping layout. Mode dimensions for `preferred`
  monitors are snapshotted into `mode_w`/`mode_h` at seed/adopt time;
  existing configs backfill automatically on the next run. (Regression-
  tested: live mode forced to 2560x1440 while `preferred` is 3840x2160 —
  computed layout unchanged.)
- **Transform-aware packing**: portrait monitors (transform 1/3/5/7) now
  advance the pack cursor by their rotated width instead of their panel
  width.
- **Settle-checked live reads**: a `hyprctl` answer is only trusted once it
  is complete (no enabled monitor at 0x0) and identical across two reads —
  partial/mid-transition data can no longer drop a monitor from the
  generated layout into the wildcard `auto` rule.
- **Manual arrangement (CLI)**: `move <id> XxY` and
  `move <id> left-of|right-of|above|below <id2>` (relative moves compute the
  pin for you, negative coordinates fine), `swap <a> <b>` (exchange places
  in the packing order), `pack` (clear all pins, re-pack), and
  `plan [--json]` (preview computed boxes, with an overlap warning, without
  touching anything). Config schema gains an optional per-monitor
  `"position": "XxY"` pin — vertical stacks, intentional gaps, any
  arrangement Hyprland allows.
- `state --json` gains per-monitor `x`/`y`/`position` and a top-level
  `overlaps` array computed from the live layout; plain `state` prints
  overlap warnings and per-monitor positions.

## 2.2.0 — 2026-08-23

- DISPLAYS rows now show each monitor's **physical size** (e.g.
  `27" · 3840×2160 @1.875x`), derived from EDID-reported dimensions via
  `hyprctl monitors all` (`physicalWidth`/`physicalHeight`) — nothing is
  hardcoded; 0 mm falls back to no size label.
- Per-row icons by display class, classified in the backend: laptop
  (internal eDP/LVDS/DSI), ultrawide (pixel aspect ≥ 2.3), tv (≥ 38"),
  otherwise a desktop monitor. Toggled-off rows always show the slashed
  monitor-off glyph.
- Hotplug reactivity: the panel refreshes state whenever the enabled-screen
  count changes (`Quickshell.screens`), so plugging/unplugging a monitor —
  or toggling one from a keybind while the panel is open — updates rows and
  the bar glyph immediately instead of waiting for the 5s poll.
- The popup now **reopens itself after a row toggle**: the backend's
  `hyprctl reload` remaps bars on screen-count changes, which destroyed the
  popup mid-flow. Toggling several monitors in one visit works again.
- Docs: added a "Why this exists" section — source-verified positioning
  against the built-in tooling (laptop-grade persistence for every output),
  with a who-it's-for list reusable for launch posts.
- Docs: corrected the watcher claim (verified against source) —
  `omarchy-hyprland-monitor-watch` only reloads for genuinely *modeless*
  monitors (enabled but 0x0; disabled outputs are excluded from its check),
  and each such reload reverts runtime `hyprctl keyword` toggles as
  collateral. The persistence claim itself is unchanged. Also confirmed: no
  default keybind/CLI/menu path toggles an external monitor (laptop-internal
  toggles exist and use the same toggles-dir mechanism as this plugin).
- Backend hardening after a real corruption event: `hyprctl` can answer
  empty while the compositor is mid-reload, and one such transient emptied
  `config.json` (every writer truncated-then-failed). `live()` now retries,
  config seeding requires a non-empty file (`-s`), derivations validate
  non-empty before writing, and the generated Lua is built fully before
  being written — no truncate-then-fail paths remain. Stress-tested: 10
  concurrent `state` calls during live toggles, zero failures.

## 2.1.0 — 2026-08-23

- DISPLAYS rows show each monitor's **alias** and a `resolution @scale`
  caption (from `bin/monitor-switcher state --json`, merged display-only over
  the upstream model) instead of bare output names.
- The BRIGHTNESS header now names the focused display it controls
  (`BRIGHTNESS · ACER`), mirroring the SCALE header. Upstream's single
  brightness slider only ever targets the focused monitor — and a monitor
  toggled off can't be focused, which read as "brightness missing" for
  switched-off displays. All three monitors here answer DDC fine; it was a
  labeling problem, not a hardware one.

## 2.0.0 — 2026-08-23

The plugin is now a **drop-in replacement** for Omarchy's built-in Display
widget instead of a separate minimal popup.

- Vendored Omarchy 4.0.0's Display panel (`Panel.qml`, `Model.js`; MIT) as a
  minimal-delta fork — every change fenced with `monitor-switcher fork`
  markers, tracked in `UPSTREAM.md`.
- The forked panel keeps all built-in features: brightness slider (+ scroll
  on the bar icon, with OSD), text size slider, scale presets, laptop
  internal/mirror handling, and keyboard navigation.
- `toggleDisplay()` now routes through `bin/monitor-switcher`, so the
  DISPLAYS rows are persistent and layout-aware instead of runtime-only.
- Own IPC target (`case.monitor-switcher`) so both widgets can coexist
  without handler collisions.
- Bar glyph tracks managed monitors (including toggled-off ones), so
  switching a monitor off no longer collapses it to the single-display icon.
- Panel hero reads "Monitor Switcher" for attribution in screenshots.
- `BarWidget.qml` removed — the manifest now points straight at `Panel.qml`,
  like every first-party panel.
- README: removal of the built-in widget is documented as
  `omarchy plugin disable omarchy.monitor` (official, reversible) instead of
  hand-editing `shell.json`; keyboard docs describe arrow keys only (the
  shell's shared key handler also answers to hjkl — that comes from Omarchy's
  `PanelKeyCatcher`, not this plugin).
- `preview.png` retaken with the forked panel.

## 1.0.0 — 2026-08-23

Initial release.

- Bar widget with a minimal checkbox popup: alias, output, resolution@scale
  per monitor; focused/disconnected states; last-enabled row locked.
- Keyboard navigation in the popup: `j`/`k` move, `Enter`/`Space` toggle,
  `Esc` close.
- `bin/monitor-switcher` CLI: `state [--json]`, `toggle|enable|disable`
  (by output name or alias), `apply`.
- Persistent toggles via a generated Lua file in Omarchy's Hyprland toggle
  directory — survives reloads, reboots, and `omarchy-hyprland-monitor-watch`.
- Layout memory: enabled monitors pack left-to-right in config order, each
  with its own `scale`, `mode`, and `transform`.
- Auto-adoption: config is seeded from the live setup on first run; newly
  connected monitors are appended automatically.
- Guards: refuses to disable the last active display; disconnected monitors
  keep their settings.
