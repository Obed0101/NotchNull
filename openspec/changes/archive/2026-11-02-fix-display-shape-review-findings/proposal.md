# Proposal

## Why

PR #23 (per-display shape and an optional camera housing) passed CI but its review left three
minor findings open against the `feat/display-shape` branch. They are real defect-shaped gaps in
behaviour that PR #23 itself introduced, so they should be closed on that branch before it merges
rather than as follow-up work on `main`.

All three were re-checked against `7fc5355`:

1. `Sources/NotchNull/UI/Activities/MediaActivities.swift:48` now sizes the island's OSD row with
   `.frame(maxWidth: spanningRowWidth)`. `NotchRootView` proposes `model.bodySize.width` to the
   content, so while the island shrinks back to `.closed` the row — and the `LevelBar`'s
   `GeometryReader` — re-measure on every frame. Before this PR the row was pinned with
   `.frame(width: islandRowWidth)` so an exit only clipped and faded it. The comment on lines
   37-39 still promises the pinned behaviour.
2. `Sources/NotchNull/Platform/SettingsFile.swift:160` accepts `"shape": "auto"` in `look.displays`
   and `docs/multiple-displays.md:51` documents it, but the per-screen `Picker` in
   `Sources/NotchNull/UI/Settings/CustomizeSettings.swift:127-130` only tags `nil`, `.notch` and
   `.island`. A stored `.auto` override selects no tag, so the control renders blank and the user
   cannot see or restore the value. `housingBinding` can also create that state itself when the
   global shape is Automatic.
3. `Tests/NotchNullTests/DisplayShapeTests.swift:13-21` saves and restores `shapeStyle`,
   `displayShapes` and `closedExtraWidth` but not `islandSatellites`, although
   `testSwitchingToIslandMovesPlayingMusicIntoItsSatellite` depends on `showsMusicSatellite`
   (`isIsland && preferences.islandSatellites`). The test therefore passes or fails depending on
   the developer's real preference. It also waits a fixed 0.05 s on the run loop three times,
   which is jitter-sensitive.

## What Changes

- Pin the island's spanning row to the HUD's own width again, so the volume/brightness OSD does
  not re-lay out per frame while the island closes. Keep the no-housing notch case filling the
  body, which is what the row needed in the first place.
- Make the per-screen shape control able to represent every value `look.displays` accepts:
  "Automatic" becomes a selectable per-screen option meaning "follow this screen's hardware",
  distinct from "Default" meaning "follow the global picker". The stored value then always has a
  matching tag and the row never renders blank.
- Make `DisplayShapeTests` independent of real user preferences and timing: pin and restore
  `islandSatellites`, and replace the fixed run-loop sleeps with a bounded wait for the expected
  `phase`.
- No behaviour change for anyone whose settings contain no `look.displays` entry, and no
  migration: `auto` keeps its meaning and becomes visible instead of invisible.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `display-shape`: the per-display shape control must be able to display and set every override
  value the settings file accepts, including Automatic; and the spanning OSD row must keep a fixed
  width while the body animates, so opting out of the camera housing does not reintroduce
  per-frame relayout.
- `notch-render-budget`: the shifting-content rules gain the case of a body whose width animates
  back to closed — its content must keep a stable layout instead of re-measuring every frame.

## Impact

- `Sources/NotchNull/UI/Activities/MediaActivities.swift`: `LevelActivity`'s island row sizing.
- `Sources/NotchNull/UI/Settings/CustomizeSettings.swift`: per-screen `Picker` options, the
  selection binding and the row subtitle.
- `docs/multiple-displays.md`: describe the four per-screen choices and Automatic's meaning.
- `Tests/NotchNullTests/DisplayShapeTests.swift`: fixture isolation and a bounded phase wait;
  new coverage for the picker option set and the pinned row width.
- Unchanged: `Preferences.DisplayShape` and its storage format, `SettingsFile` validation,
  `DisplayShapeResolver`, the silhouette rules, snapshots and status output.
