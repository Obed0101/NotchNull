# Design

## Context

See `proposal.md` — Why. Three facts from the current implementation shape the approach:

- Shape is decided in one computed property, `NotchViewModel.isIsland`, which reads the global `Preferences.shapeStyle` and `geometry.hasHardwareNotch`. Everything else — body offset, radii, wing gap, header gap, satellites, content branches — derives from that single boolean.
- There is already one model and one window per eligible display, keyed by `CGDirectDisplayID`, and each controller is built from its own `NSScreen`. The model, however, never learns which display it belongs to.
- On a display without a hardware notch, `NotchGeometry` fabricates a 190 × menu-bar-height "virtual notch". In notch style that one width does three jobs: the closed body's width, the wing centre gap, and the open header's centre gap.

Display identity that survives reconnects already exists as `NotchDisplay.persistentID` (the display UUID), used by `behavior.selectedDisplays` and its disconnected-display "Forget" row.

## Goals / Non-Goals

**Goals:**

- Resolve shape per display from a global default plus an optional override, without changing how the global default behaves.
- Make the camera-housing assumption a property of a display's presentation, not of the shape enum, so Automatic keeps one meaning.
- Keep the silhouette decision and the content-layout decision separable, because the new case needs notch silhouette with island-style content.
- Keep the change reversible: an install that never sets an override behaves byte-for-byte as today.

**Non-Goals:**

- Per-display island width, height, top offset, satellites or pill content.
- Per-display panel size, corner scale or activity width scale.
- Per-display `hideNotch` (menu bar painting).
- Changing when a display is eligible for a panel (`displayMode` / `selectedDisplays` stays as it is).

## Decisions

### 1. Overrides are one map, keyed by display UUID, holding both knobs

```swift
struct DisplayShape: Codable, Equatable {
    var style: ShapeStyle      // auto | notch | island, same enum as the global default
    var housingGap: Bool       // default true
}
@Published var displayShapes: [String: DisplayShape]   // persistentID -> override
```

Resolution:

```swift
let chosen  = displayShapes[uuid]?.style ?? preferences.shapeStyle
let island  = chosen == .island || (chosen == .auto && !geometry.hasHardwareNotch)
let housing = geometry.hasHardwareNotch || (displayShapes[uuid]?.housingGap ?? true)
let spans   = island || (chosen == .notch && !housing)
```

"Default" in the UI is the absence of an entry, not a fourth enum case. Setting a row back to Default removes the entry, so the housing flag and the style are forgotten together and cannot drift.

*Alternatives:* a fourth `ShapeStyle` case (`notchNoGap`) was rejected — it doubles the state space of Automatic and forces every `switch` to grow. A separate `[String: Bool]` map for the housing flag was rejected — two maps can disagree about whether a display is overridden at all.

### 2. Silhouette and content layout become two notions

| Derived value | Follows |
|---|---|
| `bodyTop`, `topRadius`, `capRadius`, `bottomRadius`, banner header height, row insets, satellites, `keepTopBlack` | silhouette (`island`) |
| `wingGap`, `headerGap`, activity minimum width, OSD/header content layout | content spanning (`spans`) |

Only four view/size call sites currently branch on `isIsland` for *content* (`LevelActivity`, the panel's top padding, and the closed-face branch). The closed-face branch stays on the silhouette — a notch-style closed body is a black pill either way.

`wingGap` for spanning content uses the existing `Theme.Size.islandWingGap` (16), so split activities such as music do not collide, and `headerGap` becomes 8. The activity body keeps the footprint it has with the housing assumed (closed width plus both wings); only the centre gap and the content layout change, so a volume HUD stays the same width while its bar runs through the middle and music keeps its artwork and bars at the same edges.

*Alternative:* treat "no housing" as the island content path wholesale (including floating offset and rounded caps) was rejected — the user chose the notch look on such screens; only the middle should open up.

### 3. The closed body is untouched

`closedSize` keeps using `notchSize.width` (+ `closedExtraWidth`). On a display without a hardware notch that is already the 190 pt virtual notch, so the idle body, its hover target and its tap behaviour need no special case. This is why the "min width" from the discussion is not a new constant.

### 4. Hardware notch always wins for the housing

`housingGap` is forced true when `geometry.hasHardwareNotch`. A stored `false` (for example from a MacBook running a resolution that hides the notch) is ignored the moment the notch is present again, so content can never be drawn over the camera. The setting is not shown for such displays.

### 5. Display identity reaches the model through the controller

`NotchWindowController` already receives its `NSScreen`; it derives `persistentID` once and passes it into `NotchViewModel`. The model stores it and exposes the resolved shape. Models rebuilt after a geometry change receive the same UUID, so overrides survive resolution changes. `SnapshotRenderer` builds models without a display, so the initialiser parameter defaults to an empty identifier that matches no override.

All resolution is computed from `@Published` preferences that the model already observes; no extra notification plumbing is needed for live updates.

### 6. settings.json gets a nested per-display object

```json
"look": {
  "shape": "auto",
  "displays": {
    "37D8832A-2D66-02CA-B9F7-8F30A301B230": { "shape": "notch", "housingGap": false }
  }
}
```

`look.shape` keeps its current meaning and value. The new field validates each entry independently: an unknown display UUID is accepted (it may be disconnected), an invalid shape string or non-boolean housing flag is reported for that entry only, and the rest still apply. `SettingsFile` treats unknown keys as errors, so the field must ship in the same release as the feature.

### 7. UI: per-screen rows in Style › Shape

The global segmented picker stays at the top, now labelled as the default. Under it:

```
Shape            [ Automatic | Notch | Island ]
Screens
  MacBook Pro                        [ Default v ]
  HP 23er                            [ Island  v ]
  [ ] Assume a camera housing                    <- only for a no-notch screen set to Notch
```

- Each row is a menu picker: Default, Notch, Island.
- The housing checkbox is indented under the affected row and only exists when that display has no hardware notch and resolves to Notch (through its own override or the global default, never through Automatic).
- The screen list appears when there are at least two eligible displays, at least one override, or an eligible display without a hardware notch (so the housing option is reachable on a single external screen). A single notched screen sees only the global picker.
- Disconnected overrides appear below as a "Disconnected display" row with Forget, mirroring `selectedDisplays`.
- Presets in Setup and "Reset look, size and motion" clear the map, so a preset applies to every screen.

### 8. Status and settings reference follow automatically

`NotchCoordinator.windowStatus` already reports `shape` per display; add `housingGap`. `SettingsFile` regenerates the settings reference from the field table, so the new key documents itself.

### 9. A presentation change re-derives the shown activity

Whether music belongs in the pill is decided when the activity event arrives: the island's left satellite already shows the player. Changing a display to the island after that left a stale music wing until relaunch. The model keeps the last kind from the activity centre and re-derives it whenever the shape, a display's override or the satellites change, then re-applies the phase.

*Alternative:* restarting the model on a shape change was rejected — it would drop the open panel, the pointer state and the current tab for a purely presentational change.

## Risks / Trade-offs

- **Content branches keyed on `isIsland` are missed** → Enumerate every `isIsland` use and classify each as silhouette or content during implementation; add a snapshot for "notch, no housing" so a wrong classification is visible.
- **A geometry change rebuilds the model and could drop the override** → The override lives in preferences, not the model; the rebuild test asserts the override still resolves after a simulated resolution change.
- **An older build reads a settings.json containing `look.displays`** → It reports an unknown setting and leaves the rest alone; no data loss, and the file is rewritten from the running build's schema only on change. Acceptable for a pre-1.0 settings file that is already backed up wholesale.
- **Display UUID instability for Sidecar / third-party docks** → Same exposure `selectedDisplays` already has; if the UUID changes, the override stops matching rather than matching the wrong display. Better than keying by display number.
- **Housing off could make a HUD wider than the canvas** → Body size is already clamped to `Theme.Size.canvas`; the spanning body is narrower than the current notch body, so this cannot regress.
- **Two displays with identical names in the UI** → Rows show resolution alongside the name, and behaviour is keyed by UUID, not name.

## Migration Plan

No data migration. On update, `displayShapes` starts empty, every display resolves through the existing `look.shape`, and behaviour is unchanged. Rollback is a downgrade: overrides are ignored by older builds and reported as an unknown setting, while `look.shape` still applies.

## Open Questions

- Label wording: "Assume a camera housing" versus e.g. "Reserve space for the camera housing". Affects copy only, not behaviour.
