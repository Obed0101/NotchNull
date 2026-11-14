# Proposal

## Why

NotchNull currently removes its panel outright while a fullscreen app covers a display. That prevents the notch from showing anything useful during fullscreen work—agent attention, finished turns, timers, downloads—and makes the notch unreachable by hover or click. The notch should step out of the way without disappearing: slide up, stay ready, and slide back down when it has something to say or when the user reaches for it.

## What Changes

- Replace the hard fullscreen hide (`panel.orderOut`) with a per-display slide: the body and island satellites move above the screen edge while the panel window stays registered and ready.
- Keep the notch concealed while idle in fullscreen; reveal it automatically for attention, action and feedback activities: `needsYou`, `agentDone`, `usageWarning`, `timerFinished`, `lowBattery`, `downloadKeep`, `downloadDone`, `downloadTrashed`, `screenshot`, and transient custom activities.
- Do not reveal for ambient or persistent state: `agentRunning`, `timer`, `meetingSoon`, `download` progress, `downloadExpiring`, persistent custom activities, `music`, `volume`, `brightness`, `charging`, `trayAdded`, `hello`, or `accessory`.
- Add a top-centre wake strip while concealed. Hovering it slides the body down and opens the panel after a short delay; clicking also opens; moving the pointer away closes and conceals again after the existing close delay.
- Explicit open paths (keyboard shortcut, local API, menu actions) reveal and open on a fullscreen display instead of excluding it from targeting.
- Add a `behavior.revealAlertsOnFullscreen` preference (default `true`) that can disable automatic alert reveals; hover and explicit open still work.
- Harden fullscreen detection so a temporarily visible menu bar on a notched Mac does not end the fullscreen state while the pointer reaches for the top edge.
- Preserve per-display independence across multiple displays and Spaces.
- Report the new state in status output (`fullscreen`, `concealed`, `reveal`) and keep `fullscreenHidden` as the fullscreen-mode flag for compatibility.
- **BREAKING** (status semantics): a concealed notch keeps its window registered, so `appKitVisible` can be true while `concealed` is true. Consumers must read `concealed` instead of treating `appKitVisible: false` as the only hidden state.
- Pause clock, stats and animations while concealed, hide concealed content from VoiceOver, and use a fade instead of a slide when Reduce Motion is on.
- Keep macOS's media-key HUD handoff when every display is in fullscreen; concealed displays do not reveal for volume or brightness.

## Capabilities

### New Capabilities

- `fullscreen-concealment`: per-display fullscreen slide-away, wake strip, reveal policy, and the status/settings that expose it.

### Modified Capabilities

- `notch-render-budget`: hidden-for-fullscreen now means a concealed body while the panel window remains registered; timelines and animations must still pause, and the existing no-animation-while-hidden guarantee must cover this state.

## Impact

- Core: `NotchWindowController`, `NotchViewModel`, `NotchCoordinator`, `FullscreenWatcher`.
- Notch UI: `NotchRootView`, satellite frames and interactive rects, body offset and accessibility.
- Activity policy: `ActivityCenter`, `CustomActivityStore`, activity categories.
- Settings/status: `Preferences`, `SettingsFile`, `SettingsView`, `NotchAPI`/`NotchStatus`.
- Media: `LevelsService` fullscreen handoff remains, with concealed displays ignored for HUD reveals.
- Tests: `FullscreenWatcherTests`, `NotchWindowRecoveryTests`, `NotchRenderBudgetTests`, and new fullscreen concealment/model tests.
- Docs: README, `docs/multiple-displays.md`, `skills/notchnull/references/settings.md`.
- No new dependencies, private APIs or storage formats. One new UserDefaults/`settings.json` key: `behavior.revealAlertsOnFullscreen` (default `true`).
