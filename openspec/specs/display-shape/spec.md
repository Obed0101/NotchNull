# display-shape Specification

## Purpose

Lets every connected display choose how the notch body is presented, and lets the notch look be used on screens with no camera housing without leaving a dead centre.

## Requirements

### Requirement: Shape resolves per display

The system SHALL resolve the body shape of each display independently, from a global default (Automatic, Notch, or Island) and an optional per-display override (Default, Notch, or Island). Default means the display follows the global value.

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

### Requirement: Overrides persist by display identity

Per-display overrides SHALL be stored against the display's persistent identifier rather than its display number, so they survive reconnects, reordering, restarts and wake from sleep.

#### Scenario: Reconnect keeps the override

- **WHEN** a display with an Island override is unplugged and plugged back in
- **THEN** it is still presented as an island

#### Scenario: A disconnected override is retained and forgettable

- **WHEN** a display with an override is not connected
- **THEN** the override is kept, shown as a disconnected display, and can be forgotten by the user

### Requirement: Notch style can omit the camera housing

A display without a hardware notch that resolves to the notch style SHALL offer an "assume a camera housing" setting, enabled by default. When it is disabled, activity wings, OSDs and the open panel's header SHALL use the width otherwise reserved for the housing.

#### Scenario: Housing assumed keeps the middle clear

- **WHEN** a display without a hardware notch uses the notch style with the housing assumption enabled
- **THEN** the volume HUD keeps its content on either side of a reserved centre and the open panel header keeps its centre gap

#### Scenario: Housing omitted lets content span the middle

- **WHEN** the same display has the housing assumption disabled
- **THEN** the volume HUD presents as one row whose bar crosses the centre, and the open panel header uses the full width

### Requirement: The idle body keeps a notch pill

When the housing assumption is disabled, the closed body SHALL still draw a notch-width black body at the top centre, and that body SHALL remain a hover and click target for opening the panel.

#### Scenario: Idle presentation is unchanged

- **WHEN** nothing is playing or happening and the housing assumption is disabled
- **THEN** the display shows the same closed black body it shows with the assumption enabled

#### Scenario: The idle body still opens the panel

- **WHEN** the pointer enters the closed body with the housing assumption disabled
- **THEN** the panel opens as it does for any other closed body

### Requirement: Housing assumption is never offered against a hardware notch

The housing setting MUST NOT be offered or applied on a display whose current resolution shows a hardware notch, and no content may be drawn over the camera housing.

#### Scenario: Notched display has no toggle

- **WHEN** a display shows a hardware notch
- **THEN** the housing setting is absent for it and its content keeps clear of the housing

#### Scenario: Stored preference cannot break a notched display

- **WHEN** a display that previously had no notch gains one at a new resolution
- **THEN** the housing is treated as present regardless of the stored setting

### Requirement: Omitting the housing does not change the silhouette

With the housing assumption disabled, the body SHALL keep the notch presentation: flush to the top edge, concave top flares, no rounded top caps, no floating offset below the menu bar, and no island satellites.

#### Scenario: Open panel keeps the notch outline

- **WHEN** the open panel appears on a display with the housing assumption disabled
- **THEN** it is flush with the top edge with concave top flares and no island satellites

### Requirement: Configuration is exposed and resettable

The global default and the per-display overrides SHALL be readable and writable through `settings.json` and reported per display in status output. Applying a setup preset or resetting look, size and motion SHALL clear every override.

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
