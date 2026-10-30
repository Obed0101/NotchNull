# Tasks

## 1. Preference model and resolution

- [x] 1.1 Add `DisplayShape` (`style`, `housingGap`) to `Preferences` with a `[String: DisplayShape]` published map, register it in the factory defaults and add it to the `resetCustomization` key list; verify with a `swift test` case that a fresh `Preferences` has an empty map and that reset empties it.
- [x] 1.2 Add a pure resolution helper (global default + optional override + `hasHardwareNotch`) returning the chosen style and whether the housing is assumed, including the rule that a hardware notch forces the housing on; verify with unit tests covering Default, each explicit override, Automatic with and without a hardware notch, and a stored `housingGap: false` on a notched display.

## 2. Display identity reaches the model

- [x] 2.1 Derive the display's persistent identifier once in `NotchWindowController` and pass it into `NotchViewModel` (defaulting to an identifier that matches no override for snapshot rendering); verify that a model built for a screen resolves that screen's override and a model built without one resolves the global default.
- [x] 2.2 Confirm the identity survives the geometry rebuild path (`NotchCoordinator.rebuild` / `replaceFailedWindow`); verify with a test that simulates a resolution change and asserts the override still applies afterwards.

## 3. Split silhouette from content layout

- [x] 3.1 Replace `isIsland`'s single boolean with two derived notions in `NotchViewModel`: silhouette (island) and content spanning (`island`, or notch without the assumed housing), leaving the existing silhouette-derived values — `bodyTop`, radii, banner heights, insets, satellites, `keepTopBlack` — on the silhouette; verify existing `IslandTests` layout assertions still pass unchanged.
- [x] 3.2 Make `wingGap` (16 when spanning, otherwise the closed width) and `headerGap` (8 when spanning, otherwise notch width + 8) follow content spanning, and switch the activity minimum-width and closed-size derivation to the spanning rule; verify new tests assert that with the housing off `closedSize` is unchanged while `wingGap` and `headerGap` shrink, and that a hardware-notched display is unaffected.
- [x] 3.3 Classify every remaining `isIsland` use in views as silhouette or content, and move only the content ones (`LevelActivity`'s spanning row, the open panel's top padding) onto the spanning notion; verify the volume HUD and music HUD tests report the expected body widths on a no-housing display.
- [x] 3.4 Re-derive the shown activity when a display's shape, override or satellites change, so switching to Island clears a music wing without a relaunch; verify a test drives notch → island → notch with music playing and gets activity → closed → activity.
- [x] 3.5 Keep an activity's body width equal to the assumed-housing footprint when the housing is off, letting the OSD row fill it; verify parity assertions for volume and music and the paired `nohousing`/`housing-on` snapshots.

## 4. Snapshots

- [x] 4.1 Add a "notch, no housing" geometry variant to `SnapshotRenderer` and render the closed body, volume, music, a banner and the open panel into the snapshot set; verify the generated PNGs show a flush top edge with concave flares, no satellites, and a volume bar crossing the centre.

## 5. Settings UI

- [x] 5.1 Add the per-screen rows and the conditional "Assume a camera housing" control to Style › Shape, with Default meaning no stored entry and the row list appearing for two or more eligible displays or any existing override; verify each row changes only its own display and that choosing Default removes the entry.
- [x] 5.2 Show disconnected overrides with a Forget action and update the Shape group footer to explain the default/override layering; verify a saved override for an unplugged display appears as disconnected and Forget removes it.
- [x] 5.3 Keep Setup presets writing only the global default and clearing the map; verify applying each preset leaves every display on Default and that "Reset look, size and motion" also clears overrides.

## 6. Settings file, status and docs

- [x] 6.1 Add the nested `look.displays` field to `SettingsFile` with per-entry validation that rejects a bad shape or housing flag without dropping the other entries; verify by applying a valid file, a file with one bad entry, and an unknown display UUID, and confirming the reported problems and applied result.
- [x] 6.2 Report the assumed housing alongside the resolved shape for each connected display in `NotchCoordinator.windowStatus` and the generated settings reference; verify `notchnull status` on a multi-display setup shows both fields per display.
- [x] 6.3 Document per-display shape, the housing option and the disconnect behaviour in `docs/multiple-displays.md`; verify the documented settings.json example parses and applies as written.

## 7. Integration verification

- [x] 7.1 Run `swift test` and `scripts/build-app.sh`, then open Settings and confirm on a two-display setup that each screen follows its own row, that the housing toggle appears only on the no-notch screen set to Notch, and that turning it off lets the volume bar run through the middle while the closed pill stays.

## Workflow follow-up

- Archive the change once the built app and snapshot review are accepted.
