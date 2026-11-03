# Tasks

## 1. A rejected entry keeps the override it already had

- [x] 1.1 In `SettingsFile`'s `look.displays` write closure, start from `preferences.displayShapes` instead of an empty dictionary so a rejected entry leaves that UUID's stored override untouched, and verify with a `swift test` case that stores a valid override, then applies `"shape":"round"` for the same UUID and asserts the problem is reported, `displayShapes[id]` is unchanged, and `DisplayShapeResolver.resolve` returns the same presentation as before.
- [x] 1.2 Verify the accepted entries still apply when one entry in the same object is rejected, and that omitting an entry still removes its override: extend `testSettingsFileAppliesValidOverridesAndRejectsOnlyBadEntries` with a two-entry object where one is invalid and a third assertion that re-applying without an entry clears it; confirm the test fails if the closure is switched back to an empty starting dictionary.
- [x] 1.3 Verify a rejected entry does not survive a rewrite as stale text: after the failed apply, call `SettingsFile.shared.snapshot()` and assert its `look.displays` object still contains the previously stored value for that UUID, so the debounced `write()` cannot erase it.

## 2. Every stored override is reachable in Settings

- [x] 2.1 Move the orphan-row computation out of `StyleSettings` into a pure helper that takes the stored identifiers, the connected identifiers and the eligible identifiers and returns the rows with a `connected` flag, and verify with unit tests that cover: an override for an eligible screen produces no orphan row, an override for a connected-but-ineligible screen produces one flagged connected, and an override for an absent screen produces one flagged disconnected.
- [x] 2.2 Build the per-screen rows from the helper's two outputs so a connected-but-unshown screen gets a row with its name, a subtitle saying it gets no panel in the current display mode, and a Forget button, while an absent screen keeps the "Disconnected display" title with its identifier; verify by setting `behavior.display` to `selected` with an override stored for an unselected connected screen and confirming the row appears and Forget removes the entry.
- [x] 2.3 Confirm the section no longer shows an override it cannot act on: assert with a test that when the eligible set is empty and `displayShapes` holds one entry, the helper returns a row for it, and verify on screen that `showsScreenRows` being true now always comes with at least one actionable row.
- [x] 2.4 Update `docs/multiple-displays.md` to state that an override for a screen that is connected but not shown is also listed and can be forgotten, and that a rejected entry leaves the stored override alone; verify the documented example still applies with no reported problems.

## 3. Integration

- [x] 3.1 Run `swift test` and confirm the full suite passes with no skipped tests other than the pre-existing opt-in live test.
- [x] 3.2 Run `scripts/build-app.sh` and confirm a clean release build.
- [x] 3.3 Live pass on a two-display setup: store an override for the external screen, switch `behavior.display` to `selected` without selecting it, confirm the row and its Forget button, and confirm editing the entry to an invalid value in `settings.json` reports the problem while the screen keeps its shape and the file keeps its old value.
