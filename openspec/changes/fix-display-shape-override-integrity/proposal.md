# Proposal

## Why

The review of PR #23 left two findings on the per-display shape override that round one did not
cover. Both were re-checked against `3806381` and still hold, and both fail on ordinary setups
rather than exotic ones.

1. An override for a screen that is connected but gets no panel can be neither seen nor removed.
   The Style page builds its per-screen rows from `eligibleDisplays`
   (`Sources/NotchNull/UI/Settings/CustomizeSettings.swift:123`), while `disconnectedOverrides`
   (:38-41) filters against every connected screen. With `behavior.display` on `main`, `builtIn` or
   `selected`, a connected screen that is not shown has no row, and its override is also excluded
   from the "Disconnected display" list; because `displayShapes` is non-empty, `showsScreenRows`
   (:45-47) keeps the section visible. The override becomes unreachable and the docs claim stored
   overrides can be forgotten from that list.
2. A `look.displays` entry that fails validation silently deletes that UUID's previous override.
   The write closure (`Sources/NotchNull/Platform/SettingsFile.swift:146-175`) starts from an empty
   dictionary, skips an invalid entry with `continue`, then assigns the result to
   `preferences.displayShapes`. The previously stored override for that UUID is dropped, and the
   `snapshot()` rewrite 400 ms later (`:34-37`, `:99-107`) writes a `settings.json` without that
   entry, so the user's text is gone too. Every other settings field keeps its old value and only
   reports a problem.

## What Changes

- Every screen that stores an override becomes reachable in Settings: an override for a screen that
  is connected but not currently shown is listed and can be forgotten, and a row's title says which
  case it is instead of calling a connected screen disconnected.
- A rejected `look.displays` entry keeps that UUID's previously stored override and reports the
  problem. Valid entries in the same object still apply, and omitting an entry still removes the
  override, so behaviour the spec already promises is preserved.
- No change to the stored format of `look.displays`, to the resolution rules, or to the settings
  file's canonical rewrite.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `display-shape`: the "Configuration is exposed and resettable" requirement becomes explicit about
  reachability (every stored override can be seen and forgotten from Settings, whatever the display
  mode) and about integrity (an entry that fails validation must not discard the override already
  stored for that display).

## Impact

- `Sources/NotchNull/UI/Settings/CustomizeSettings.swift`: the per-screen row list, the
  disconnected-override list and the row titles that distinguish the two cases.
- `Sources/NotchNull/Platform/SettingsFile.swift`: the `look.displays` write closure keeps previous
  values for rejected entries.
- `docs/multiple-displays.md`: states that an override for a screen that is connected but not shown
  is also listed and can be forgotten, and that a rejected entry leaves the stored override alone.
- Tests: the `look.displays` round-trip test gains the rejected-entry-keeps-its-value case; the list
  that the rows are built from is made testable so reachability is covered without rendering.
- Unchanged: `Preferences.DisplayShape` and its encoding, `DisplayShapeResolver`, the silhouette
  rules, snapshots, and status output.
