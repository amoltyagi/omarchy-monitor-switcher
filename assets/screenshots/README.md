# Screenshots

Fresh real Monitor Switcher captures taken September 16, 2026, with the user's
current dark green theme. Images are cropped tightly to the plugin surface;
control labels and values are unaltered. The public artwork uses one short
caption and gives the plugin almost the entire canvas.

- `displays.png` — three active monitors: MSI at 4000 K, LG at 5000 K, Acer off.
- `night-light.png` — the same independent settings with MSI's toggle menu open.
- `arrangement.png` — a new three-monitor arrangement capture and Apply action.

The Night Light states were applied on the actual displays and confirmed by the
plugin's live state before capture. Previous Night Light settings and the user's
display selection were restored afterward. Captures used LG at 3840×1600 and
125% scaling; the interface was also checked on MSI at 187.5%, Acer at 200%,
and a smaller 1080p desktop during implementation.

The new screenshots replace the earlier screenshots at the same paths.
Editable artwork is in `../hero.svg` and `../arrangement.svg`. Render from the
repository root with:

```bash
rsvg-convert assets/hero.svg -o preview.png
rsvg-convert assets/arrangement.svg -o preview-detail.png
```
