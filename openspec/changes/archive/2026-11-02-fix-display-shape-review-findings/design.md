# Design

## Context

See `proposal.md` — Why. Three facts from the branch shape the approach:

- `NotchRootView` gives the body content `model.bodySize.width` as its proposed width
  (`Sources/NotchNull/UI/Notch/NotchRootView.swift:40`), and `bodySize` animates toward
  `closedSize.width` on exit. So any content sized with `maxWidth` is re-measured on every frame of
  that animation. `LevelActivity` was the only spanning row that this PR moved off a fixed width.
- The per-screen shape row is a `Picker` over `Preferences.ShapeStyle?`, where `nil` is Default.
  `Preferences.ShapeStyle` has three cases (`auto`, `notch`, `island`) and `SettingsFile` validates
  against the same enum, so the picker is missing exactly one tag.
- `DisplayShapeTests` drives `ActivityCenter` and reads back `NotchViewModel.phase`, which arrives
  through `center.$current.receive(on: RunLoop.main)`. There is no existing wait helper in the
  suite: `IslandTests` uses the same fixed `RunLoop.main.run(until:)` sleep, and only
  `OpencodeReadTests` uses XCTest expectations, for long external reads.

Island and no-housing-notch sizing must stay distinguishable: `bodySize` for an island activity is
`max(islandWidth × scale, minWidth × scale, closedSize.width)`, while the notch keeps
`closedSize.width + wing × 2 × scale` regardless of the housing. A row pinned to the HUD's own
width is therefore always narrower than or equal to an island body, and a row that fills the body
is what the no-housing notch wants.

## Goals / Non-Goals

**Goals:**

- Restore the island OSD's fixed row width without changing the no-housing notch's spanning row.
- Make the per-screen control a faithful view of `look.displays`, so every stored value is
  displayed and re-selectable.
- Make the new tests independent of the developer's preferences and of animation timing.

**Non-Goals:**

- Changing the stored shape model, the resolution rules, or `SettingsFile` validation. `auto` keeps
  its current meaning and remains a valid per-display value.
- Redesigning the Style page layout or the housing toggle.
- Touching the pre-existing `IslandTests` sleep, or adding a shared async-wait harness for the whole
  suite. Both are noted as follow-ups, not part of this change.

## Decisions

### 1. The row width becomes a model value, not a view computation

`LevelActivity` currently derives its spanning width from `ActivityKind.volume.layout.islandWidth`
and decides between fixed and filling inline. Instead, `NotchViewModel` gains:

```swift
/// Width one-row OSD content keeps while the body animates; nil means it fills the body.
var osdRowWidth: CGFloat? {
    isIsland ? Self.osdWidth(scale: CGFloat(preferences.activityWidthScale)) : nil
}
```

and the view applies

```swift
.frame(width: model.osdRowWidth)
.frame(maxWidth: model.osdRowWidth == nil ? .infinity : nil)
.frame(height: context.rowHeight)
```

Why the model: the surrounding assertions in `DisplayShapeTests` already read `bodySize`,
`wingGap` and `headerGap` from the model, so the invariant "the island row never exceeds the island
body, and the no-housing row fills it" becomes a unit test instead of a rendering check.
*Alternatives:* a `static func` on the view (testable but duplicates the preference read), a
`GeometryReader`-free `fixedSize` (does not constrain the `LevelBar`'s inner `GeometryReader`, so it
still re-measures), or leaving `maxWidth` and accepting the relayout (rejected: the review finding,
and the branch's own comment says otherwise).

The pinned width is the same 196 pt fallback that `IslandWidth` declares for volume and brightness,
so island rendering is byte-identical to the pre-PR behaviour. Because a pinned row inside a body
capped by the canvas could clip, the value is clamped to the same canvas limit `bodySize` uses; the
icon and value keep fixed frames, so a clip only trims the bar's breathing room.

### 2. The per-screen picker offers all four values, always

The picker tags become `nil` (Default), `.auto` (Automatic), `.notch`, `.island` — all four offered
unconditionally, so the control does not change shape depending on stored state, and a value written
by `settings.json` always has a matching tag. `shapeBinding` and the storage model are unchanged:
Automatic stores `DisplayShape(style: .auto)`.

`screenSubtitle` gains the stored value, so an Automatic row reads `Automatic · Island` (resolution
for that screen) rather than silently looking like an Island override. The picker's fixed width
grows to fit the longest label.

*Alternatives:* adding `.auto` only when such an entry already exists (the control would gain and
lose an option as files change); rejecting `auto` in `look.displays` (a breaking change to a value
the docs and a test already cover); normalising a stored `auto` to `nil` on load (silently rewrites
the user's file-backed setting and loses the distinction between "follow the global picker" and
"follow this screen").

### 3. Test isolation: pin every preference the test reads, and poll instead of sleeping

`DisplayShapeTests` saves and restores `islandSatellites` alongside the existing three preferences,
setting it to `true` in `setUp`, matching `IslandTests`. The three fixed 0.05 s waits become one
helper:

```swift
@discardableResult
private func waitFor(_ description: String, _ condition: () -> Bool, timeout: TimeInterval = 2) -> Bool
```

which spins `RunLoop.main` in 10 ms slices until the condition holds or the deadline passes, and
reports the description on failure. `condition` is checked first, so an already-satisfied state does
not wait at all.

*Alternatives:* `XCTestExpectation` on `model.$phase` (the "already there" case emits no second
value, and the initial emission fires before the subscription is set up); `Task.sleep` (the
delivery is on the run loop, not the cooperative executor, so it would not advance the sink).

## Risks / Trade-offs

- **Clipping on very small canvases** — the pinned island row can exceed the canvas-capped body →
  clamp to the canvas limit and keep fixed icon/value frames; the bar absorbs the difference.
- **Default vs Automatic confusion** — two options now both "resolve automatically" → subtitles name
  the stored value for every row, and `docs/multiple-displays.md` states the difference in one line.
- **Shared `Preferences.shared` in tests** — `DisplayShapeTests` and `IslandTests` mutate the same
  singleton; XCTest runs methods in a class serially, and both classes restore their keys, but
  parallel test classes would still race → out of scope here; the change keeps restore symmetry and
  leaves a follow-up note.
- **Polling helper can mask a slow machine** — a 2 s bound hides jitter instead of removing it → the
  condition is checked before each slice, so the pass path is immediate and only the failure path
  costs the timeout.

## Migration Plan

- No settings migration: `look.displays` entries keep their format, and `auto` stays valid.
- Rollback: revert the three commits; the only stored-state change is that a user may now have an
  explicit `auto` entry that the old UI shows blank — the same state the review flagged, not a
  regression.
- Verification: `swift test`, `scripts/build-app.sh`, and a snapshot pass for the island OSD plus the
  no-housing OSD to confirm widths are unchanged against the PR's paired renders.
