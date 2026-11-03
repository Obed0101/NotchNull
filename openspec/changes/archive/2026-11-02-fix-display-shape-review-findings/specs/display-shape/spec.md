# Spec Delta

## MODIFIED Requirements

### Requirement: Shape resolves per display

The system SHALL resolve the body shape of each display independently, from a global default (Automatic, Notch, or Island) and an optional per-display override (Default, Notch, Island, or Automatic). Default follows the global value; a per-display Automatic follows that display's hardware.

#### Scenario: Default follows the global choice

- **WHEN** the global shape is Notch and a display is set to Default
- **THEN** that display draws the notch body

#### Scenario: An override wins over the global choice

- **WHEN** the global shape is Notch and a display is set to Island
- **THEN** that display floats an island and the other displays keep their own resolution

#### Scenario: Automatic follows the hardware

- **WHEN** the global shape is Automatic and a display is set to Default
- **THEN** a display showing a hardware notch draws the notch body, and a display without one floats an island

#### Scenario: Hardware resolution changes re-resolve Automatic

- **WHEN** a MacBook changes to a resolution that hides the notch while the global shape is Automatic
- **THEN** that display switches to the island presentation without user action

#### Scenario: A display's own Automatic ignores the global choice

- **WHEN** the global shape is Notch and one display is set to Automatic
- **THEN** that display floats an island if it shows no hardware notch, and the other displays still follow the global choice

### Requirement: Configuration is exposed and resettable

The global default and the per-display overrides SHALL be readable and writable through `settings.json` and reported per display in status output. Every value the settings file accepts for an override MUST also be visible and selectable in the per-screen control. Applying a setup preset or resetting look, size and motion SHALL clear every override.

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

#### Scenario: A stored Automatic override is shown as Automatic

- **WHEN** `settings.json` stores `"shape": "auto"` for a connected display
- **THEN** that display's row shows Automatic as the selected value and reports the presentation Automatic resolves to for it

#### Scenario: Every accepted override is selectable

- **WHEN** a user opens the per-screen shape control
- **THEN** Default, Notch, Island and Automatic are all offered, and choosing one stores exactly that value
