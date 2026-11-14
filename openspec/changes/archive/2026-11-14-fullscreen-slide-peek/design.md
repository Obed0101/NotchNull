# Design

## Context

See `proposal.md` for motivation and `specs/fullscreen-concealment/spec.md` for the behavior contract.

The current fullscreen path is a hard hide. `FullscreenWatcher` publishes a per-display set, `NotchCoordinator.applyFullscreenHiding()` forwards it to each `NotchWindowController`, and `setFullscreenHidden(true)` closes the model, calls `panel.orderOut(nil)`, and pauses sampling. The panel is a fixed transparent canvas pinned to the top centre of a display; the SwiftUI body is top-aligned at `bodyTop` and morphs between notch and island. Because the window is either fully ordered in or fully ordered out, there is no state in which it can accept a hover or reveal an activity while remaining out of the way.

Constraints that shape the approach:

- The body is drawn in a fixed window, so a slide is a SwiftUI offset, not a window resize.
- The notch and island presentations have different `bodyTop` and closed sizes; the slide must work for both.
- Island satellites are separate views in the same canvas and must move with the body.
- `NotchWindowController` already pauses clock/stats and animations through `model.isWindowVisible`; the new state must feed that flag.
- Fullscreen detection uses the public window list. On a display with a camera housing, the detector currently treats a visible menu bar as evidence that the display is not fullscreen.
- `ActivityCenter` exposes one winner, `current`. A persistent custom activity can outrank a transient agent event; fullscreen reveal selection must not be blocked by that winner.
- `NotchStatus` is a public read surface, and `fullscreenHidden` is already documented.

## Goals / Non-Goals

**Goals:**

- Keep the panel window registered while the notch is out of the way, so reveal is immediate and reliable.
- Conceal and reveal per display, with a slide that works for notch and island.
- Reveal for the attention/action/feedback activities selected in the proposal; keep ambient and persistent state hidden.
- Provide a top-centre wake strip whose hover opens the panel, with click and explicit open as alternatives.
- Preserve the render budget guarantee while concealed.
- Keep status, settings, media-key handoff, accessibility and Reduce Motion coherent with the new state.

**Non-Goals:**

- A media-only fullscreen mode. Scope is every fullscreen app for this change.
- Reading or mirroring macOS Notification Center notifications.
- Private window-server APIs or a new dependency.
- Redesigning the open panel, tab layout or activity artwork.
- Changing normal (non-fullscreen) hover, click or shortcut behavior.
- Adding a second window or a separate alert banner.

## Decisions

### 1. Add a presentation layer, not a new phase

`NotchViewModel.Phase` continues to describe content: closed, activity, open or drop. Fullscreen concealment becomes an independent, published presentation state on the model:

```text
isFullscreenActive  = display is covered + setting is on
activityReveals     = current fullscreen-reveal activity exists and alerts are enabled
isConcealed         = isFullscreenActive && !isOpen && !isPointerInside && !activityReveals
```

The window controller sets `isFullscreenActive`; the model derives `isConcealed`. This keeps every existing phase transition intact and makes hover, alert reveal and open behave like three reasons not to conceal.

**Alternative considered:** a `.hidden` phase. Rejected because every content switch would need to know about it, and two independent booleans (content and presentation) would be conflated.

### 2. Slide the whole root, not the window or the body height

`NotchRootView` applies one offset to the ZStack that contains the body and the island satellites:

```text
concealOffset = isConcealed ? -(bodyTop + shapeSize.height + slideMargin) : 0
```

`slideMargin` (proposed 40 pt) clears the body shadow and emission edge. The window canvas top is the display top, so the offset moves the content out of the visible canvas and the window clips it. The same formula works for a notch (`bodyTop = 0`) and an island (bodyTop is the configured gap, or the housing height plus gap on a notched display). Satellites move because they share the root transform.

**Alternatives considered:**

- Move and animate the `NSPanel` frame. Rejected: AppKit frame animation is harder to coordinate with SwiftUI size changes, can be constrained near screen edges, and complicates multi-display recovery.
- Collapse the body height like BoringNotch. Rejected: it is a shrink, not the requested slide, and it would distort the island.
- A mask/clip reveal. Rejected: less physical and does not move the satellites as one body.

### 3. Keep the panel registered and change the visibility contract

`setFullscreenHidden` becomes a mode setter (`setFullscreenActive`) and no longer calls `panel.orderOut(nil)`. The panel remains ordered in, transparent, and above the fullscreen app. `refreshSampling` uses `!isConcealed` instead of the old `!fullscreenHidden` flag. `windowServerVisibility`, frame reconciliation and window replacement continue to run while fullscreen is active, because the panel is still needed for reveal.

`isWindowVisible` is set to false as soon as concealment begins; that pauses clock, stats, chase outline and agent-mark timelines. The slide animation itself is a SwiftUI view animation and does not depend on `isWindowVisible`.

**Alternative considered:** keep the hard hide and create a new window on reveal. Rejected: slow, prone to focus/registration flashes, and impossible to hover.

### 4. Wake strip and interaction model

While concealed, `interactiveRect` returns a wake strip instead of the body:

```text
wakeStrip = CGRect(
    x: screen.midX - closedSize.width / 2,
    y: screen.maxY - wakeHeight,
    width: closedSize.width,
    height: wakeHeight          // 8 pt
)
```

The strip is the only hit target while concealed. `satelliteScreenRects` is empty and the body is not clickable. `PointerTracker` is global, so hover works even while the panel is click-through. `refreshHitTesting` sets `ignoresMouseEvents = false` for the wake strip so a click is captured; outside the strip the window stays click-through and the fullscreen app receives the click.

Hovering the strip sets `pointerInside`, which makes `isConcealed` false: the body slides down and the existing open scheduling runs with a fullscreen delay of `max(Motion.hoverOpenDelay, 0.12)`. This deliberately overrides `openTrigger = click` in fullscreen, as requested. A click on the strip opens immediately. Moving away closes after `Motion.hoverCloseDelay` and conceals when no reveal activity remains.

The wake strip is a transparent SwiftUI view rendered only when concealed. It carries the tap gesture, is excluded from accessibility, and is not the body's normal content shape. This avoids leaving offscreen body content interactive.

**Alternative considered:** let hover only reveal the closed body. Rejected by the user; hover must open.

### 5. Fullscreen reveal selection is separate from the ActivityCenter winner

`ActivityCenter.current` remains the normal presentation winner. Fullscreen uses a separate selector:

```text
revealActivity = ActivityCenter.mostUrgent { $0.fullscreenPresence == .alert }
```

The selector evaluates the same active persistent/transient sets, but ignores a higher-priority ambient or persistent winner. This matters because a persistent custom activity (priority 6) currently outranks `agentDone` (priority 7); without a separate selector, a widget could hide an agent-finished notification in fullscreen.

`fullscreenPresence` is a new property on `ActivityKind`:

| Presence | Activities |
|---|---|
| `.alert` | `needsYou`, `agentDone`, `usageWarning`, `timerFinished`, `lowBattery`, `downloadKeep`, `downloadDone`, `downloadTrashed`, `screenshot` |
| `.alert` when transient | `custom` with a finite duration |
| `.hidden` | everything else, including `agentRunning`, `timer`, `meetingSoon`, `download`, `downloadExpiring`, persistent `custom`, `music`, `volume`, `brightness`, `charging`, `trayAdded`, `hello`, `accessory` |

The model presents `revealActivity` while it exists; when it expires, the model falls back to the normal winner for hover and normal display, and conceals if the pointer is outside and the panel is closed. `revealAlertsOnFullscreen` gates only the automatic reveal; it does not hide the activity from a hover reveal.

**Alternative considered:** reveal whenever `ActivityCenter.current` is any activity. Rejected because music, running agents and download progress would hold the notch down over the fullscreen app.

### 6. Fullscreen detection hysteresis

Keep the public window-list query. Split the detector into pure helpers:

- `fullscreenDisplayIDs(...)` keeps its current meaning and tests.
- A new helper identifies a fullscreen-sized window that starts below the camera housing, regardless of menu bar visibility.

`FullscreenWatcher` keeps per-display `menuBarVisibleSince` state. When a display was fullscreen on the previous refresh and the below-housing window is still present, a newly visible menu bar does not exit fullscreen until it has been continuously visible for `fullscreenMenuBarGrace` (proposed 1.5 s) or until the window/Space changes. A display that was never fullscreen still uses the strict matcher, so a zoomed window under a persistently visible menu bar is not misdetected.

The grace state resets on display-set changes, Space changes and when the menu bar hides. Passing `now` into the hysteresis helper keeps tests deterministic.

The owner filter also excludes the system capture UI (`Screenshot`, `screencapture`, `screencaptureui`, `ScreenCapture`). Its full-screen layer-0 overlay is visually identical to a fullscreen app while the capture controls are open; without the filter, taking a screenshot makes the notch slide and clips the captured notch.

**Alternatives considered:**

- Ignore menu bar visibility entirely. Rejected: a zoomed window would look fullscreen.
- Use SkyLight/MacroVisionKit space data. Rejected: private APIs and a new dependency; the public heuristic is sufficient for this feature.
- Keep the hard hide for notched displays. Rejected: the feature must work on the hardware notch too.

### 7. Per-display coordination and media keys

`NotchCoordinator.applyFullscreenHiding()` calls `controller.setFullscreenActive(enabled && fullscreen.contains(id))` for each controller. It no longer filters concealed controllers out of `primaryController`; explicit shortcut and API opens target the display under the pointer and reveal it if needed.

`LevelsService.notchIsHidden` remains driven by the all-displays fullscreen mode, not by the current reveal state:

```text
notchIsHidden = controllers are non-empty && all are fullscreen-active
```

Concealed displays do not reveal for `volume` or `brightness`, so the system HUD handoff stays stable even while an agent alert is peeking. If any display is not fullscreen, NotchNull keeps its normal HUD behavior on the visible displays.

**Alternative considered:** keep the media tap active and reveal for level changes. Rejected because it introduces an overlay during fullscreen on every volume key and makes the handoff flicker with temporary reveals.

### 8. Status, settings and accessibility

`windowStatus` adds:

```json
"fullscreen": true,
"concealed": true,
"reveal": "activity" | "hover" | "open" | null
```

`fullscreenHidden` stays as the fullscreen-mode flag. `appKitVisible` may be true while `concealed` is true; the status docs must say to read `concealed` for visual visibility. `NotchStatus.write()` is called on fullscreen and reveal changes, coalesced like the existing writes.

Settings keep `behavior.hideOnFullscreen` and add `behavior.revealAlertsOnFullscreen` (default true). The General settings copy changes from "Hide on fullscreen apps" to a slide/peek description. The new setting disables automatic alerts only; hover and explicit open still work.

While concealed, the root view gets `.accessibilityHidden(true)`, and the wake strip is also hidden from accessibility. Explicit keyboard/API open is the accessible path. With Reduce Motion enabled, concealment uses opacity with `concealOffset = 0`; no spatial slide. Snapshot rendering treats concealment as settled.

### 9. Tests and verification

- Pure tests for `ActivityKind.fullscreenPresence`, the separate `mostUrgent` selector, the `isConcealed` predicate and the offset/wake-strip geometry for notch and island.
- Hysteresis tests with injected timestamps: menu bar briefly visible, menu bar persistently visible, window/Space change.
- Recovery tests updated: fullscreen keeps the panel registered; explicit open reveals it; a missing Window Server window during fullscreen still triggers recovery.
- Render-budget test: clock/stats do not advance while concealed and resume on reveal.
- Status tests: concealed, activity-revealed, hover-revealed and open states; `fullscreenHidden` compatibility.
- Manual verification on a notched Mac and an external display: native fullscreen Safari/QuickTime, hover wake strip, click, shortcut, agent event, menu-bar reveal, VoiceOver, Reduce Motion, multi-display and media keys.

## Risks / Trade-offs

- **Accidental hover-open near the top centre** → 8 pt strip, 120 ms delay, and a click-through area outside the strip. If it proves noisy, the strip height/delay can be tuned without changing the specs.
- **Fullscreen false positives** from the public window heuristic → hysteresis plus the existing excluded-owner rules and tests. A window that is merely zoomed under a persistent menu bar still does not count.
- **Keeping the window registered** can make `appKitVisible` and Window Server visibility true while visually concealed → status exposes `concealed`, docs call out the change, and the render-budget requirement still pauses work.
- **A persistent custom activity can outrank alerts** → the separate fullscreen reveal selector prevents it; normal presentation keeps its existing winner.
- **Persistent `needsYou` can stay over fullscreen content** → this is the intended attention behavior; resolving the session or hovering away conceals it. `revealAlertsOnFullscreen` is the escape hatch for users who do not want automatic alerts.
- **Wake strip intercepts a click at the top centre** → the strip is only as wide as the closed body and 8 pt tall; clicks elsewhere pass through.
- **VoiceOver offscreen content** → explicit `accessibilityHidden` while concealed and a testable inert state.
- **Status compatibility** → `fullscreenHidden` is retained as the mode flag; `concealed` is the new visual state. Consumers that treated `appKitVisible: false` as the only hidden state must update.
- **Fullscreen app compatibility** → the panel already uses `.mainMenu + 3`, `.fullScreenAuxiliary` and `.canJoinAllSpaces`; BoringNotch uses the same family of settings. Verify on current macOS before release.

## Migration Plan

No data migration. `hideOnFullscreen` keeps its meaning and default. `revealAlertsOnFullscreen` defaults to true when absent, so existing users get alert reveals immediately; setting it to false restores the quiet behavior while keeping hover and explicit open. `fullscreenHidden` remains in status for compatibility, with `fullscreen`/`concealed`/`reveal` added. Rolling back removes the preference and restores the old hard-hide path; no stored format changes.

## Open Questions

None. The wake strip size (8 pt), hover delay (120 ms) and menu-bar grace (1.5 s) are tunable implementation constants; they do not change the specs or the task breakdown.
