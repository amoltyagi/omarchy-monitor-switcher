# Screenshots

Monitor Desk captures taken on the MSI MPG272UX OLED (DP-3), September 25,
2026: 3840×2160 at 240 Hz, 187.5% scaling. The desk: MSI and LG ultrawide in
landscape (LG Night Light 4000 K) and the Acer PE270K in portrait (90°, turned
clockwise), in the user's current theme, on an empty workspace.

For each state there are two real captures from the same `grim -o DP-3` frame:

- `displays.png`, `rotation.png`, `arrangement.png`, `night-light.png`: the
  complete plugin panel at native size (1993 px wide), top to bottom including
  Text size and the shortcut row, with transparent rounded corners.
- `desktop-*.jpg`: the surrounding MSI desktop (bar and wallpaper), used as the
  artwork backdrop.

Values and controls are unaltered. The artwork places the panel at its real
position on the desktop, darkens the free space and adds short bullets there.

The README and GitHub release show exactly three images:

1. `preview.png` (`../hero.svg`) — **monitor management hero**.
2. `preview-rotation.png` (`../rotation.svg`) — **rotation, new in 3.2**: the
   Acer's orientation menu opened from its chin.
3. `preview-detail.png` (`../arrangement.svg`) — **desktop arrangement** with
   the portrait Acer.

`night-light.png` is linked from the README; `../night-light.svg` is its
editable showcase. Render from the repository root:

```bash
rsvg-convert assets/hero.svg -o preview.png
rsvg-convert assets/rotation.svg -o preview-rotation.png
rsvg-convert assets/arrangement.svg -o preview-detail.png
```
