# Screenshots

Three fresh Monitor Switcher captures taken on the MSI MPG272UX OLED (DP-3),
September 16, 2026: 3840×2160 at 240 Hz, 187.5% scaling. The higher pixel density
provides native captures about 1993 pixels wide, preserving sharper UI detail
than the previous LG captures. The user's current dark theme is unchanged.

Display values and controls are unaltered; images are tightly cropped to the
plugin. Public artwork uses a short caption, small margins and the screenshot
at native pixel size. The README and GitHub release show exactly three images:

1. `preview.png` / `displays.png` — **monitor management hero**: resolution,
   refresh, scale, power, brightness and Arrange, with no open Night Light menu.
2. `preview-night-light.png` / `night-light.png` — **secondary feature**:
   MSI 4000 K, LG 5000 K, Acer off, with MSI's independent temperature menu.
3. `preview-detail.png` / `arrangement.png` — **desktop arrangement**:
   three connected desktops, snap preview, placement controls and Apply.

All three were newly captured on MSI; these supersede the earlier LG images.
The Night Light example was applied to the real outputs and verified by live
IPC before capture. Original Night Light preferences were restored byte for
byte afterward. Acer was temporarily enabled, then restored to its prior off
state; MSI and LG remain active.

Editable artwork is in `../hero.svg`, `../night-light.svg` and `../arrangement.svg`.
Render from the repository root:

```bash
rsvg-convert assets/hero.svg -o preview.png
rsvg-convert assets/night-light.svg -o preview-night-light.png
rsvg-convert assets/arrangement.svg -o preview-detail.png
```
