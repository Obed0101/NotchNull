import AppKit
import Combine

/// Keeps one notch window per eligible screen, following display changes and the display preference.
@MainActor
final class NotchCoordinator {
    private let services: AppServices
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var lastWindowReplacement: [CGDirectDisplayID: Date] = [:]

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didWakeNotification))
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        Preferences.shared.$displayMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuild() } }
            .store(in: &cancellables)
        Preferences.shared.$selectedDisplays
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuild() } }
            .store(in: &cancellables)
        services.fullscreen.$fullscreenDisplayIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyFullscreenHiding() }
            .store(in: &cancellables)
        Preferences.shared.$hideOnFullscreen
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyFullscreenHiding() }
            .store(in: &cancellables)
        rebuild()
    }

    private var primaryController: NotchWindowController? {
        let available = NotchDisplay.connected.filter { controllers[$0.id]?.isFullscreenHidden == false }
        guard let id = DisplaySelection.target(available, pointer: NSEvent.mouseLocation) else { return nil }
        return controllers[id]
    }

    var windowStatus: JSONValue {
        .array(NotchDisplay.connected.compactMap { display in
            guard let controller = controllers[display.id], var status = controller.windowStatus.object else { return nil }
            status["displayID"] = .number(Double(display.id))
            status["displayName"] = .string(display.name)
            status["hasHardwareNotch"] = .bool(display.hasNotch)
            status["shape"] = .string(controller.model.isIsland ? "island" : "notch")
            status["screenFrame"] = .object(["x": .number(display.frame.minX), "y": .number(display.frame.minY),
                "width": .number(display.frame.width), "height": .number(display.frame.height)])
            return .object(status)
        })
    }

    private func makeController(screen: NSScreen, model: NotchViewModel? = nil) -> NotchWindowController {
        let id = NotchGeometry.screenID(screen)
        return NotchWindowController(screen: screen, services: services, model: model,
            onWindowFailure: { [weak self] in self?.replaceFailedWindow(on: id) })
    }

    private func replaceFailedWindow(on id: CGDirectDisplayID) {
        // Do not create windows repeatedly while the system itself suppresses overlays.
        if let last = lastWindowReplacement[id], Date().timeIntervalSince(last) < 30 { return }
        guard let old = controllers[id], !old.isFullscreenHidden,
              let screen = eligibleScreens().first(where: { NotchGeometry.screenID($0) == id }) else { return }
        lastWindowReplacement[id] = Date()
        let model = old.model.geometry == NotchGeometry(screen: screen) ? old.model : nil
        old.tearDown()
        controllers[id] = makeController(screen: screen, model: model)
        services.fullscreen.refresh()
        applyFullscreenHiding()
    }

    func openPrimary(tab: NotchTab? = nil) {
        primaryController?.open(tab: tab)
    }

    func closePrimary() {
        primaryController?.model.close()
    }

    /// Clipboard shortcut handler.
    func toggleClipboard() {
        guard Preferences.shared.clipboardEnabled, !Preferences.shared.hiddenTabs.contains(NotchTab.clipboard.rawValue) else { return }
        primaryController?.toggleClipboardFromKeyboard()
    }

    private func eligibleScreens() -> [NSScreen] {
        let ids = Set(DisplaySelection.eligible(NotchDisplay.connected, mode: Preferences.shared.displayMode,
            selected: Preferences.shared.selectedDisplays).map(\.id))
        return NSScreen.screens.filter { ids.contains(NotchGeometry.screenID($0)) }
    }

    private func rebuild() {
        let screens = eligibleScreens()
        let wanted = Dictionary(uniqueKeysWithValues: screens.map { (NotchGeometry.screenID($0), $0) })
        for (id, controller) in controllers {
            let current = wanted[id].map(NotchGeometry.init(screen:))
            if current == nil || current != controller.model.geometry {
                controller.tearDown()
                controllers[id] = nil
            }
        }
        for (id, screen) in wanted where controllers[id] == nil {
            controllers[id] = makeController(screen: screen)
        }
        // Re-read fullscreen before restoring panels on a new Space or after wake.
        services.fullscreen.refresh()
        applyFullscreenHiding()
        NotchStatus.write()
    }

    /// Hides each display's notch independently while a fullscreen app covers that display.
    private func applyFullscreenHiding() {
        let enabled = Preferences.shared.hideOnFullscreen
        let fullscreen = services.fullscreen.fullscreenDisplayIDs
        for (id, controller) in controllers {
            controller.setFullscreenHidden(enabled && fullscreen.contains(id))
        }
        // With no notch left to draw the HUD, the media keys go back to macOS and its own HUD.
        services.levels.notchIsHidden = !controllers.isEmpty && controllers.values.allSatisfy(\.isFullscreenHidden)
    }
}
