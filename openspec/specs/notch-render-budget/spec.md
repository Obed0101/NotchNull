# notch-render-budget Specification

## Purpose

Keeps the notch's live presentation cheap: time-driven labels redraw only when their value changes, the body geometry stays stable, and windows that are hidden or duplicated do not keep animating.

## Requirements

### Requirement: Time-driven labels update once per change

A notch label whose value changes on a one-second cadence SHALL redraw only when the displayed value changes. It MUST NOT run a rolling, morphing, or spring animation that lasts until the next change.

#### Scenario: Agent elapsed time

- **WHEN** a running agent session shows elapsed time in the collapsed notch
- **THEN** the label changes once per second and no animation continues between ticks

#### Scenario: Timer countdown

- **WHEN** the timer activity is shown in the notch
- **THEN** each second replaces the previous value in one step instead of continuously rolling digits

#### Scenario: Unchanged value

- **WHEN** the displayed time has not changed and nothing else in the notch is animating
- **THEN** the notch does not redraw

### Requirement: Time labels keep a stable slot

A time label SHALL occupy a reserved area whose size does not depend on its current digits, so crossing a digit or unit boundary does not resize or move the notch.

#### Scenario: Digit growth

- **WHEN** an elapsed label moves from `9s` to `10s` or from `59s` to `1m 0s`
- **THEN** the notch body keeps its width, height, and position, with no layout animation

#### Scenario: Unit growth

- **WHEN** a countdown crosses from minutes to hours
- **THEN** the reserved time area is sized for the longest expected value and the body still does not move

### Requirement: Label updates do not repaint static chrome

Updating a time label SHALL cause at most one redraw of the label and its immediate container. The body fill, emission edge, glow, and shadow MUST NOT be re-rendered because a label changed.

#### Scenario: Body chrome is untouched

- **WHEN** an elapsed or countdown label advances by one second
- **THEN** the body fill, edge glow, and shadow pixels are produced from the same static content as before the update

#### Scenario: One redraw per tick

- **WHEN** one visible notch window advances a single time label
- **THEN** that window performs at most one redraw for the change

### Requirement: Only genuinely per-frame content animates

Content that changes every frame MAY animate continuously only while it is visible and active. Static labels, settled indicators, and activities that are not shown MUST NOT drive continuous animation.

#### Scenario: Music bars

- **WHEN** music is playing and the music activity is visible
- **THEN** the bars animate at their normal cadence, and they stop when playback pauses or the activity is hidden

#### Scenario: Needs-you glow

- **WHEN** the needs-you activity is answered or replaced
- **THEN** its travelling glow stops instead of continuing off screen

#### Scenario: Settled notch

- **WHEN** the only visible activity is a one-second time label
- **THEN** no other repeating animation runs in that window

### Requirement: Hidden windows do no animation work

A notch window that is not actually on screen MUST pause its timelines and repeating animations. This covers a window hidden for fullscreen, ordered out, on a sleeping display, or on a Space it does not inhabit.

#### Scenario: Fullscreen hides the notch

- **WHEN** a fullscreen app covers the display and the notch is hidden
- **THEN** no notch animation or timeline advances until the notch returns

#### Scenario: Display sleeps

- **WHEN** the display is asleep or the window is off screen
- **THEN** the window performs no animation work, and it resumes when the screen wakes

#### Scenario: Restored visibility

- **WHEN** the notch becomes visible again
- **THEN** labels and animations resume from the current state without replaying missed ticks

### Requirement: Visible duplicate windows share one update

When the same activity appears in notch windows on several displays, each visible window SHALL update at most once for a single value change and MUST NOT run an independent continuous animation for time-driven content.

#### Scenario: Two displays show the same agent activity

- **WHEN** two displays both show a running agent's elapsed time
- **THEN** each window advances once per second, with no per-frame redraw between ticks

#### Scenario: One display hidden

- **WHEN** one of those displays is asleep or its window is off screen
- **THEN** only the visible window updates, and the hidden one does no work

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
