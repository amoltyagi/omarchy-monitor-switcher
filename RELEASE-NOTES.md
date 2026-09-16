# Monitor Switcher 3.0.1

## Clearer confirmations.

- No stale red “change pending” message after a preview ends.
- All monitor panels share the same action and confirmation state.
- Choosing the current setting does nothing; it no longer starts a preview.
- Focus another display without cancelling the preview.
- Normal timeouts are status messages. Actual failures remain visible.

Existing settings and shortcuts are preserved.

---

# Monitor Switcher 3.0

## Your desk. In order.

A major redesign of the monitor panel for Omarchy.

- **Settings on the display.** Click resolution, refresh rate or scale to edit.
- **Power, simplified.** An On/Off switch beneath every monitor.
- **Arrange by dragging.** Snap screens together or place them left, right, above or below.
- **Try it first.** Verified changes with 20-second Keep / Revert.
- **Shortcuts without the clutter.** The original monitor shortcut stays. More shortcuts opens the rest.

Rounded surfaces, clearer controls and theme-aware colors throughout.

### Under the surface

Monitor detection now handles a display without an active mode without losing
the rest. Saved settings and live values are shown separately. Power, focus and
layout changes are checked against the compositor, and duplicate monitor entries
are caught before they can produce conflicting rules.

### Update

```bash
omarchy plugin update case.monitor-switcher
```

Existing monitor settings and shortcuts carry forward.

![The redesigned display panel](https://raw.githubusercontent.com/amoltyagi/omarchy-monitor-switcher/v3.0.0/preview.png)

![The new arrangement view](https://raw.githubusercontent.com/amoltyagi/omarchy-monitor-switcher/v3.0.0/preview-detail.png)
