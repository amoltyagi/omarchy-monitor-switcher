# Upstream fork tracking

`Panel.qml` and `Model.js` are vendored copies of Omarchy's built-in Display
widget (`omarchy.monitor`) with a small, fenced patch set applied.

## Provenance

| | |
|---|---|
| Source | `/usr/share/omarchy/shell/plugins/panels/monitor/{Panel.qml,Model.js}` |
| Upstream repo | https://github.com/basecamp/omarchy |
| Forked from | Omarchy **4.0.0** (`pacman -Q omarchy` → `4.0.0-1`) |
| License | MIT, (c) David Heinemeier Hansson — see `LICENSE.upstream` |

## The patch set (Panel.qml only — Model.js is byte-identical)

Every change is marked with a `monitor-switcher fork` comment. Audit the
delta any time with:

```bash
grep -n "monitor-switcher fork" Panel.qml
```

1. **Identity** — `moduleName` / `ipcTarget` / `IpcHandler.target` changed
   from `omarchy.monitor` to `case.monitor-switcher`, so this widget and the
   built-in one can coexist without fighting over the shell's single-handler
   IPC targets.
2. **Persistent toggles** — `toggleDisplay()` calls
   `bin/monitor-switcher toggle <output>` instead of
   `hyprctl keyword monitor X,disable`. Adds the `scriptPath` property.
   No extra refresh patch is needed: `actionProc.onRunningChanged` already
   calls `refresh()`, and the backend's `hyprctl reload` has settled by the
   time the process exits.
3. **Bar glyph** — tracks `root.displays.length` (all *managed* monitors,
   including toggled-off ones) instead of `Quickshell.screens.length`
   (enabled screens only), so switching a monitor off doesn't collapse the
   icon to the single-display variant. Also adds `tooltipText: "Monitor
   Switcher"`.
4. **Panel title** — hero reads "Monitor Switcher" instead of "Display", so
   screenshots in issue reports are attributable to the right project.
5. **Named rows** — a second `Process` polls `bin/monitor-switcher state
   --json` into a `switcherMeta` map (fired from `refresh()`); DISPLAYS rows
   render the alias and a `WxH @scalex` caption instead of the bare output
   name. Display-only; all state logic still runs on `root.displays`.
6. **Brightness target label** — the BRIGHTNESS section header names the
   focused display it controls (`BRIGHTNESS · ACER`), mirroring upstream's
   SCALE header pattern. Upstream's slider only ever targets the focused
   monitor, and a disabled monitor can't be focused — this label makes that
   visible instead of looking like a missing feature.
7. **Physical size + class icons + hotplug** — the backend's `state --json`
   derives per-monitor `inches` (EDID mm via `hyprctl monitors all`) and
   `kind` (laptop / ultrawide ≥ 2.3 aspect / tv ≥ 38" / monitor). Rows show
   `size · resolution @scale` and a per-kind glyph (`rowGlyphFor`); disabled
   rows show the slashed monitor-off glyph. A `Quickshell.screens`-count
   watcher refreshes state on hotplug/external toggles. Nothing is hardcoded
   per monitor — all metadata comes from the EDID and live compositor state.
8. **Reopen popup after toggles** — the backend persists via
   `hyprctl reload`, and a toggle that changes the enabled-screen count
   remaps bars, destroying the popup surface (a plain reload does not —
   verified). `toggleDisplay` remembers `root.opened`, and an
   `actionProc.onExited` handler reopens the panel ~600 ms after a
   successful toggle. Failed toggles (last-display guard) don't reopen. If
   the disabled monitor owned this bar, nothing reopens — correct,
   since that surface is gone.
9. **Keyboard hints footer** — a `PanelSeparator` + centered caption under
   the DISPLAYS section (`↑↓ navigate · ←→ adjust · ⏎ toggle display · esc
   close`). Pure discoverability for the keyboard-first toggle flow; no
   logic.

## Re-sync procedure (after each Omarchy update)

1. Check whether upstream touched the widget:
   `pacman -Q omarchy` and compare against the version above; then
   `diff /usr/share/omarchy/shell/plugins/panels/monitor/Panel.qml Panel.qml`
   ignoring the fenced blocks.
2. If upstream changed: copy the fresh `Panel.qml` / `Model.js` over ours,
   re-apply the nine patches above (all within `monitor-switcher fork`
   fences), and update the version in the table.
3. Run the smoke matrix:
   - panel opens; brightness slider + scroll-wheel brightness + OSD work
   - BRIGHTNESS header names the focused display when >1 is managed
   - DISPLAYS rows show aliases, `size · resolution @scale` captions, and
     per-class glyphs (slashed monitor when off); unplug/replug updates rows
   - text size slider snaps through its stops; scale pills apply
   - toggle a monitor off → row unchecks; survives `hyprctl reload` + 10 s
     (the `omarchy-hyprland-monitor-watch` reaction window)
   - toggle it back on → returns to its previous position/scale
   - last enabled display refuses to turn off
   - IPC: `omarchy-shell case.monitor-switcher state` answers

## Notes for future maintainers

- The shell's plugin validator rejects symlinks inside installed plugin
  folders, so the vendored files must be real copies — drift is managed by
  this document, not by linking.
- Keep the patch set minimal on purpose. Every extra line of delta is merge
  work on each Omarchy release. Features that don't require forking belong
  in `bin/monitor-switcher`, not in this file.
