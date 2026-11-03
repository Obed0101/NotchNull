# Proposal

## Why

The body has one shape setting for every screen, and the notch style assumes a camera housing is present. On an external display that setting either forces a floating island the user did not ask for, or — when Notch is forced — leaves a 190 pt dead centre where the wings, OSDs and open-panel header refuse to draw, because the layout reserves room for a camera housing that is not there. Users with a mix of screens cannot have "notch on the MacBook, island on the monitor", and single-screen users on a non-notched display cannot get the notch look without the dead middle.

## What Changes

- Add a **per-display shape override** layered over the existing global shape: each connected display resolves to `Default | Notch | Island`, where `Default` follows the global `Automatic | Notch | Island` picker.
- Store overrides by display UUID (`persistentID`), the same identity `behavior.selectedDisplays` already uses, so they survive reconnects and are remembered for disconnected displays.
- Add a per-display **"Assume a camera housing"** flag for screens without a hardware notch that resolve to Notch. When off, activity wings, OSDs and the open-panel header stop reserving the middle and use the full width, while the closed body keeps its black pill.
- Split one layout notion into two: the **silhouette** (notch vs island: top flares, rounded caps, floating offset, satellites) and the **content layout** (two wings vs one row spanning the middle). Island sets both; Notch with the housing assumption sets neither; Notch without it keeps the notch silhouette and spans content.
- Expose the new configuration in `settings.json` as `look.displays`, in `status`/status.json per display, and in Settings › Style › Shape as per-screen rows.
- Presets and "Reset look, size and motion" clear all overrides.

Not breaking: existing `look.shape` keeps its meaning as the default for every screen, and installs with no overrides behave exactly as today.

## Capabilities

### New Capabilities
- `display-shape`: how each display resolves its body shape (global default plus per-display override), how the camera-housing assumption changes content layout without changing the silhouette, persistence by display UUID across reconnects, and the settings/status surface for all of it.

### Modified Capabilities
- None. `notch-render-budget` constrains cost, not geometry choices, and is unaffected.

## Impact

- `Sources/NotchNull/Config/Preferences.swift`: new `displayShapes` map and `DisplayShape` value, factory defaults, reset list.
- `Sources/NotchNull/Core/NotchGeometry.swift` / `DisplaySelection.swift`: per-display identity reaches the model; no new geometry fabrication.
- `Sources/NotchNull/Core/NotchViewModel.swift`: `isIsland` splits into silhouette and content-spanning resolution; `wingGap`, `headerGap`, activity minimum widths and the closed-size derivation follow.
- `Sources/NotchNull/Core/NotchWindowController.swift` / `App/NotchCoordinator.swift`: pass the display UUID when building each controller; report `housingGap` in per-display status.
- `Sources/NotchNull/UI/Activities/MediaActivities.swift` and `UI/Notch/NotchRootView.swift`, `UI/Panel/ExpandedPanel.swift`: the handful of `isIsland` content branches switch to the content-spanning notion.
- `Sources/NotchNull/UI/Settings/CustomizeSettings.swift`: per-screen rows and the housing toggle in the Shape group; `SetupSettings.swift` presets keep writing the global default.
- `Sources/NotchNull/Platform/SettingsFile.swift`: new `look.displays` field with validation; generated settings reference.
- `Sources/NotchNull/App/SnapshotRenderer.swift`: a "notch, no housing" snapshot variant.
- `Tests/NotchNullTests/IslandTests.swift`, `DisplaySelectionTests.swift`: resolution, persistence and layout assertions.
- `docs/multiple-displays.md`: document per-display shape and the housing option.
