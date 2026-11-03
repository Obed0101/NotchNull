# Spec Delta

## MODIFIED Requirements

### Requirement: Configuration is exposed and resettable

The global default and the per-display overrides SHALL be readable and writable through `settings.json` and reported per display in status output. Every stored override SHALL be visible and removable from Settings while the app runs, whatever display mode is in effect. An entry that fails validation MUST NOT discard the override already stored for that display. Applying a setup preset or resetting look, size and motion SHALL clear every override.

#### Scenario: Editing settings.json applies live

- **WHEN** a user edits the per-display shape in `settings.json` and saves
- **THEN** the affected display changes presentation without a restart

#### Scenario: Status reports the resolved presentation

- **WHEN** status is queried
- **THEN** each connected display reports its resolved shape and whether a camera housing is assumed

#### Scenario: Reset clears overrides

- **WHEN** the user resets look, size and motion, or applies a setup preset
- **THEN** every per-display override is removed and all displays follow the global shape

#### Scenario: One bad entry does not block the rest

- **WHEN** `settings.json` contains an invalid per-display entry
- **THEN** the problem is reported and the remaining entries still apply

#### Scenario: A rejected entry keeps the override it already had

- **WHEN** a display already has an override and its `look.displays` entry is then edited to an invalid value
- **THEN** the problem is reported, the previously stored override for that display still applies, and the resolved presentation of that display does not change

#### Scenario: An override can be deleted by omitting the entry

- **WHEN** a display's entry is removed from `look.displays` and the file is saved
- **THEN** that display falls back to the global shape and stores no override

#### Scenario: An override for a screen that is not shown is still reachable

- **WHEN** a display has a stored override and the current display mode gives that display no panel
- **THEN** Settings lists that screen's override with the screen named, and offers a control that removes it

#### Scenario: The row says whether the screen is connected

- **WHEN** Settings lists a stored override for a screen that is not currently shown
- **THEN** the row distinguishes a screen that is connected but not shown from one that is not connected
