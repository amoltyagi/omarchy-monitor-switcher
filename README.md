# Monitor Switcher

An [Omarchy](https://omarchy.org) shell plugin that **replaces the built-in
Display widget** with an identical twin — brightness, text size, scale
presets, display list — except its monitor on/off toggles are **persistent,
layout-aware, and overlap-proof**.

Built for **desktops with two or more external monitors**: switch panels
off and on from the bar, the keyboard, or a keybind — and have it stay that
way.

![preview](preview.png)

This is an **unofficial fork** of Omarchy's `omarchy.monitor` widget
(vendored at Omarchy 4.0.0, MIT — see `UPSTREAM.md`). It is not affiliated
with or supported by the Omarchy project. **Please report issues to this
repository, not to Omarchy.**

## Why this exists

Omarchy already has a great display-toggle story — **if you're on a laptop**.
The internal display gets a persistent toggle (`SUPER+CTRL+Delete`),
mirroring, lid-switch automation, and a recovery service, all backed by a
config-file mechanism that survives reloads and reboots.

External monitors get none of that. The built-in Display widget can toggle a
monitor, but only at runtime: the disable lives in no config file, so the
next `hyprctl reload` — a theme switch, a system refresh, the watcher's
recovery loop — silently turns it back on. Re-enable it and your position
and scale are gone (`auto` placement). The only persistent option is
hand-editing `monitors.lua`.

Monitor Switcher closes that gap:

- **Persistent on/off for every output** — the same toggles-dir mechanism
  Omarchy reserves for laptop panels, extended to all your monitors
- **Layout memory** — position, scale, mode, and transform per monitor;
  remaining screens re-pack left-to-right in a fixed order
- **Scriptable** — a CLI with aliases (`toggle MSI`) that survive output
  renumbering, so keybinds stay stable
- **Zero feature loss** — the built-in widget's full feature set
  (brightness, text size, scale) with real toggles on top

And switching deserves a keyboard home. Omarchy ships no keybind to power an
external display on or off, so display rows are **numbered 1…N
left-to-right** and the CLI answers `toggle 1`…`toggle N` — bind
`SUPER+SHIFT+CTRL+1…N` (a combo Omarchy leaves unclaimed) and every panel on
your desk is one keystroke away, listed in the `SUPER+K` keybindings sheet
like a first-party shortcut.

### Who it's for

- **Desktop users with two or more external monitors** — the audience the
  built-in tooling least serves
- **OLED owners** who switch panels off when idle (burn-in is real)
- **Streamers and anyone flipping between focus and full-battlestation
  layouts**
- **Anyone with a flaky-EDID monitor** whose runtime toggles keep getting
  reverted by the watcher daemon
- **Docked-laptop users** who want the same persistence for every screen,
  not just the internal one

Single monitor you never switch off? The built-in widget has you covered —
this plugin is for the rest of us.

### How this differs from layout editors

[Monitor Studio](https://omarchyplugins.com/plugin.html?id=io.github.vuhungthang.monitor-studio),
[hyprmoncfg](https://omarchyplugins.com/plugin.html?id=crmne.hyprmoncfg),
[Screens](https://omarchyplugins.com/plugin.html?id=im0001gt.screens) and
friends are **arrangement tools**: drag rectangles, pick modes, save
profiles. Monitor Switcher is a **switcher**: off-states that persist across
reloads and reboots, keybind-stable aliases, and layouts that are validated
for overlaps *before* they reach the compositor — Hyprland's "Monitor X
overlaps with other monitor(s)" error can never come from here. One caveat:
tools that each write `hl.monitor` rules fight over the same outputs — the
last reload wins. Use Monitor Switcher **or** a layout editor, not both.

## What you get

Everything the built-in Display widget already does, unchanged:

- brightness slider (plus scroll-on-the-bar-icon, with OSD) — it controls the
  **focused** monitor, which the header names (`BRIGHTNESS · ACER`)
- text size slider, scale presets for the focused monitor
- display on/off rows showing each monitor's **alias, physical size, and
  resolution@scale** (`LG  38" · 3840×1600 @1.25x`), with per-class icons
  (laptop / ultrawide / TV / monitor / slashed = off) read live from EDID —
  last-display lock, laptop internal/mirror handling
- instant reaction to **monitor hotplug** and external keybind toggles
- **keyboard control, mouse optional**: `↑`/`↓` to a display row,
  `⏎`/`space` switches that monitor on or off; `←`/`→` adjust sliders and
  walk the scale presets, `esc` close, `tab` hop to the next panel — and
  the popup footer shows the adoptable `SUPER+SHIFT+CTRL+1…N` shortcut

Plus what the built-in widget can't do:

- **persistent off-states** — a monitor you switch off stays off across
  `hyprctl reload`, reboots, and the `omarchy-hyprland-monitor-watch` daemon
- **overlap-proof layouts** — every layout is validated before applying; a
  colliding arrangement is refused with a clear message and your current
  layout is kept, instead of Hyprland auto-placing on top of your rules
- **layout memory** — enabled monitors pack left-to-right in a fixed order,
  each keeping its own position, scale, mode, and transform
- **manual arrangement from the CLI** — pin explicit positions or move
  monitors relative to each other (`move`/`swap`/`pack`), no drag canvas
  required
- a **CLI and aliases** (`toggle MSI` instead of `toggle DP-3`), so
  keybindings survive output renumbering

## Install

```bash
omarchy plugin add https://github.com/amoltyagi/omarchy-monitor-switcher --enable
```

Then, to avoid two display widgets in the bar, disable the built-in one:

```bash
omarchy plugin disable omarchy.monitor
```

This is Omarchy's official, fully reversible mechanism — it removes the
widget from your bar layout, nothing more. Bring it back any time with
`omarchy plugin enable omarchy.monitor`. (The plugin deliberately does **not**
do this for you; your bar layout is yours.) If you keep both enabled, they
coexist safely — they use separate IPC targets — but the built-in widget's
toggles remain runtime-only, so prefer toggling from Monitor Switcher.

On first run the plugin adopts your current monitor setup — no manual
configuration needed.

## Usage

**Bar:** click the monitor glyph to open the popup. Sliders and scale pills
behave exactly like the built-in widget. Click a display row (or move to it
with the arrow keys and hit `⏎`) to toggle that monitor persistently.
Scrolling the bar glyph adjusts brightness.

**Terminal:**

```bash
monitor-switcher state            # table of monitors (+ overlap warnings)
monitor-switcher state --json     # machine-readable
monitor-switcher toggle MSI       # alias, output name, or number: toggle 2
monitor-switcher disable DP-2
monitor-switcher enable LG
monitor-switcher apply            # re-apply layout from config
```

**Arranging** (all validated for overlaps before anything is applied — a
colliding change is refused and reverted):

```bash
monitor-switcher plan                # preview computed layout boxes
monitor-switcher move LG 2048x0      # pin a position (logical pixels)
monitor-switcher move LG above MSI   # or relative: left-of|right-of|above|below
monitor-switcher swap MSI LG         # exchange places in the pack order
monitor-switcher pack                # clear all pins, re-pack left-to-right
```

Unpinned monitors pack left-to-right in config order; a pinned monitor sits
exactly where you put it (vertical stacks, intentional gaps — anything
Hyprland allows). Geometry is derived from each monitor's **configured**
mode — never from a transient fallback mode it might be running during
hotplug — and rotation (odd transforms) is accounted for.

**Keybindings** (add to `~/.config/hypr/bindings.lua`, adjusting the path if
your plugin id differs):

```lua
-- 1/2/3 = left/center/right in the pack order — numbers are allocated
-- automatically, need no aliases, and survive output renumbering.
o.bind("SUPER + SHIFT + CTRL + 1", "Toggle display 1",
  "/home/USER/.config/omarchy/plugins/case.monitor-switcher/bin/monitor-switcher toggle 1")
o.bind("SUPER + SHIFT + CTRL + 2", "Toggle display 2",
  "/home/USER/.config/omarchy/plugins/case.monitor-switcher/bin/monitor-switcher toggle 2")
o.bind("SUPER + SHIFT + CTRL + 3", "Toggle display 3",
  "/home/USER/.config/omarchy/plugins/case.monitor-switcher/bin/monitor-switcher toggle 3")
```

`SUPER+SHIFT+CTRL+<number>` is unclaimed by Omarchy defaults, and because
the binds carry descriptions they show up in Omarchy's `SUPER+K`
keybindings sheet like first-party shortcuts. Prefer names? Aliases work
everywhere numbers do (`toggle MSI`) and likewise survive renumbering
(DP-1 ↔ DP-3 shuffling).

**IPC:** the panel answers on its own target, e.g.
`omarchy-shell case.monitor-switcher state` (brightness, focused monitor,
scale, display list) — same methods as the built-in widget, minus the
collision.

## Configuration

`~/.config/monitor-switcher/config.json` — created from your live setup on
first run. Array order is the left-to-right packing order:

```json
[
  { "output": "DP-3", "alias": "MSI",  "scale": 1.875 },
  { "output": "DP-2", "alias": "LG",   "scale": 1.25, "mode": "3840x1600@75" },
  { "output": "DP-1", "alias": "Acer", "scale": 1.875, "transform": 0 }
]
```

| Field       | Default       | Meaning                                  |
|-------------|---------------|------------------------------------------|
| `output`    | (required)    | Hyprland output name (`hyprctl monitors all`) |
| `alias`     | model name    | Display name in the panel; also usable as CLI/keybind id |
| `scale`     | live value    | Hyprland scale factor                    |
| `mode`      | `"preferred"` | Mode string, e.g. `"3840x2160@240"`      |
| `transform` | `0`           | Hyprland transform (1 = 90°, 3 = 270°)   |
| `position`  | (packed)      | Explicit `"XxY"` pin in logical pixels; unset = pack in array order |
| `mode_w`/`mode_h` | (managed) | Native-mode snapshot used for packing math when `mode` is `"preferred"` — written by the tool; pin an explicit `mode` instead of editing these |

After editing: `monitor-switcher apply`. Newly connected monitors are
adopted automatically (appended rightmost with their current scale). Every
apply is pre-flight validated: if the resulting boxes would overlap, nothing
is written and the current layout stays — fix the pins with
`monitor-switcher move`/`pack`.

Your hand-written `~/.config/hypr/monitors.lua` only needs a wildcard
fallback rule for monitors not managed by this plugin:

```lua
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
```

## Architecture

One bash backend (`bin/monitor-switcher`) owns **all** toggle/layout logic.
The panel is a vendored copy of Omarchy's Display widget whose
`toggleDisplay()` calls the backend instead of `hyprctl keyword monitor`;
the bar popup and any keybindings are thin callers, so behavior can never
drift between interfaces. Layout geometry is computed from the config
(never from a monitor's transient live mode), validated for overlaps, and
only then written:

```
Panel.qml (vendored fork) ──┐
                            ├─► bin/monitor-switcher ─► validate ─► write generated Lua ─► hyprctl reload
SUPER+SHIFT+CTRL+1/2/3    ──┘
```

State files:

| File | Role |
|------|------|
| `~/.config/monitor-switcher/config.json` | Your settings: order, alias, scale, mode, transform per monitor |
| `~/.local/state/monitor-switcher/state.json` | Runtime state: which outputs are off |
| `~/.local/state/omarchy/toggles/hypr/monitor-switcher.lua` | **Generated** layout; auto-sourced by Omarchy on every reload |

**Why the generated-Lua approach:** `hyprctl keyword monitor X,disable` is
runtime-only — it lives in no config file, so the next `hyprctl reload`
re-applies `monitors.lua` and silently turns the display back on. Reloads
happen for many reasons: theme switches, `omarchy-refresh`, and, on
multi-monitor desktops, the `monitor-watch` daemon's modeless-recovery loop
(a monitor that comes up modeless — partial EDID, powered off at boot —
keeps it retrying). Routing state through the toggle directory makes the
disable part of the config itself — the same mechanism Omarchy's own
laptop-display toggle uses (`internal-monitor-disable.lua`).

## Development

The repo is developed live through a symlink:

```bash
ln -s ~/Work/omarchy-monitor-switcher ~/.config/omarchy/plugins/case.monitor-switcher
omarchy plugin validate ~/Work/omarchy-monitor-switcher  # the validator rejects the symlinked path itself
omarchy restart shell   # QML changes need this: a rescan does not rebuild live bar widgets
```

Backend (`bin/monitor-switcher`) changes need no restart — the panel spawns
the script fresh on every call.

`Panel.qml` and `Model.js` are a **minimal-delta fork** of Omarchy's Display
widget — every local change is fenced with a `monitor-switcher fork` comment
(`grep -n "monitor-switcher fork" Panel.qml`). See `UPSTREAM.md` for the
provenance, the exact patch list, and the re-sync ritual to run after each
Omarchy update. Requires Omarchy ≥ 4.0.

Backend tests run against the live compositor; the useful manual matrix is:
toggle each monitor off/on, toggle the middle one (re-pack), refuse-to-kill
the last display, and confirm off-states survive `hyprctl reload` + 10s
(the watcher's reaction window). For the forked panel additionally check:
brightness slider + scroll-wheel + OSD, text-size stops, scale pills, and
`omarchy-shell case.monitor-switcher state`.

## Uninstall

```bash
omarchy plugin enable omarchy.monitor   # restore the built-in Display widget
omarchy plugin remove case.monitor-switcher
rm -f ~/.local/state/omarchy/toggles/hypr/monitor-switcher.lua
hyprctl reload
```

Then re-add any explicit monitor rules you want to `~/.config/hypr/monitors.lua`.

## License

The plugin's own code is MIT (see `LICENSE`). `Panel.qml` and `Model.js`
are derived from Omarchy, MIT, (c) David Heinemeier Hansson
(see `LICENSE.upstream`).
