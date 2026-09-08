# Upstream fork tracking

`Panel.qml` and `Model.js` derive from Omarchy's built-in Display widget
(`omarchy.monitor`). The local gallery, refresh trials and wheel-safe controls
extend that original fork; they are not supplied by the upstream widget.

## Provenance

| | |
|---|---|
| Source | `/usr/share/omarchy/shell/plugins/panels/monitor/{Panel.qml,Model.js}` |
| Upstream repo | https://github.com/basecamp/omarchy |
| Forked from | Omarchy **4.0.0** (`pacman -Q omarchy` → `4.0.0-1`) |
| License | MIT, (c) David Heinemeier Hansson — see `LICENSE.upstream` |

## The patch set

Local feature blocks carry `monitor-switcher fork` comments. Locate them with:

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
3. **Bar logo** - `MonitorLogo.qml` provides a theme-tinted vector through
   `BarIconButton.iconComponent`, with the existing tooltip and click behavior.
   Its two-screen/slider mark stays stable as monitors are switched off.
   The same mark appears beside the panel title and in the README's `logo.svg`.
4. **Panel title** — hero reads "Monitor Switcher" instead of "Display", so
   screenshots in issue reports are attributable to the right project.
5. **Named, numbered gallery** — a second `Process` polls
   `bin/monitor-switcher state --json` into a `switcherMeta` map (fired from
   `refresh()`). `galleryMonitors` sorts connected displays by config-order
   number; illustrations show that number, alias and configured geometry.
   `activateCursor` indexes the same array and calls the persistent backend.
   Numbers match `monitor-switcher toggle N` and the existing keybindings.
6. **Brightness target label** — the BRIGHTNESS section header names the
   focused display it controls (`BRIGHTNESS · ACER`), mirroring upstream's
   SCALE header pattern. Upstream's slider only ever targets the focused
   monitor, and a disabled monitor can't be focused — this label makes that
   visible instead of looking like a missing feature.
7. **Physical size and hotplug** — the backend's `state --json`
   derives per-monitor `inches` (EDID mm via `hyprctl monitors all`) and
   `kind` (laptop / ultrawide ≥ 2.3 aspect / tv ≥ 38" / monitor). The gallery
   shows size, resolution, scale and live Hz, with dimmed off screens. A
   `Quickshell.screens`-count watcher refreshes state on hotplug/external toggles.
8. **Reopen popup after toggles** — the backend persists via
   `hyprctl reload`, and a toggle that changes the enabled-screen count
   remaps bars, destroying the popup surface (a plain reload does not —
   verified). `toggleDisplay` remembers `root.opened`, and an
   `actionProc.onExited` handler reopens the panel ~600 ms after a
   successful toggle. Failed toggles (last-display guard) don't reopen. If
   the disabled monitor owned this bar, nothing reopens — correct,
   since that surface is gone.
9. **Keyboard hint footer** — a `PanelSeparator` + one centered caption
   at the bottom of the panel suggesting the adoptable keybind convention
   (`Keyboard shortcut: SUPER+SHIFT+CTRL+1…N`, N tracks
   `root.displays.length`; only shown with 2+ displays). Pure
   discoverability; no logic.
10. **Bounded process output** — every `Process` command that feeds a
    `StdioCollector` is wrapped with `| head -c N` (argv-safe `bash -c`
    form; the installed `StdioCollector` exposes no size limit, so the cap
    lives in the spawned command). Covers `stateProc`, `switcherProc`,
    `setBrightnessProc`, `actionProc` (toggle + scale assignments), and
    `textScaleProc`. Marketplace review finding on #1918.
11. **Scale via backend** — `setScale()` calls
    `bin/monitor-switcher scale <focused> <factor>` instead of
    `omarchy-hyprland-monitor-scaling` (whose runtime-only
    `position="auto"` poke the generated layout reverts on the next reload,
    and whose live-refreshRate mode string some panels reject outright).
    The backend rounds to a Hyprland-clean scale, persists it in
    `config.json`, and re-applies through the overlap validator; packing
    reflows automatically.
12. **Display gallery and refresh controls** - `DisplayGallery.qml` renders
    theme-aware monitor silhouettes using configured dimensions and rotation,
    including dimmed disabled monitors. `Model.js` adds geometry and precise
    refresh matching/formatting helpers. The panel displays live Hz and an
    indexed, advertised-mode slider, keyboard preview/commit, pending countdown,
    Keep/Revert controls, and backend errors. Layout actions are serialized;
    bounded command pipelines preserve failure status with `pipefail`.
    The backend owns persistence, live verification and independent rollback.
13. **Integrated gallery controls and wheel-safe sliders** - numbered gallery
    illustrations, size/resolution/scale metadata and On/Off buttons replace
    the duplicate bottom display list. Existing keyboard shortcuts and the
    exact shortcut footer remain. Scale is an indexed slider including the
    custom current value. `DragSlider.qml` intercepts wheel input for panel
    scrolling; the bar no longer changes brightness on wheel gestures.

## Re-sync procedure (after each Omarchy update)

1. Check whether upstream touched the widget:
   `pacman -Q omarchy` and compare against the version above; then
   `diff /usr/share/omarchy/shell/plugins/panels/monitor/Panel.qml Panel.qml`
   ignoring the fenced blocks.
2. If upstream changed: copy the fresh `Panel.qml` / `Model.js` over ours,
   re-apply the patches above (all within `monitor-switcher fork`
   fences), and update the version in the table.
3. Run the smoke matrix:
   - panel opens; brightness dragging works, wheel gestures never change settings
   - BRIGHTNESS header names the focused display when >1 is managed
   - gallery shows number, alias, size, resolution, scale and On/Off buttons;
     unplug/replug updates the gallery; original shortcut footer remains
   - text size and scale sliders snap through their stops; release applies
   - toggle a monitor off → gallery button reads Off; survives `hyprctl reload` + 10 s
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
