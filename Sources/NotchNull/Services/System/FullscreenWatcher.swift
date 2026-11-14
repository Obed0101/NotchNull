import AppKit
import Combine

/// A window as far as fullscreen detection cares: who owns it, its layer and its size.
struct FullscreenWindow: Equatable {
    var owner: String
    var pid: Int32
    var layer: Int
    var bounds: CGRect
}

/// A display as far as fullscreen detection cares: its ID, its global bounds and the height
/// of the camera housing, which fullscreen windows sit below on a MacBook with a notch.
struct FullscreenScreen: Equatable {
    var id: CGDirectDisplayID
    var bounds: CGRect
    var topInset: CGFloat = 0
}

/// Publishes which displays currently have a fullscreen app covering them. A window counts
/// as fullscreen when it sits on the normal window layer and its size matches the display
/// size; each display is evaluated independently, so a fullscreen app on display 1 hides
/// only that display's notch.
///
/// The check is event-driven first (app activation, Space change, display change) with a
/// slow timer as a backstop for transitions that post no notification (e.g. in-app video
/// fullscreen). The window-list query only reads bounds/owner/layer, which needs no
/// Screen Recording permission, and the timer stops while the setting is off.
@MainActor
final class FullscreenWatcher: ObservableObject {
    @Published private(set) var fullscreenDisplayIDs: Set<CGDirectDisplayID> = []

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var settingCancellable: AnyCancellable?
    private var lastPublished: Set<CGDirectDisplayID>?
    /// When each notched display first showed a menu bar during a fullscreen transition.
    private var menuBarVisibleSince: [CGDirectDisplayID: Date] = [:]

    /// Window owners that cover the screen but are not apps (menu bar, wallpaper, overlays).
    /// The screenshot UI is included because its full-screen overlay otherwise looks exactly
    /// like a fullscreen app for the few seconds the capture controls are open.
    static let excludedOwners: Set<String> = [
        "Dock", "Window Server", "Control Center", "Notification Center",
        "Wallpaper", "ScreenSaverEngine", "loginwindow",
        "Screenshot", "screencapture", "screencaptureui", "ScreenCapture",
    ]

    /// Bounds slop in points: fullscreen windows should match the display exactly, but allow
    /// rounding differences in Quartz coordinates.
    static let sizeTolerance: CGFloat = 1

    /// The menu bar is a Window Server window on this layer. A fullscreen Space has none until
    /// the pointer reveals it, which tells a fullscreen window below the camera housing from a
    /// window that was only zoomed to fill the screen.
    static let menuBarLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
    static let menuBarOwner = "Window Server"

    func start() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resetHysteresis()
                    self?.refresh()
                }
            },
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.resetHysteresis()
                    self?.refresh()
                }
            },
        ]
        settingCancellable = Preferences.shared.$hideOnFullscreen
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTimer() }
        updateTimer()
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        refresh()
        guard Preferences.shared.hideOnFullscreen else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Constants.Intervals.fullscreenPoll, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Re-reads the on-screen window list and publishes the fullscreen display set.
    func refresh() {
        guard Preferences.shared.hideOnFullscreen else {
            if fullscreenDisplayIDs.isEmpty == false { fullscreenDisplayIDs = [] }
            lastPublished = []
            menuBarVisibleSince.removeAll()
            return
        }
        let now = Date()
        let windows = Self.currentWindows()
        let screens = Self.currentScreens()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let strict = Self.fullscreenDisplayIDs(windows: windows, screens: screens, ownPID: ownPID)
        let belowHousing = Self.belowHousingFullscreenDisplayIDs(windows: windows, screens: screens, ownPID: ownPID)
        let next = Self.applyingMenuBarGrace(
            strict: strict,
            belowHousing: belowHousing,
            previous: lastPublished ?? [],
            screens: screens,
            windows: windows,
            menuBarVisibleSince: &menuBarVisibleSince,
            now: now,
            grace: Constants.Intervals.fullscreenMenuBarGrace
        )
        guard next != lastPublished else { return }
        lastPublished = next
        fullscreenDisplayIDs = next
    }

    private func resetHysteresis() {
        menuBarVisibleSince.removeAll()
    }

    private static func currentScreens() -> [FullscreenScreen] {
        NSScreen.screens.map { screen in
            let id = NotchGeometry.screenID(screen)
            return FullscreenScreen(
                id: id,
                bounds: CGDisplayBounds(id),
                topInset: screen.safeAreaInsets.top
            )
        }
    }

    private static func currentWindows() -> [FullscreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [FullscreenWindow] = []
        result.reserveCapacity(list.count)
        for entry in list {
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue
            else { continue }
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            result.append(
                FullscreenWindow(
                    owner: owner,
                    pid: pid,
                    layer: layer,
                    bounds: CGRect(x: x, y: y, width: width, height: height)
                )
            )
        }
        return result
    }

    /// Pure matcher, unit-tested: which screens have a normal-layer window covering them.
    static func fullscreenDisplayIDs(
        windows: [FullscreenWindow],
        screens: [FullscreenScreen],
        ownPID: Int32
    ) -> Set<CGDirectDisplayID> {
        var result: Set<CGDirectDisplayID> = []
        for screen in screens {
            // Below the camera housing only counts while the menu bar is away.
            let belowHousing = screen.topInset > 0 && !menuBarIsVisible(on: screen, windows: windows)
            for window in windows {
                guard window.layer == 0,
                      window.pid != ownPID,
                      !excludedOwners.contains(window.owner),
                      abs(window.bounds.minX - screen.bounds.minX) <= sizeTolerance,
                      abs(window.bounds.maxX - screen.bounds.maxX) <= sizeTolerance,
                      abs(window.bounds.maxY - screen.bounds.maxY) <= sizeTolerance
                else { continue }
                let top = window.bounds.minY - screen.bounds.minY
                guard abs(top) <= sizeTolerance || (belowHousing && abs(top - screen.topInset) <= sizeTolerance) else { continue }
                result.insert(screen.id)
                break
            }
        }
        return result
    }

    /// Pure matcher for a fullscreen-sized window that starts below the camera housing,
    /// regardless of whether the menu bar is temporarily visible.
    static func belowHousingFullscreenDisplayIDs(
        windows: [FullscreenWindow],
        screens: [FullscreenScreen],
        ownPID: Int32
    ) -> Set<CGDirectDisplayID> {
        var result: Set<CGDirectDisplayID> = []
        for screen in screens where screen.topInset > 0 {
            for window in windows {
                guard window.layer == 0,
                      window.pid != ownPID,
                      !excludedOwners.contains(window.owner),
                      abs(window.bounds.minX - screen.bounds.minX) <= sizeTolerance,
                      abs(window.bounds.maxX - screen.bounds.maxX) <= sizeTolerance,
                      abs(window.bounds.maxY - screen.bounds.maxY) <= sizeTolerance,
                      abs((window.bounds.minY - screen.bounds.minY) - screen.topInset) <= sizeTolerance
                else { continue }
                result.insert(screen.id)
                break
            }
        }
        return result
    }

    /// Keeps a notched display in fullscreen while its menu bar is only briefly visible.
    /// The menu bar hides in fullscreen; raising the pointer to the top edge reveals it, which
    /// must not be mistaken for leaving fullscreen before the user has a chance to interact.
    static func applyingMenuBarGrace(
        strict: Set<CGDirectDisplayID>,
        belowHousing: Set<CGDirectDisplayID>,
        previous: Set<CGDirectDisplayID>,
        screens: [FullscreenScreen],
        windows: [FullscreenWindow],
        menuBarVisibleSince: inout [CGDirectDisplayID: Date],
        now: Date,
        grace: TimeInterval
    ) -> Set<CGDirectDisplayID> {
        var result = strict
        var next: [CGDirectDisplayID: Date] = [:]
        for screen in screens {
            let visible = screen.topInset > 0 && menuBarIsVisible(on: screen, windows: windows)
            if visible {
                next[screen.id] = menuBarVisibleSince[screen.id] ?? now
            }
            guard previous.contains(screen.id),
                  belowHousing.contains(screen.id),
                  !strict.contains(screen.id),
                  visible,
                  let since = next[screen.id],
                  now.timeIntervalSince(since) < grace
            else { continue }
            result.insert(screen.id)
        }
        menuBarVisibleSince = next
        return result
    }

    static func menuBarIsVisible(on screen: FullscreenScreen, windows: [FullscreenWindow]) -> Bool {
        windows.contains { window in
            window.layer == menuBarLayer
                && window.owner == menuBarOwner
                && abs(window.bounds.minX - screen.bounds.minX) <= sizeTolerance
                && abs(window.bounds.minY - screen.bounds.minY) <= sizeTolerance
        }
    }
}
