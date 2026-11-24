# Multiple displays (1.4.6)

Settings → Displays offers All displays, Main display, Built-in display, or Custom.
Every connected display also has its own **Show notch** switch. Flipping one while
All, Main or Built-in is selected seeds Custom with the displays that were eligible
and then applies the switch, so a single monitor can be turned off without first
choosing Custom. In Custom, enable each connected display individually. Selections
use display UUIDs rather than temporary display numbers; disconnected selections
remain saved and can be forgotten. No selected displays means no notch panels, not a
fallback to another screen. Main means the macOS main display, not whichever screen
has keyboard focus. Built-in falls back to the main display in clamshell mode. Each
row also shows Main, Built-in or External and the display's logical resolution.

Automatic shape uses the hardware notch where available and an island everywhere
else, including external monitors, Sidecar, and MacBook resolutions that omit the
notch. The clipboard shortcut and open/close commands target the enabled display
under the pointer, falling back to built-in, then main/first eligible display.
Displays concealed by a fullscreen app remain eligible for explicit shortcut and
API opens; opening one slides it back down.

## Fullscreen

While a fullscreen app covers a display, the notch slides above the top edge and
stays registered, so it can come back without rebuilding its window. Attention
activities slide it back: an agent needs you or finishes, a usage warning, a
finished timer or low battery, a download keep/done/trash prompt, a screenshot, or
a transient custom activity. Running agents, an active timer, an upcoming meeting,
download progress, music, volume, brightness and the other ambient states stay
concealed until the pointer reaches the top-centre wake strip. Hovering that strip
slides the notch down and opens the panel; clicking it also opens; moving away
closes and conceals after the close delay. Each display conceals independently.
`behavior.revealAlertsOnFullscreen` (default true) turns automatic alert reveals
off without disabling hover or explicit opens. **Expand for attention on** in
Settings → Displays limits those reveals to all enabled displays, the single
display currently chosen by **Show NotchNull on**, or selected displays. “Same as
Show on” follows every display when Show NotchNull on is All, and otherwise
follows the first eligible display. Every display row has an **Attention** switch. Flipping it while
All enabled displays or Same as Show on is chosen seeds Selected with the current
effective targets and then applies the switch; in Selected, the switches edit the
subset directly. Attention is disabled when that display's notch is off, and the
row says so. Unselected displays still reveal on hover or when opened. Attention
choices are remembered while a display is hidden or its notch is off; they take
effect again when that display is shown.
`behavior.attentionDisplay` is `enabled`, `followDisplay`, or `selected`, and
`behavior.attentionDisplays` holds the custom subset of display UUIDs. A saved UUID
cannot expand on a display whose notch is disabled, and disconnected selections
survive reconnects.

## Per-display shape

Settings › Style › **Default shape** picks a default for every screen (Automatic,
Notch or Island) and lists each screen with an inline segmented control: Default,
Auto, Notch or Island. Default stores nothing and follows the global picker; Auto
follows that screen's hardware, while Notch or Island force one. Choosing Default
again forgets that screen's entry. Overrides are keyed by display UUID, so they
survive reconnects, restarts and display-number changes. An override for a screen
that is not connected is kept and can be forgotten from the same list, and so is one
for a screen that is connected but gets no panel in the current display mode (for
example Custom with that screen left out): that row is titled with the screen's
name, so it is not mistaken for a disconnected one.

Island-only controls (pill content, 24-hour clock, satellites, width, height and
distance from the top) live in a separate **Island appearance** group, shown only
when at least one eligible display currently resolves to an island.

Automatic resolves per screen: a display showing a hardware notch uses the notch,
any other display floats an island. A MacBook that changes to a resolution
without the notch re-resolves without user action.

## Camera housing

The notch style normally reserves the middle for the camera housing: activity
wings, OSDs and the open panel's header stay clear of it. On a screen without a
hardware notch, the Advanced disclosure under Style's Default shape section offers
"Assume a camera housing" for that screen. With it off, an OSD such as the volume
HUD becomes one row across the middle, the open panel's header uses the full width,
and the closed body still draws the same black pill. A screen that really has a hardware notch always keeps
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
A screen's own `auto` follows that screen's hardware (an island where there is no
notch, the notch body where there is one), while `Default` in Settings stores
nothing and follows the global `look.shape` picker. All four choices are offered in
the per-screen segmented control, so a value written here is always visible and can
be changed back.
`housingGap` defaults to true. A syntactically valid UUID for a screen that is not
connected is kept; an invalid entry is reported and does not stop the others. An
entry that fails validation leaves that screen's stored override alone, so a typo
never changes or removes a shape; delete the entry instead to forget it.
Applying a shape card in Setup, or "Reset look, size and motion", clears every
override.

`notchnull status` reports connected displays (names, UUIDs, scale, logical size)
and panel display IDs, global frames, shapes, Window Server visibility, and each
panel's `fullscreen`, `concealed` and `reveal` state (`activity`, `hover`, `open`,
or null). Each panel also reports `attentionExpansion`, whether that display is
allowed to expand automatically for attention; each display's
`attentionRevision` changes when that permission changes, even if the panel's
visibility does not. `fullscreenHidden` remains the fullscreen-mode flag for
compatibility; `appKitVisible` can be true while `concealed` is true.
`behavior.selectedDisplays` in settings.json holds selected UUIDs; set
`behavior.display` to `selected` to use them.
`behavior.attentionDisplay` (`enabled` by default, `followDisplay`, or
`selected`) and `behavior.attentionDisplays` choose which of those notch-enabled
displays may expand for attention.

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
