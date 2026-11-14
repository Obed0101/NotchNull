# fullscreen-concealment Specification

## Purpose

Keeps the notch out of the way on displays covered by a fullscreen app while keeping it ready to slide back for attention, alerts and deliberate access.

## Requirements

### Requirement: Fullscreen conceals each display independently

When the fullscreen setting is enabled, the system SHALL conceal the notch on each display covered by a fullscreen app and MUST leave the notch of every other display unchanged. Concealment MUST end when that display is no longer covered by a fullscreen app.

#### Scenario: One display is fullscreen

- **WHEN** a fullscreen app covers display A and display B has no fullscreen app
- **THEN** display A conceals its notch and display B keeps its notch visible

#### Scenario: Fullscreen ends

- **WHEN** the fullscreen app on display A closes or leaves fullscreen
- **THEN** display A's notch is revealed again

#### Scenario: Setting is off

- **WHEN** the fullscreen setting is disabled and a fullscreen app covers a display
- **THEN** the notch stays visible on that display

### Requirement: Concealment is a reversible slide

Concealment SHALL move the notch body and any island satellites above the display edge with an animation, and reveal SHALL slide them back to their normal position. The notch MUST remain able to reveal without recreating its panel, and concealment MUST NOT permanently close an open presentation.

#### Scenario: Fullscreen begins

- **WHEN** a fullscreen app starts covering the display and the notch is idle
- **THEN** the body slides above the top edge instead of disappearing without motion

#### Scenario: Fullscreen ends

- **WHEN** the fullscreen app stops covering the display
- **THEN** the body slides back to its normal position

#### Scenario: Reveal from concealment

- **WHEN** a concealed notch receives a reveal trigger
- **THEN** the body slides down from the top edge and can be interacted with

#### Scenario: Window is not torn down

- **WHEN** the notch is concealed and revealed repeatedly
- **THEN** the panel remains the same window and no visible flash or recreation occurs

### Requirement: Attention activities reveal the notch

While concealed, the notch SHALL reveal when the most urgent active activity needs attention, asks for an action or reports a result, even if an ambient activity has higher normal priority. This includes needs-you, agent-finished, usage-warning, timer-finished, low-battery, download-keep, download-done, download-trashed, screenshot and transient custom activities.

#### Scenario: Agent needs you

- **WHEN** an agent session starts waiting for the user while the notch is concealed
- **THEN** the notch reveals and shows the needs-you banner

#### Scenario: Agent finishes

- **WHEN** a running agent finishes a turn while the notch is concealed
- **THEN** the notch reveals and shows the finished activity

#### Scenario: Timer finishes

- **WHEN** a timer reaches zero while the notch is concealed
- **THEN** the notch reveals and shows the timer-finished activity

#### Scenario: Download asks to be kept

- **WHEN** a new download needs a keep decision while the notch is concealed
- **THEN** the notch reveals and shows the download-keep prompt

#### Scenario: Download completes or is trashed

- **WHEN** a download completes or is moved to the Trash while the notch is concealed
- **THEN** the notch reveals and shows the corresponding result

#### Scenario: Screenshot is taken

- **WHEN** a screenshot is captured while the notch is concealed
- **THEN** the notch reveals and shows the screenshot activity

#### Scenario: Transient custom activity

- **WHEN** a custom activity with a finite duration is posted while the notch is concealed
- **THEN** the notch reveals for that activity

### Requirement: A revealed activity returns to concealment

When a reveal caused by an activity ends, the notch SHALL conceal again after no attention activity remains active, unless the pointer is inside the notch or the panel is open. If the pointer is inside, concealment MUST wait until the pointer leaves and the close delay elapses.

#### Scenario: Activity expires

- **WHEN** a revealed transient activity expires, no other attention activity remains and the pointer is outside
- **THEN** the notch conceals again

#### Scenario: Pointer is inside

- **WHEN** a revealed transient activity expires while the pointer is over the notch
- **THEN** the notch stays revealed until the pointer leaves and the close delay elapses

#### Scenario: Panel is open

- **WHEN** an activity ends while the panel is open
- **THEN** the panel stays open and the notch does not conceal

### Requirement: Ambient and persistent state stays concealed

While concealed, the notch MUST NOT reveal automatically for ambient or persistent state, including running agents, an active timer, an upcoming meeting, download progress, expiring downloads, persistent custom activities, music, volume, brightness, charging, tray additions, the launch hello and device connections. A deliberate hover or open MAY still show that state.

#### Scenario: Music plays in fullscreen

- **WHEN** music is playing and the notch is concealed for fullscreen
- **THEN** the notch stays concealed until the user hovers or opens it

#### Scenario: An agent keeps running

- **WHEN** an agent is running but does not need attention and the notch is concealed
- **THEN** the notch stays concealed

#### Scenario: Download progresses

- **WHEN** a download is in progress and the notch is concealed
- **THEN** the notch stays concealed

#### Scenario: Volume key while all displays are fullscreen

- **WHEN** the user presses a volume or brightness key while every display is in fullscreen concealment
- **THEN** the notch does not reveal for the level change

#### Scenario: Hover shows persistent state

- **WHEN** the user hovers the wake strip while a persistent ambient activity is current
- **THEN** the revealed body shows that activity

### Requirement: The wake strip reveals and opens on hover

While concealed, the system SHALL expose a top-centre wake strip. Hovering it SHALL slide the body down and open the panel after a deliberate delay of at least 100 ms. Clicking it SHALL open the panel. Moving the pointer away SHALL close the panel and conceal the notch after the close delay. Hover-open MUST apply even when the general open trigger is click.

#### Scenario: Hover opens

- **WHEN** the pointer enters the wake strip and remains there for the delay
- **THEN** the notch slides down and the panel opens

#### Scenario: Click opens

- **WHEN** the user clicks the wake strip before the hover delay elapses
- **THEN** the notch slides down and the panel opens

#### Scenario: Pointer leaves

- **WHEN** the pointer leaves the revealed notch while no attention activity is current
- **THEN** the panel closes and the notch conceals after the close delay

#### Scenario: Pointer outside the wake strip

- **WHEN** the pointer moves near the top edge but outside the wake strip
- **THEN** the notch stays concealed

#### Scenario: General trigger is click

- **WHEN** the general open trigger is click and the pointer hovers the wake strip
- **THEN** the notch still slides down and the panel opens after the delay

### Requirement: Explicit open reveals a concealed notch

A keyboard shortcut, local API request or menu action that opens the notch SHALL reveal the concealed notch and open the panel on the targeted display. Concealed displays MUST remain eligible for explicit open targeting.

#### Scenario: Clipboard shortcut

- **WHEN** the user triggers the Clipboard shortcut while the targeted display is concealed
- **THEN** the notch reveals and opens on the Clipboard tab

#### Scenario: API open

- **WHEN** the local API asks to open a tab on a concealed display
- **THEN** the display reveals and opens that tab

#### Scenario: Explicit open without hover

- **WHEN** the user explicitly opens the notch without first hovering the wake strip
- **THEN** the notch reveals and opens directly

### Requirement: Concealment adapts to notch and island

The slide SHALL work for the notch and island presentations. The notch body MUST return flush to the top edge, and an island MUST return to its configured top gap. Island satellites MUST move with the body, and a concealed notch MUST leave no interactive region except the wake strip.

#### Scenario: Notch presentation

- **WHEN** a display using the notch presentation conceals and reveals in fullscreen
- **THEN** the body leaves the top edge and returns flush to it

#### Scenario: Island presentation

- **WHEN** a display using the island presentation conceals and reveals in fullscreen
- **THEN** the pill and its satellites leave the top edge and return at the configured island top gap

#### Scenario: Forced island on a notched display

- **WHEN** a display with a camera housing uses the island presentation in fullscreen
- **THEN** the pill leaves from below the housing and returns below it

#### Scenario: Concealed body is not clickable

- **WHEN** the body is concealed and the pointer is outside the wake strip
- **THEN** clicks pass through to the fullscreen app

### Requirement: Concealed content is inert and hidden from accessibility

While concealed, the notch body MUST NOT receive clicks, drags, scrolls or keyboard focus outside the wake strip. Its content SHALL be hidden from accessibility. When revealed, the content SHALL become interactive and accessible again.

#### Scenario: Click passes through

- **WHEN** the notch is concealed and the user clicks outside the wake strip
- **THEN** the fullscreen app receives the click

#### Scenario: VoiceOver

- **WHEN** the notch is concealed and VoiceOver inspects the screen
- **THEN** it does not find the concealed notch content

#### Scenario: Revealed content

- **WHEN** the notch is revealed
- **THEN** its content is interactive and accessible again

### Requirement: Fullscreen detection survives a temporary menu bar

On a display with a camera housing, a temporarily visible menu bar MUST NOT be treated as leaving fullscreen while a fullscreen app still covers the display. The system SHALL leave fullscreen only when the fullscreen window or Space actually changes, or after the menu bar remains visible beyond a short grace period.

#### Scenario: Pointer reveals the menu bar

- **WHEN** the pointer reaches the top edge, the menu bar appears, and the fullscreen app still covers the display
- **THEN** the display stays in fullscreen mode and the notch does not spuriously conceal or reveal

#### Scenario: Zoomed window under a persistent menu bar

- **WHEN** a normal window is merely zoomed under a menu bar that remains visible
- **THEN** the display is not treated as fullscreen

#### Scenario: Real fullscreen exit

- **WHEN** the fullscreen window closes or the Space changes
- **THEN** the display leaves fullscreen mode

### Requirement: System capture overlays are not fullscreen apps

A full-screen system capture UI (the screenshot toolbar and its selection overlay) SHALL NOT be treated as a fullscreen app. Opening or closing it MUST NOT conceal or reveal the notch or change its fullscreen state.

#### Scenario: Screenshot toolbar opens

- **WHEN** the system screenshot UI is open over a display
- **THEN** the notch stays in its current reveal state

#### Scenario: Screenshot is completed or cancelled

- **WHEN** the screenshot UI closes
- **THEN** the notch does not slide or change fullscreen state because of the capture UI

### Requirement: Status and settings expose concealment

Status output SHALL report, per display, whether fullscreen concealment is active, whether the body is currently concealed, and why it is revealed. It MUST keep `fullscreenHidden` as the fullscreen-mode flag for compatibility. Settings SHALL provide a way to disable automatic alert reveals while keeping hover and explicit open.

#### Scenario: Concealed status

- **WHEN** a display is in fullscreen concealment and no reveal is active
- **THEN** status reports fullscreen active, concealed true and no reveal reason

#### Scenario: Revealed status

- **WHEN** an activity or the pointer reveals the notch
- **THEN** status reports concealed false and the reveal reason

#### Scenario: Alerts disabled

- **WHEN** automatic alert reveals are disabled and an attention activity becomes current
- **THEN** the notch stays concealed until the user hovers or opens it

#### Scenario: Setting is off

- **WHEN** fullscreen concealment is disabled
- **THEN** status reports no fullscreen concealment for the display

### Requirement: Media-key HUD handoff follows fullscreen mode

When every display is in fullscreen concealment mode, volume and brightness keys SHALL continue to use the system HUD. A temporary reveal for another activity MUST NOT change that handoff. When at least one display is not in fullscreen mode, NotchNull SHALL keep its normal HUD behavior.

#### Scenario: All displays fullscreen

- **WHEN** every display is in fullscreen concealment and the user changes volume
- **THEN** macOS shows its own HUD and the notch stays concealed

#### Scenario: Alert peek while all fullscreen

- **WHEN** an attention activity reveals one notch while every display is in fullscreen concealment
- **THEN** volume and brightness keys still use the system HUD

#### Scenario: One display visible

- **WHEN** at least one display is not in fullscreen concealment and the user changes volume
- **THEN** NotchNull keeps its normal HUD behavior

### Requirement: Reduce Motion replaces the slide with a fade

When Reduce Motion is enabled, concealment and reveal SHALL use a short fade instead of a spatial slide. The notch MUST NOT move above the display edge in that mode, and concealed content MUST remain inert.

#### Scenario: Reduce Motion conceal

- **WHEN** Reduce Motion is enabled and the notch conceals for fullscreen
- **THEN** the body fades out without moving above the display edge

#### Scenario: Reduce Motion reveal

- **WHEN** Reduce Motion is enabled and the notch reveals
- **THEN** the body fades in without sliding
