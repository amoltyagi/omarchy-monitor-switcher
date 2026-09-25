# Upstream fork tracking

`Panel.qml` and `Model.js` originally derive from Omarchy's built-in display
widget. The interactive gallery, arrangement editor and persistent backend are
local features.

## Provenance

| | |
|---|---|
| Original source | `/usr/share/omarchy/shell/plugins/panels/monitor/{Panel.qml,Model.js}` |
| Upstream repository | https://github.com/basecamp/omarchy |
| Originally forked from | Omarchy 4.0.0 |
| Current integration verified on | Omarchy 4.0.3, Hyprland 0.56.2 (Lua), Qt 6.11.2 |
| License | MIT; see `LICENSE.upstream` |

## Local components

| File | Responsibility |
|---|---|
| `Panel.qml` | Popup, one backend snapshot, action processes, brightness/text size, keyboard help |
| `PanelRegistry.js` | Elect one IPC owner across per-screen instances; route to focused screen |
| `DisplayGallery.qml` | Adaptive physical monitor gallery, chin rotation menu, toggle-anchored Night Light and trial confirmation |
| `SettingChip.qml` | Rounded, visibly editable setting/button with hover and keyboard feedback |
| `MonitorPowerToggle.qml` | Below-monitor power switch and pending feedback |
| `OrientationGlyph.qml` | Tiny monitor glyph showing a rotation, used on the chin button and its menu |
| `ArrangementEditor.qml` | Draft desktop layout, dragging, snap preview and relative placement |
| `Model.js` | Pure scale/mode, physical geometry and arrangement helpers |
| `DragSlider.qml` | Wheel-safe brightness/text-size sliders |
| `MonitorLogo.qml` | Theme-tinted vector identity |
| `bin/monitor-switcher` | Persistent config/state, collision-free returning monitors, rotation reflow, verified actions and rollback |
| `bin/monitor-nightlight.py` | Per-output gamma controls, saved temperature preferences and hotplug replay |
| `bin/monitor-action` | Detached display changes that survive their originating panel |

## Integration details

- The panel subclasses `qs.Ui.Panel` and uses `KeyboardPanel`, `BarIconButton`,
  `CursorSurface` and other shell UI primitives. Do not edit packaged files.
- `manageIpc: false` is paired with elected ownership in `PanelRegistry.js`.
  Every screen has a widget instance, even when the manifest disallows duplicate
  layout entries. Registration must survive hotplug and shell reload.
- The registry also serializes panel actions and shares snapshots. Reads carry
  generation/sequence tickets so stale results cannot erase a new confirmation.
  Controls remain blocked between process exit and a fresh state read.
- Omarchy 4.x nests popup content inside a holder directly below `BorderSurface`.
  A guarded local binding applies rounded corners to this panel's card only.
  Check this containment when updating `KeyboardPanel` integration.
- Layout/power commands use the plugin backend, not Omarchy's runtime-only
  monitor tools. Focus uses `hl.dispatch(hl.dsp.focus({monitor = ...}))` on Lua
  Hyprland; legacy `hyprctl dispatch focusmonitor ...` is not compatible.
- Monitor cards, active count and focused output come from one snapshot.
  Brightness reads are separately targeted and ignore obsolete focus results.
- Output collectors are bounded and command values travel in argv rather than
  being interpolated into shell code.
- Panel resolution, refresh, scale and arrangement edits use the independent
  Keep/Revert watchdog. Ordinary CLI layout commands verify application too.

- `bin/monitor-nightlight.py` owns only selected outputs' gamma controls. It runs
  once through the registry IPC owner, releases gamma on exit and replays saved
  preferences after hotplug. Keep global hyprsunset controls separate.
- `bin/monitor-action` runs layout actions in an independent session so removing
  the initiating panel cannot interrupt persistence or rollback.
- Verified layouts are bounded to eight connected monitor sets; recovery uses
  the existing confirmation protocol and verifies rollback on live survivors.

## Updating after Omarchy changes

Compare upstream APIs with the integration above; the panel has been restructured
and should not be overwritten with a stock copy. Preserve MIT attribution.

1. Run backend/model and offscreen QML tests documented in `README.md`.
2. Run `omarchy plugin validate` on the real repository path.
3. Check popup layout, corners, click-to-edit, focus and keyboard navigation.
4. Check power switching, last-usable-display protection, and live mode/scale
   verification with the relevant Hyprland version.
5. Check dragging and atomic arrangement Apply/Keep/Revert, including shell
   closure during a trial.
6. Check IPC before and after monitor hotplug, then refresh the screenshots.
