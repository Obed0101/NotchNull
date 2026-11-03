# Design

## Context

See `proposal.md` — Why. Three facts from the current code decide the approach:

- `StyleSettings` holds `displays = NotchDisplay.connected` (`CustomizeSettings.swift:8`) and derives
  two different sets from it: `eligibleDisplays` (:33-35, what gets a row) and
  `disconnectedOverrides` (:38-41, what gets a Forget row). `DisplaySelection.eligible`
  (`Core/DisplaySelection.swift:33-40`) narrows by `behavior.display`, so with `main`, `builtIn` or
  `selected` the two sets disagree about a connected screen.
- `showsScreenRows` (:45-47) is true whenever `displayShapes` is non-empty, so the section stays
  visible even when the only entry has no row.
- `SettingsFile`'s other fields read the current value, validate the incoming one, and leave the
  preference untouched on failure (`SettingsFile.swift:330-353`). The `look.displays` closure
  (:146-175) is the outlier: it rebuilds the whole dictionary and assigns it regardless.
  `apply()` only calls `write` when the file value differs from `read` (:77), so a rejected entry
  always reaches the closure, and `write()` (:99-107) then persists `snapshot()` 400 ms later.

## Goals / Non-Goals

**Goals:**

- Make every stored override reachable from Settings for the whole time the app runs, with a control
  that removes it.
- Make a rejected entry behave like every other field: report the problem, change nothing.
- Keep the row list cheap to reason about: one rule for "this override has a row".

**Non-Goals:**

- Changing `DisplaySelection.eligible`, the display-mode semantics, or which screens get a panel.
- Redesigning the Style page: no new section, no per-screen picker for screens that get no panel.
- Preserving comments or layout in `settings.json` across a rewrite — canonical rewriting is existing
  behaviour and unrelated to this change.

## Decisions

### 1. The orphan list is computed by exclusion, and titled by cause

`disconnectedOverrides` becomes the set of stored overrides that the per-screen rows do not already
cover, and each entry carries whether its screen is connected:

```swift
private struct OrphanOverride: Identifiable {
    let id: String            // the persistent identifier, used as the row identity
    let display: NotchDisplay? // nil when no connected screen has this identifier
}

private var orphanOverrides: [OrphanOverride] {
    let shown = Set(eligibleDisplays.map(\.persistentID))
    return preferences.displayShapes.keys
        .filter { !shown.contains($0) }
        .sorted()
        .map { id in
            OrphanOverride(id: id, display: displays.first { $0.persistentID == id })
        }
}
```

The row title follows the cause: `display == nil` keeps "Disconnected display" with the UUID, and a
connected-but-unshown screen is titled by its name with a subtitle explaining it gets no panel in the
current display mode. Both keep the same Forget button, so there is one list and one control.

*Why not iterate every connected display as a row (the alternative I considered):* that would give
screens which get no panel a picker whose value has no effect until the mode changes, and it would
grow the section on every multi-screen setup regardless of overrides. It is a defensible reading of
"the Style page should look like the Displays page", but it changes what the page claims rather than
only closing the gap, so it stays out of this fix.

*Why keep the row keyed by identifier rather than by display:* an override belongs to the persistent
identifier, and the same screen can drop in and out of the eligible set between launches. Keying by
identifier keeps the row stable and keeps `Forget` a one-line `displayShapes[id] = nil`.

### 2. Rejected entries keep their previous value

The closure starts from the value it already holds instead of an empty dictionary:

```swift
var shapes = preferences.displayShapes
for (id, entry) in entries {
    ...guard failures...
    if let invalid {
        // Leave whatever this UUID had; report the problem.
        problems.append(invalid)
        continue
    }
    shapes[uuid.uuidString] = Preferences.DisplayShape(style: style, housingGap: housingGap)
}
preferences.displayShapes = shapes
```

Omitting an entry still deletes it, because `shapes` starts from the previous dictionary and the loop
only adds; the assignment writes back exactly the previous set plus the accepted entries. That keeps
the three behaviours the spec already asks for: valid entries apply, the problem is reported, and
deletion by omission still works.

*Why not "leave `displayShapes` entirely unchanged when any entry fails":* it is the reviewer's
second suggestion and it is the worse one — every edit is uploaded as a whole object, so one stale
invalid entry would freeze the section and make deletion impossible. Rejecting per entry matches how
every other field behaves.

*Why not stash the raw rejected text and re-emit it on write:* `snapshot()` is generated from typed
preferences, and re-emitting arbitrary user text would need a parallel "as written" store for one
field. The problem message already names the key and the accepted values; keeping the old override is
the part that protects the user.

### 3. Reachability is tested through the list, not the view

`orphanOverrides` and `eligibleDisplays` both need `NotchDisplay` values, which the tests cannot
construct without real screens. The list logic moves to a small pure helper that takes the stored
identifiers, the connected identifiers and the eligible identifiers, and returns the orphan rows with
a "connected" flag. `StyleSettings` keeps the SwiftUI plumbing and calls it.

*Alternative:* snapshot the Settings page with a fabricated override and diff the render. It would
catch a regression in the row, but it needs a display fixture in the renderer and tells the reader
less than an assertion over the list.

## Risks / Trade-offs

- **Forget on a connected-but-unshown screen looks like it should hide the panel** → the subtitle
  states that the screen gets no panel in the current display mode; the button only removes the
  shape override.
- **A rejected entry keeps an override the user was trying to replace** → the reported problem names
  the key and the accepted values, and the old value is still what `snapshot()` shows, so the file
  and the UI agree.
- **Two row kinds in one list** → both use `SettingsRow` with distinct titles and tints; the list
  stays sorted by identifier so rows do not reorder between launches.
- **`SettingsFile` keeps the old dictionary by reference, not by copy** → `displayShapes` is a value
  type inside a `@Published`, so the closure mutates a copy and assigns once, which keeps the
  debounced write from firing twice.

## Migration Plan

- No stored-format change: existing `look.displays` entries load unchanged, and a previously
  orphaned override becomes visible instead of staying hidden.
- Rollback: revert the two files; the only lasting effect is that a forgotten override stays
  forgotten, which needs no repair.
- Verification: `swift test`, `scripts/build-app.sh`, and a live pass with `behavior.display` set to
  `selected` to confirm the row appears and Forget removes it.
