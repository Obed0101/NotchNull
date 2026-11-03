# Tasks

## 1. Island OSD keeps a fixed row width

- [x] 1.1 Add `osdRowWidth` to `NotchViewModel` (island: the volume/brightness HUD width × `activityWidthScale`, clamped to the canvas limit; otherwise `nil`), and verify with a `swift test` case that it is non-nil and equal to `196 × scale` for an island and `nil` for a notch body without the housing and for a notch body with it.
- [x] 1.2 Add a test asserting the invariant the view relies on: on an island the pinned row is not wider than `bodySize.width` for `.activity(.volume)`, and on a no-housing notch `osdRowWidth` is `nil` so the row fills the body. Verify it fails if `osdRowWidth` is changed back to `nil` for the island.
- [x] 1.3 In `LevelActivity`, size the spanning row with `.frame(width: model.osdRowWidth)` plus `.frame(maxWidth: model.osdRowWidth == nil ? .infinity : nil)`, fix the comment on lines 37-39 to describe the pinned island row, and verify with `swift build` plus the existing `DisplayShapeTests` width assertions still passing.
- [x] 1.4 Append an island volume snapshot and its no-housing counterpart to the snapshot set and verify, by comparing against the PR's paired `housing-on`/`nohousing` renders, that the island HUD width is unchanged and the no-housing bar still crosses the centre.

## 2. Per-screen picker shows every accepted value

- [x] 2.1 Offer `nil` (Default), `.auto` (Automatic), `.notch` and `.island` in the per-screen `Picker` in `Sources/NotchNull/UI/Settings/CustomizeSettings.swift`, widening the control for the longest label, and verify by selecting each option and confirming `preferences.displayShapes` stores `DisplayShape(style:)` with the matching value and that Default stores no entry.
- [x] 2.2 Show the stored value in `screenSubtitle` so a row reads e.g. `Automatic · Island` and an overridden row is distinguishable from a Default row on the same resolved presentation; verify by rendering the Style page with overrides set to `auto`, `notch` and `island` and confirming each subtitle names its stored value.
- [x] 2.3 Extend the `settings.json` round-trip test to cover `"shape": "auto"` per display, asserting `SettingsFile.apply` accepts it, the map holds `.auto`, and the value the picker would show is `.auto` rather than absent; verify the test fails against the previous tag set.
- [x] 2.4 Document in `docs/multiple-displays.md` that per-screen entries accept `auto`, `notch` and `island`, and that a screen's own `auto` follows that screen's hardware while `Default` follows the global picker; verify the documented example applies with no reported problems.

## 3. Tests no longer depend on real preferences or fixed sleeps

- [x] 3.1 Save and restore `islandSatellites` in `DisplayShapeTests.setUp`/`tearDown`, setting it to `true` in `setUp`, and verify the suite passes with `islandSatellites` set to `false` beforehand (simulate by pre-setting the default before the run).
- [x] 3.2 Replace the three fixed `RunLoop.main.run(until:)` waits in `testSwitchingToIslandMovesPlayingMusicIntoItsSatellite` with a bounded poll of the expected `phase` (check the condition first, slice the run loop, fail with the expected phase after the deadline), and verify the test passes and that an impossible expectation fails after the bound rather than hanging.
- [x] 3.3 Confirm the tests no longer read any preference they do not restore: list every preference the class touches and verify each has a `setUp` value and a `tearDown` restore, using a read of the final file.

## 4. Integration

- [x] 4.1 Run `swift test` on `feat/display-shape` and confirm the full suite passes with no skipped tests other than the pre-existing opt-in live test.
- [x] 4.2 Run `scripts/build-app.sh` and confirm a clean release build.
- [x] 4.3 On a two-display setup, verify the volume HUD stays put while the island closes, that a stored `"shape": "auto"` row shows Automatic, and that the no-housing OSD still spans the body.

## Workflow follow-up

- Reply to each of the three review findings on PR #23 with the commit that addresses it.
- Archive the change once the fixes are on `feat/display-shape` and reviewed.
