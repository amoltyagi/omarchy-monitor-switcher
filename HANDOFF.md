# Monitor Switcher handoff — 2026-09-16

## Entry point and working-tree state

Real installed repository: `/home/case/Work/omarchy-monitor-switcher`.
Installed plugin symlink: `/home/case/.config/omarchy/plugins/case.monitor-switcher`.
Project mirror: `/home/case/.codex/.chatgpt-projects/g-p-6aaa6f83ed6c8191be2cca61c2983ad2`.
The mirror's `sources/` is read-only. No synced source was changed.

The repository already had substantial uncommitted work when this task began
(per-output night light, detached actions, recovery and UI work). Preserve it.
The user subsequently authorized committing all changes and pushing to GitHub.
The release is 3.1.0; the public name is simply Monitor Switcher. Existing
release/history claims in RECOVERY-NOTES.md refer to prior work.

## User requests handled

- Night Light choices should open at their own toggle, not inside the monitor illustration.
- Fix crowded/overlapping controls on LG and adapt to available display space/scaling.
- Inspect screenshots on every physical monitor.
- Re-enable the middle monitor after the user closes its gap by arranging 1 and 3 together.
- Add subtle macOS-like depth, gradients, and readable borders/text.
- Leave a portable explanation for another harness.

## Implementation

### UI

`DisplayGallery.qml`: separate `editing` (mode/refresh/scale inside the screen)
from `nightEditing`. A Qt Quick Controls Popup is parented to each Night Light
chip and opens below it, or above when there is insufficient space. Positive
window-edge margins keep it onscreen; opening recalculates available space. It shares the existing choice model, cursor, keyboard
selection and per-output apply signal. Outside press/Escape close it. Monitor
specifications remain visible. The chip exposes its popup for QML tests.

The resolution/status group has its own top-anchored row instead of being
vertically centered over the bottom refresh/scale row. `Model.galleryLayout`
now accepts optional `minimumHeight`; gallery requests 160 styled units and
wraps columns when controls would be crowded. Width/height use logical Qt
coordinates and Omarchy Style spacing; do not multiply by physical monitor scale.
`Panel.qml` requests 1160 styled units, fitted by KeyboardPanel to available
screen width. Its existing vertical ScrollView accommodates wrapped rows.

Monitor casings use a light-to-shaded gradient. Screens have a stronger but
subtle cool/warm gradient, diagonal reflected-light band, inner edge highlight,
and existing offset shadow. Fonts remain theme foreground; focus borders remain
accent. No raster assets, global theme settings or packaged Omarchy code changed.

### Returning monitor placement

`bin/monitor-switcher`: new `place_returning_display(output, live)` runs only
when enabling a currently disabled monitor, after removing its disabled flag,
inside the existing rollback-protected subshell.

It calculates logical boxes with the existing mode/scale/rotation helper.
If the returning box does not collide, positions are unchanged.
For a horizontal row (all boxes share a vertical interval), it reopens the old
slot, shifting boxes at/right of the insertion position by the returning width.
Thus 1–3 at x=0,1920 becomes 1–2–3 at x=0,1920,3840 when 2 returns.
If a box extends from the left into the saved slot, insertion begins after it.
Every proposed row is rechecked for overlap before writing.

For non-row layouts, it enumerates touching edge placements around active
boxes, rejects collisions, and chooses the one nearest the saved position.
It moves only the returning display in this fallback. Resolved active positions
are pinned so unpinned successors cannot accidentally follow the moved output.
Explicit Arrange/move/scale overlap validation remains strict. Ordinary apply
still verifies live geometry and power. Failure restores state/config and the
previous generated layout using existing rollback behavior.

Disabling a monitor does not automatically compact your arrangement; you retain
control of that operation. These changes concern explicit enable/toggle, not
automatic cable-hotplug restoration. On extremely small logical desktops, the
existing panel fitting/scrolling still applies; every advertised hardware mode
was not cycled during testing.

## Verification and screenshots

Actual screenshots were captured with `grim`, then cropped (no image generation).
Screenshots in the project mirror's `verification/`:

- `lg-before.png`: original LG crowding, most visible in disabled monitor cards.
- `lg-125-percent.png`: LG DP-2, 3840×1600, ~74.98 Hz, scale 1.25.
- `msi-187-5-percent.png`: MSI DP-3, 3840×2160, 240 Hz, scale 1.875.
- `acer-200-percent.png`: Acer HDMI-A-1, 3840×2160, ~60 Hz, scale 2.
- `acer-1080p-200-percent.png`: physical Acer temporarily at 1920×1080, scale 2
  (960×540 logical desktop), confirming wrapping/scrolling and the upward popup.

All three final screenshots were visually inspected, including an open Night
Light popup. A popup may target a different card than the physical screen hosting
the panel; that is intentional, and per-output targeting has an interaction test.
The screenshots reflect the user's active theme at capture time.

The additional 1080p check found a bottom-edge popup clipping bug. The final
implementation opens above the toggle and constrains to screen margins; its
actual screenshot and a dedicated QML interaction test both pass. The Acer was
then restored to its saved 4K mode.

Tests added/extended:
- QML: popup belongs to its chip, monitor specifications remain visible, per-output
  night-light signal is correct; actual row geometry does not overlap at panel
  widths 480, 760 and 1060 with MSI/LG/Acer physical proportions; upward opening
  near the window bottom keeps every option within the viewport.
- Model: minimum-height wrapping at available widths 456, 736 and 1036.
- Backend: returning middle monitor reopens its slot; failed reload restores the
  saved geometry/state; mixed-scale rotated vertical setup finds a free edge.

Commands (from real repository):

```sh
node --test --test-isolation=none tests/*.test.js
node --test --test-isolation=none --test-name-pattern='returning' tests/backend.test.js
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME= /usr/lib/qt6/bin/qmltestrunner -input tests/ui -import tests/ui/imports
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
bash -n bin/monitor-switcher bin/monitor-action
git diff --check
```

Node 26's default subprocess test isolation reported only file-level failures in
this environment. `--test-isolation=none` exposes useful individual assertions.
The first new rollback assertion incorrectly required preservation of an extra
trailing newline. It was corrected to compare JSON values and the exact generated
Lua. The implementation already restored the correct values.

## Runtime/reload notes

QML changes through the installed symlink did not visibly apply with
`omarchy-shell shell rescanPlugins`; `omarchy restart shell` loaded them.
Read IPC with `omarchy-shell case.monitor-switcher state`; open/close with
`omarchy-shell case.monitor-switcher open` / `close`.

Hyprland here uses Lua APIs, e.g. `hyprctl eval 'hl.dispatch(hl.dsp.focus({monitor="DP-2"}))'`.
Temporary runtime monitor enabling needs `disabled=false` explicitly; merely
supplying mode/scale does not clear a previous disabled flag. These temporary
rules were removed with `hyprctl reload`, followed by `hyprctl configerrors`.

At task start LG alone was enabled. During the task the saved selection changed
to Acer alone (`state.json.disabled` contains DP-2 and DP-3). Final cleanup
restored that latest saved configuration, not the earlier LG-only selection.
No saved monitor preference files or night-light preferences were edited for
visual QA. Secondary monitor activation/deactivation can relocate workspaces.

## Relevant pre-existing architecture

`Panel.qml` is instantiated per physical screen. `PanelRegistry.js` selects the
IPC owner, shares snapshots and fences stale/in-flight actions. Do not bypass
that ownership when adding actions. `bin/monitor-action` detaches an action so
disabling its originating screen cannot terminate it. `bin/monitor-nightlight.py`
owns per-output gamma state and persistence. `Model.js` owns shared layout and
selection calculations. `ArrangementEditor.qml` is a preview; backend validation
and verification are authoritative. Recovery and trial/watchdog behavior were
already present and remain intact.

Persistent paths: `~/.config/monitor-switcher/config.json`,
`~/.config/monitor-switcher/night-light.json`, `~/.local/state/monitor-switcher/`,
`~/.local/state/omarchy/toggles/hypr/monitor-switcher.lua` (generated).
Do not edit `/usr/share/omarchy` or reset the dirty repository.

## Final validation record

- QML: 11 passing results (9 interaction cases plus setup/cleanup), including
  responsive row geometry and upward popup containment.
- Model/registry/action: 24 tests passed.
- Python per-output night-light tests: 9 passed.
- New returning-display backend cases: all 3 passed, including rollback.
- Bash syntax, Git whitespace checks and Hyprland configuration checks passed.

An earlier full backend run reported 70/71 because a comment-only edit changed
the shell file while a long-lived recovery process was still reading it. Its
error was a transient syntax error at a moved line, not a failed geometry or
rollback assertion. The same case passed immediately against the unchanged file.
Final full-suite verification therefore used a frozen copy under
`/tmp/monitor-fix/frozen/` to prevent mid-execution edits.

No live middle-monitor failure was deliberately induced; placement and failure
rollback were exercised through the fail-closed compositor fixture. All physical
UI checks and the temporary low-resolution check were done on the actual displays.

Final frozen backend run: **71/71 passed**, including the recovery case above
and all three new returning-monitor scenarios (270 seconds). The frozen backend
was byte-for-byte identical to the installed file (`cmp` verified). Together with
24 model/registry/action tests, all **95 Node tests passed** in final verification.
Python: **9/9 passed**. QML: **11 passing results**, no failures. There are no
outstanding failures from this task. The raw backend log is saved alongside the
screenshots in the project mirror as `verification/backend-results.txt`.

## GitHub publication preparation

The user authorized committing all accumulated changes and pushing to GitHub,
updating documentation, and replacing the previous screenshots. Public artwork
now gives almost the entire canvas to the plugin with one short caption. Fresh
real captures replace `assets/screenshots/displays.png` and `arrangement.png`;
`night-light.png` adds the open toggle menu. `preview.png` highlights MSI 4000 K,
LG 5000 K, Acer Off. These were actual independent gamma states, verified through
IPC. Original Night Light preferences were restored afterward, and the temporary
Acer activation was undone. MSI and LG were active before and after capture.

README, manifest, release notes, changelog, attribution/component documentation
and screenshot provenance have been updated for 3.1.0. Branding is “Monitor
Switcher” without a version suffix; the manifest/tag retain semantic versions.
No external marketplace messages were sent as part of this publication task.

## Publication complete

All accumulated implementation, tests, documentation and replacement screenshot
assets were committed and pushed to `origin/main` on September 16, 2026.
Implementation/release commit: `37d19d1428d13c45b2e8480de7ee8bda155284cf`.
Tag: `v3.1.0`.
Release: https://github.com/amoltyagi/omarchy-monitor-switcher/releases/tag/v3.1.0
Public title: **Monitor Switcher — Independent Night Light**.

The release is published (not a draft) and all five screenshot/preview attachments
were verified: preview.png, preview-detail.png, displays.png, night-light.png,
arrangement.png. Release-body images use immutable URLs at the implementation
commit. Main README embeds the replacement previews at their existing paths.
Original Night Light preference bytes were verified restored. The user continued
changing their active monitor selection during publication; no later selection
was overridden by cleanup.

Final release checks: plugin manifest validation, Bash/Python syntax, whitespace,
24 model/registry/action tests, 9 Python tests and 11 QML results all passed.
The installed backend is identical to the earlier frozen 71/71 passing backend
run. Artwork was rendered and visually inspected before committing. This
publication record is a documentation follow-up; it does not change released code.
