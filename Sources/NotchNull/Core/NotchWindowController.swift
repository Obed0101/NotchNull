import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Owns one notch panel on one screen: positions it, routes pointer input and keeps
/// click-through outside the visible pieces.
@MainActor
final class NotchWindowController {
    let model: NotchViewModel
    private let panel: NotchPanel
    private var cancellables: Set<AnyCancellable> = []
    private var dropArmed = false
    private var scrollAccumulator: CGFloat = 0
    private var tabSwipeAccumulator: CGFloat = 0
    private var lastTabSwipe = Date.distantPast
    private let clipboard: ClipboardService
    private let picker: ClipboardPicker
    private var keyMonitor: Any?
    /// The keyboard shortcut opened the panel, so losing focus closes it again.
    private var openedFromKeyboard = false
    /// A fullscreen app covers this controller's display (and the setting is on).
    private var fullscreenHidden = false
    private var tornDown = false
    private var failedRestores = 0
    private let onWindowFailure: (() -> Void)?
    var isFullscreenHidden: Bool { fullscreenHidden }

    init(screen: NSScreen, services: AppServices, model: NotchViewModel? = nil, onWindowFailure: (() -> Void)? = nil) {
        let geometry = NotchGeometry(screen: screen)
        self.model = model ?? NotchViewModel(geometry: geometry)
        self.onWindowFailure = onWindowFailure
        panel = NotchPanel(frame: geometry.windowFrame)
        clipboard = services.clipboard
        picker = services.clipboardPicker

        let root = NotchRootView()
            .environmentObject(self.model)
            .withServices(services)
        panel.contentView = NotchHostingView(rootView: AnyView(root))
        panel.setFrame(geometry.windowFrame, display: false)
        panel.orderFrontRegardless()

        PointerTracker.shared.register(self, handlers: .init(
            moved: { [weak self] point in self?.pointerMoved(point) },
            dragged: { [weak self] point, hasDrag in self?.pointerDragged(point, hasFileDrag: hasDrag) },
            mouseUp: { [weak self] point in self?.pointerReleased(point) },
            scrolled: { [weak self] event in self?.scrolled(event) }
        ))

        self.model.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                DispatchQueue.main.async {
                    self?.refreshHitTesting()
                    self?.releaseFocusIfCollapsed(phase)
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: panel)
            .sink { [weak self] _ in self?.installKeyMonitor() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in self?.panelResignedKey() }
            .store(in: &cancellables)
        // AppKit's visibility flags can disagree with Window Server. Check the actual
        // window registration instead of repeatedly ordering an already ordered window.
        Timer.publish(every: Constants.Intervals.fullscreenPoll, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.reconcileWindowVisibility(isOnScreen: self.panel.isVisible ? self.windowServerVisibility : false)
            }
            .store(in: &cancellables)
        Log.window.info("Notch panel on screen \(NotchGeometry.screenID(screen)) notch=\(geometry.notchSize.width)x\(geometry.notchSize.height) hardware=\(geometry.hasHardwareNotch)")
    }

    func tearDown() {
        tornDown = true
        // Deliberately removing this display must not trigger automatic recovery.
        cancellables.removeAll()
        removeKeyMonitor()
        PointerTracker.shared.unregister(self)
        panel.orderOut(nil)
        panel.close()
    }

    /// Hides this display's notch while a fullscreen app covers it; the controller is kept
    /// so the notch returns instantly when fullscreen ends.
    func setFullscreenHidden(_ hidden: Bool) {
        guard hidden != fullscreenHidden else {
            // AppKit can order a panel out independently during Space/display transitions.
            // An unchanged fullscreen state must still reconcile the actual window.
            if !hidden { restoreVisibility() }
            return
        }
        fullscreenHidden = hidden
        if hidden {
            model.close()
            panel.orderOut(nil)
        } else {
            restoreVisibility()
        }
    }

    /// nil means Window Server could not be queried; it is not evidence of a hidden panel.
    private var windowServerVisibility: Bool? {
        guard let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(panel.windowNumber)) as? [[String: Any]],
              let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == panel.windowNumber })
        else { return nil }
        return (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
    }

    var windowStatus: JSONValue {
        .object([
            "windowNumber": .number(Double(panel.windowNumber)),
            "appKitVisible": .bool(panel.isVisible),
            "onActiveSpace": .bool(panel.isOnActiveSpace),
            "windowServerVisible": windowServerVisibility.map(JSONValue.bool) ?? .null,
            "fullscreenHidden": .bool(fullscreenHidden),
            "failedRestores": .number(Double(failedRestores)),
        ])
    }

    /// Takes an observed Window Server state so the failure path can be tested deterministically.
    func reconcileWindowVisibility(isOnScreen: Bool?) {
        guard !tornDown, !fullscreenHidden, !NSApp.isHidden, let isOnScreen else { return }
        if isOnScreen {
            failedRestores = 0
            if panel.frame != model.geometry.windowFrame { restoreVisibility() }
            return
        }
        failedRestores += 1
        if failedRestores == 1 {
            Log.window.notice("Re-registering a notch panel missing from Window Server")
            restoreVisibility(forceReorder: true)
        } else if failedRestores == 2 {
            Log.window.error("Notch panel remains missing after reordering; replacing its window")
            onWindowFailure?()
        }
    }

    private func restoreVisibility(forceReorder: Bool = false) {
        guard !tornDown, !fullscreenHidden else { return }
        if forceReorder { panel.orderOut(nil) }
        panel.setFrame(model.geometry.windowFrame, display: false)
        panel.orderFrontRegardless()
        refreshHitTesting()
    }

    func open(tab: NotchTab? = nil) {
        guard !fullscreenHidden else { return }
        failedRestores = 0
        restoreVisibility(forceReorder: windowServerVisibility == false)
        model.open(tab: tab)
    }

    // MARK: Keyboard

    /// The Clipboard shortcut: opens the panel on Clipboard ready to type, or closes it when it
    /// is already showing Clipboard with the keyboard.
    func toggleClipboardFromKeyboard() {
        guard !fullscreenHidden else { return }
        if model.phase == .open, model.selectedTab == .clipboard, panel.isKeyWindow {
            endKeyboardSession(restoreFocus: true)
            return
        }
        restoreVisibility()
        openedFromKeyboard = true
        // Key first, so the search field can take focus as the tab appears.
        panel.makeKey()
        model.open(tab: .clipboard)
        picker.begin()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.consumesKey(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func panelResignedKey() {
        removeKeyMonitor()
        guard openedFromKeyboard else { return }
        // Focus moved to another app (a click elsewhere): tuck the panel away like a menu.
        openedFromKeyboard = false
        picker.end()
        if !model.isPointerInside { model.close() }
    }

    /// True for keys the Clipboard tab handles; everything else reaches the search field.
    private func consumesKey(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        let onClipboard = model.phase == .open && model.selectedTab == .clipboard
        if Int(event.keyCode) == kVK_Escape {
            if onClipboard, !picker.query.isEmpty {
                picker.query = ""
            } else {
                endKeyboardSession(restoreFocus: true)
            }
            return true
        }
        guard onClipboard else { return false }
        let count = picker.visibleItems(from: clipboard.items).count
        let searchIsEmpty = picker.query.isEmpty
        switch Int(event.keyCode) {
        case kVK_UpArrow: picker.move(.up, itemCount: count)
        case kVK_DownArrow: picker.move(.down, itemCount: count)
        // With text in the field, left and right move the caret instead.
        case kVK_LeftArrow where searchIsEmpty: picker.move(.left, itemCount: count)
        case kVK_RightArrow where searchIsEmpty: picker.move(.right, itemCount: count)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            commitSelection(paste: !event.modifierFlags.contains(.command))
        default:
            return false
        }
        return true
    }

    /// Return copies the highlighted item and pastes it into the app in front; ⌘Return only copies.
    private func commitSelection(paste: Bool) {
        guard let item = picker.selectedItem(in: clipboard.items) else { return }
        clipboard.copy(item)
        endKeyboardSession(restoreFocus: true)
        guard paste else { return }
        // Let the app in front take keyboard focus back before ⌘V arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if !ClipboardService.pasteIntoFrontApp() {
                Log.files.info("Clipboard item copied; pasting needs Accessibility")
            }
        }
    }

    private func endKeyboardSession(restoreFocus: Bool) {
        openedFromKeyboard = false
        picker.end()
        model.close()
        if restoreFocus { releaseFocus() }
    }

    /// A closed notch must never keep the keyboard, or typing would vanish into it.
    private func releaseFocusIfCollapsed(_ phase: NotchViewModel.Phase) {
        guard phase != .open, phase != .drop, panel.isKeyWindow else { return }
        openedFromKeyboard = false
        picker.end()
        releaseFocus()
    }

    /// A non-activating panel keeps keyboard focus until it leaves the screen; reordering it
    /// hands focus back to the app that was in front without flashing the (closing) body.
    private func releaseFocus() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Pointer

    private func pointerMoved(_ point: NSPoint) {
        guard !dropArmed, !fullscreenHidden else { return }
        panel.ignoresMouseEvents = !model.pointerMoved(to: point)
    }

    private func pointerDragged(_ point: NSPoint, hasFileDrag: Bool) {
        guard hasFileDrag, Preferences.shared.trayEnabled else { return }
        let near = model.dropProximityRect.contains(point)
        if near && !dropArmed {
            dropArmed = true
            panel.ignoresMouseEvents = false
            model.beginDrop()
        } else if !near && dropArmed {
            dropArmed = false
            model.endDrop()
            refreshHitTesting()
        }
    }

    private func pointerReleased(_ point: NSPoint) {
        guard dropArmed else { return }
        dropArmed = false
        // Give SwiftUI's drop handler a beat to receive the payload before the tiles collapse.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.model.endDrop()
            self.refreshHitTesting()
        }
    }

    private func scrolled(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        guard model.interactiveRect.contains(location) else { return }
        if event.phase == .began { scrollAccumulator = 0 }
        let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        scrollAccumulator += delta
        let threshold: CGFloat = 18
        if !model.isExpanded, scrollAccumulator > threshold {
            scrollAccumulator = 0
            model.open()
        } else if model.phase == .open, scrollAccumulator < -threshold * 2,
                  location.y > model.geometry.screenFrame.maxY - model.bodyTop - model.rowHeight - Theme.Size.headerHeight - 16 {
            scrollAccumulator = 0
            model.close()
        }
        handleTabSwipe(event)
    }

    /// Horizontal swipe on the open panel background switches tabs. Child horizontal
    /// scrollers (Tray, Widgets) consume the gesture first: swiping over one scrolls it.
    private func handleTabSwipe(_ event: NSEvent) {
        guard model.phase == .open, Preferences.shared.tabSwipeEnabled else {
            tabSwipeAccumulator = 0
            return
        }
        // Local events only, so each gesture is handled once and locationInWindow is valid.
        guard event.window === panel else { return }
        guard event.momentumPhase.isEmpty else { return }
        if event.phase == .began { tabSwipeAccumulator = 0 }
        let dx = TabSwipe.fingerDeltaX(scrollingDeltaX: event.scrollingDeltaX, inverted: event.isDirectionInvertedFromDevice)
        guard TabSwipe.isHorizontal(dx, event.scrollingDeltaY) else { return }
        if isOverHorizontallyScrollableContent(at: event.locationInWindow) {
            tabSwipeAccumulator = 0
            return
        }
        tabSwipeAccumulator += dx
        guard Date().timeIntervalSince(lastTabSwipe) >= TabSwipe.cooldown,
              let step = TabSwipe.step(for: tabSwipeAccumulator) else { return }
        tabSwipeAccumulator = 0
        lastTabSwipe = Date()
        model.stepTab(by: step)
    }

    /// True when the point sits over an NSScrollView with horizontal overflow.
    private func isOverHorizontallyScrollableContent(at windowPoint: NSPoint) -> Bool {
        guard let root = panel.contentView, root.bounds.contains(root.convert(windowPoint, from: nil)),
              let hit = root.hitTest(windowPoint) else { return false }
        var view: NSView? = hit
        while let current = view {
            if let scroll = (current as? NSScrollView) ?? current.enclosingScrollView {
                let visible = scroll.contentView.bounds.width
                let docWidth = scroll.documentView?.frame.width ?? visible
                if docWidth > visible + 1 { return true }
            }
            view = current.superview
        }
        return false
    }

    private func refreshHitTesting() {
        guard !dropArmed else { return }
        panel.ignoresMouseEvents = !model.pointerMoved(to: NSEvent.mouseLocation)
    }
}
