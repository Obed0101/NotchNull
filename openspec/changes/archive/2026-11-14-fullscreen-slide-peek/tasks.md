# Tasks

## 1. Presentation state and slide

- [x] 1.1 Add `isFullscreenActive`, `isConcealed`, `revealReason` and `concealOffset` to `NotchViewModel`, with an injected activity-reveal flag for now; verify with unit tests covering fullscreen off, open, pointer inside, alert reveal and ambient-hidden combinations.
- [x] 1.2 Add `Motion.conceal`/`Motion.reveal` tokens plus the slide margin and wake-strip constants; verify Reduce Motion selects a fade and `Motion.isSnapshot` renders a settled state.
- [x] 1.3 Apply the concealment offset and Reduce Motion opacity to the `NotchRootView` ZStack so the body and island satellites move together; verify with notch and island geometry tests and snapshot fixtures.
- [x] 1.4 Add concealed and revealed fixtures to `SnapshotRenderer`; verify `.build/debug/NotchNull --snapshots /tmp/snap` renders both states without motion artifacts.

## 2. Reveal policy and activity selection

- [x] 2.1 Add `ActivityKind.fullscreenPresence` with `.alert` for needs-you, agent-finished, usage-warning, timer-finished, low-battery, download-keep, download-done, download-trashed and screenshot, and `.hidden` for every other kind; verify with a table-driven test covering every case.
- [x] 2.2 Treat transient custom activities as alerts and persistent custom activities as hidden; verify with `CustomActivityStore` fixtures and tests for both modes.
- [x] 2.3 Add `ActivityCenter.mostUrgent(where:)`; verify a persistent custom winner does not mask a transient `agentDone`, and that music or a running agent is never selected for a fullscreen alert.
- [x] 2.4 Add `Preferences.revealAlertsOnFullscreen` with a factory default of `true` and gate automatic reveals; verify the model keeps the notch concealed for alerts when the setting is off while hover and open still work.
- [x] 2.5 Update `NotchViewModel.activityChanged`/`updateActivity` so a concealed notch presents the fullscreen alert activity and a hover reveal falls back to the normal activity winner; verify the transition tests for alert, expiry, hover and open.

## 3. Window lifecycle, wake strip and interaction

- [x] 3.1 Replace `setFullscreenHidden` with `setFullscreenActive`, keep the panel ordered in, and update `refreshSampling`, `reconcileWindowVisibility`, `open` and `toggleClipboardFromKeyboard`; verify `NotchWindowRecoveryTests` and a new test that the panel stays visible while concealed.
- [x] 3.2 Add the wake strip rectangle to `NotchViewModel.interactiveRect`, suppress satellite hit rects while concealed, and keep the body click-through outside the strip; verify notch/island geometry tests and click-through behavior.
- [x] 3.3 Add a transparent `WakeStrip` overlay with hover and click handling plus the 120 ms fullscreen open delay; verify hover opens, click opens, pointer leave closes and conceals, and `openTrigger = click` still opens on hover.
- [x] 3.4 Update `NotchCoordinator` to apply fullscreen mode per display, include concealed displays in explicit shortcut/API targeting, and keep `LevelsService.notchIsHidden` driven by the fullscreen mode; verify coordinator, API and multi-display targeting tests.
- [x] 3.5 Update file-drop and scroll guards so concealed content is inert outside the wake strip; verify the drag/scroll tests or focused manual checks.

## 4. Fullscreen detection hysteresis

- [x] 4.1 Split the pure below-housing fullscreen detector from the strict matcher; verify tests for notched and non-notched displays.
- [x] 4.2 Add per-display `menuBarVisibleSince` hysteresis with `fullscreenMenuBarGrace`; verify a brief menu-bar reveal keeps fullscreen and a persistently visible menu bar exits it.
- [x] 4.3 Reset hysteresis state on Space and display changes and when the menu bar hides; verify with injected-time tests.
- [x] 4.4 Update `FullscreenWatcherTests` for the new helpers and regression cases; verify `swift test --filter FullscreenWatcherTests`.

## 5. Settings, status, accessibility and docs

- [x] 5.1 Add `behavior.revealAlertsOnFullscreen` to `SettingsFile` and the preferences factory defaults; verify the settings round-trip test and live application.
- [x] 5.2 Update the General settings copy for the slide behavior and add the reveal-alerts toggle; verify by building the app and exercising both settings.
- [x] 5.3 Add `fullscreen`, `concealed` and `reveal` to `windowStatus` while keeping `fullscreenHidden`, and write status on fullscreen/reveal changes; verify with unit tests and `notchnull status`.
- [x] 5.4 Hide concealed content from accessibility and keep only the wake strip interactive; verify with VoiceOver checks and the Reduce Motion snapshot/test added in 1.3.
- [x] 5.5 Update `README.md`, `docs/multiple-displays.md` and `skills/notchnull/references/settings.md` for the slide, wake strip, reveal policy, status fields and new key; verify the documented commands and status examples.
- [x] 5.6 Update the clock/stat visibility coverage in `NotchWindowRecoveryTests` and `NotchRenderBudgetTests` for concealed-body pausing and reveal resumption; verify `swift test --filter NotchRenderBudget` and the recovery tests.

## 6. Integration and manual verification

- [x] 6.1 Run `swift build && swift test`; verify all tests pass.
- [x] 6.2 Run `scripts/build-app.sh`, launch the app, and verify fullscreen Safari/QuickTime: idle conceal, hover wake/open, click, explicit shortcut/API, agent event, menu-bar reveal, media keys and fullscreen exit.
- [x] 6.3 Verify on a notched Mac if available and with an external display: per-display concealment, island satellites, forced island, multi-display shortcuts and status fields; document any hardware case that cannot be exercised.
- [x] 6.4 Verify VoiceOver, Reduce Motion and performance: the concealed notch runs no clock, stat or display-link work, and reveal resumes from current values.
- [x] 6.5 Verify `notchnull status` and `settings.json` report `fullscreen`, `concealed`, `reveal`, `fullscreenHidden` and `behavior.revealAlertsOnFullscreen` as documented.

> Hardware note: no notched Mac or external display was available in this session. The built-in no-notch display was used for the live checks; the notched/island hardware cases remain unexercised on physical hardware.

## Workflow follow-up

- Add a release note for the version that ships this behavior.
- Archive the change after review.
