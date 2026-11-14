# Spec Delta

## MODIFIED Requirements

### Requirement: Hidden windows do no animation work

A notch window whose body is not visible MUST pause its timelines and repeating animations. This covers a body concealed for fullscreen, an ordered-out window, a sleeping display, or a Space it does not inhabit. A panel kept registered for a concealed body MUST NOT continue animation work.

#### Scenario: Fullscreen hides the notch

- **WHEN** a fullscreen app covers the display and the notch is hidden
- **THEN** no notch animation or timeline advances until the notch returns

#### Scenario: Concealed body in a registered window

- **WHEN** the panel window remains registered while its body is concealed for fullscreen
- **THEN** the clock, stats and repeating animations still do no work

#### Scenario: Display sleeps

- **WHEN** the display is asleep or the window is off screen
- **THEN** the window performs no animation work, and it resumes when the screen wakes

#### Scenario: Restored visibility

- **WHEN** the notch becomes visible again
- **THEN** labels and animations resume from the current state without replaying missed ticks
