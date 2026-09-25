# Monitor Switcher 3.2 — Rotation

Your displays. One place. Now in portrait, too.

Manage resolution, refresh rate, scale, rotation, power and desktop layout from one panel.

![Monitor Switcher panel with MSI and LG in landscape and the Acer in portrait](preview.png)

## Turn it portrait

Every monitor now has a small rotation button on its chin. Click it (or press
`O`), choose **Landscape**, **Portrait · turned right**, **Portrait · turned
left** or **Upside down**, and watch the card turn.

![Rotation menu opened from the Acer's chin, Portrait · turned right checked](preview-rotation.png)

- **Neighbours make room.** Rotation works like a pivot stand. In a row the
  screen keeps its left edge, and displays to its right slide over so your
  pointer still crosses cleanly. Columns do the same downward. Other layouts
  use the nearest free edge.
- **Nothing can strand you.** Every rotation is a verified 20-second
  Keep/Revert trial. Do nothing and your previous layout comes back.
  Impossible layouts are refused before anything changes.
- **Portrait looks portrait.** Cards keep their true shape, controls stack to
  stay readable, and Arrange shows the new footprint.
- **Scriptable.** `monitor-switcher rotate Acer 90` (also `0`, `180`, `270`,
  `next`, `prev`) for keybinds and scripts.

## Arrange around it

![Arrangement with the portrait Acer beside MSI and LG](preview-detail.png)

Night Light per monitor, power toggles, verified recovery and every existing
setting and shortcut carry forward.
[See the Night Light menu](assets/screenshots/night-light.png).

Update with:

```bash
omarchy plugin update case.monitor-switcher
```

[Full changelog](CHANGELOG.md) · [README](README.md)
