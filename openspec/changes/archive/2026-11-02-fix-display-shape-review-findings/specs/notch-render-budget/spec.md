# Spec Delta

## ADDED Requirements

### Requirement: Animating body width does not re-lay out spanning content

While a body's width animates, one-row spanning content inside it MUST keep a fixed layout and be clipped by the shrinking body instead of re-measuring per frame. This applies to the island and to a notch body that does not assume a camera housing.

#### Scenario: Island OSD on exit

- **WHEN** the volume or brightness HUD has been shown on an island and the body animates back to closed
- **THEN** the row keeps the width it had while visible, and its bar and labels are clipped rather than re-laid out on every frame

#### Scenario: No-housing notch OSD still fills its body

- **WHEN** the volume or brightness HUD is shown on a display using the notch style without the camera housing
- **THEN** its single row fills the body's width as before

#### Scenario: Rapid key repeats

- **WHEN** the user presses a volume or brightness key several times while the body is animating
- **THEN** only the level fill moves; the row, icon and value keep their positions
