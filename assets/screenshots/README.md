# Screenshots

Four Monitor Switcher captures taken on the MSI MPG272UX OLED (DP-3),
September 25, 2026: 3840×2160 at 240 Hz, 187.5% scaling. The high pixel density
gives native captures 1993 pixels wide. The desk: MSI (landscape), LG ultrawide
(landscape, Night Light 4000 K) and Acer PE270K in portrait (90°, turned
clockwise), in the user's current theme.

Display values and controls are unaltered. Images are cropped to the plugin
panel; the desktop outside its rounded corners is masked with the artwork
background, so no windows or wallpaper appear.

The README and GitHub release show exactly three images:

1. `preview.png` / `displays.png` — **monitor management hero**: all three
   displays, with the chin rotation buttons (Acer at 90°), power and Night Light.
2. `preview-rotation.png` / `rotation.png` — **rotation (new in 3.2)**: the
   Acer's orientation menu opened from its chin, current choice checked.
3. `preview-detail.png` / `arrangement.png` — **desktop arrangement**: the
   portrait Acer beside MSI and LG in desktop space, with placement controls.

`night-light.png` is linked from the README: the LG's temperature menu open
from its toggle.

Editable artwork is in `../hero.svg`, `../rotation.svg`, `../arrangement.svg`
and `../night-light.svg`. Render from the repository root:

```bash
rsvg-convert assets/hero.svg -o preview.png
rsvg-convert assets/rotation.svg -o preview-rotation.png
rsvg-convert assets/arrangement.svg -o preview-detail.png
```
