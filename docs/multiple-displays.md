# Multiple displays (1.4.6)

Settings → General → Displays offers Built-in, Main, All, or Selected displays.
In Selected mode, enable each connected display individually. Selections use display
UUIDs rather than temporary display numbers; disconnected selections remain saved
and can be forgotten. No selected displays means no notch panels, not a fallback to
another screen. Main means the macOS main display, not whichever screen has keyboard
focus. Built-in falls back to the main display in clamshell mode.

Automatic shape uses the hardware notch where available and an island everywhere
else, including external monitors, Sidecar, and MacBook resolutions that omit the
notch. The clipboard shortcut and open/close commands target the enabled display
under the pointer, falling back to built-in, then main/first eligible display.
Fullscreen-hidden displays are excluded from shortcut targeting.

## Per-display shape

Settings › Style › Shape picks a default for every screen (Automatic, Notch or
Island) and lists each screen so it can keep its own choice: Default, Notch or
Island. Default stores nothing and follows the global picker; choosing Default
again forgets that screen's entry. Overrides are keyed by display UUID, so they
survive reconnects, restarts and display-number changes. An override for a screen
that is not connected is kept and can be forgotten from the same list.

Automatic resolves per screen: a display showing a hardware notch uses the notch,
any other display floats an island. A MacBook that changes to a resolution
without the notch re-resolves without user action.

## Camera housing

The notch style normally reserves the middle for the camera housing: activity
wings, OSDs and the open panel's header stay clear of it. On a screen without a
hardware notch, the Shape page also offers "Assume a camera housing" for that
screen. With it off, an OSD such as the volume HUD becomes one row across the
middle, the open panel's header uses the full width, and the closed body still
draws the same black pill. A screen that really has a hardware notch always keeps
the housing, whatever is stored.

`look.displays` in settings.json holds the overrides, and `status` reports each
display's resolved shape and whether it assumes a housing:

```json
"look": {
  "shape": "auto",
  "displays": {
    "37D8832A-2D66-02CA-B9F7-8F30A301B230": { "shape": "notch", "housingGap": false }
  }
}
```

An entry needs a valid display UUID and one of `auto`, `notch` or `island`.
`housingGap` defaults to true. A syntactically valid UUID for a screen that is not
connected is kept; an invalid entry is reported and does not stop the others.
Applying a shape card in Setup, or "Reset look, size and motion", clears every
override.

`notchnull status` reports connected displays (names, UUIDs, scale, logical size)
and panel display IDs, global frames, shapes, and Window Server visibility.
`behavior.selectedDisplays` in settings.json holds selected UUIDs; set
`behavior.display` to `selected` to use them.

## Checked on real connected hardware

- Built-in Retina: 1800 × 1125 logical points, 2×, island at this resolution.
- HP 23er: 1920 × 1080 points, 1×, positioned right of the MacBook.
- iPad / Sidecar: 1055 × 744 points, 2×, positioned left (negative global X).
- All three panels registered and visible in Window Server at once.
- Main, Built-in, Selected (monitor + iPad), Selected (empty), and All returned
  exactly the expected panels through the running app API.
- Open Home under each display's pointer: inspected real screen captures; centered
  panels fit and their content renders at each display's scale. Controls satellite
  also rendered on all three. Idle clocks inspected on all three.
- 178 automated tests, zero failures, one opt-in live-update test skipped.
  Selection/reconnect identity, clamshell fallback, negative coordinates, geometry,
  and invalid settings are covered by DisplaySelectionTests.

Local evidence is in `build/multidisplay-check/` (not published: desktop captures
contain personal content). Original settings are backed up there. Test changes to
unrelated settings were restored; All displays is left enabled.

## Still requires hands-on checking

Physical unplug/reconnect, Sidecar disconnect/reconnect UUID stability, changing
which display is main, changing resolution/rotation, sleep/wake, clamshell, and
fullscreen/Spaces transitions were not physically exercised in this check.
The real clipboard keyboard shortcut was not verified; synthetic key events did
not trigger it in this environment. Its per-display target selection is covered
by unit tests and the real API open commands above.
