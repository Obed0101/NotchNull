import Combine
import Foundation
import SwiftUI

/// User preferences persisted in UserDefaults. Services and views observe this object; motion
/// values are also read straight from UserDefaults by `Motion` so they apply everywhere.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    enum DisplayMode: String, CaseIterable, Identifiable {
        case builtIn, main, all, selected
        var id: String { rawValue }
        var title: String {
            switch self {
            case .builtIn: "Built-in display"
            case .main: "Main display"
            case .all: "All displays"
            case .selected: "Selected displays"
            }
        }
    }

    enum OpenTrigger: String, CaseIterable, Identifiable {
        case hover, click
        var id: String { rawValue }
        var title: String { self == .hover ? "Hover" : "Click" }
    }

    enum BodyStyle: String, CaseIterable, Identifiable {
        case black, glass, tinted
        var id: String { rawValue }
        var title: String {
            switch self {
            case .black: "Black"
            case .glass: "Glass"
            case .tinted: "Tinted"
            }
        }
    }

    /// Rows available in the Home tab's quick list.
    enum HomeRow: String, CaseIterable, Identifiable {
        case keepAwake, upNext, timer, system, network
        var id: String { rawValue }
        var title: String {
            switch self {
            case .keepAwake: "Keep Awake"
            case .upNext: "Up next"
            case .timer: "Timer"
            case .system: "CPU and memory"
            case .network: "Network"
            }
        }
    }

    enum MotionPreset: String, CaseIterable, Identifiable {
        case instant, snappy, balanced, relaxed
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var values: (speed: Double, bounce: Double, hover: Double) {
            switch self {
            case .instant: (2.0, 0.0, 0.0)
            case .snappy: (1.35, 0.12, 0.04)
            case .balanced: (1.0, 0.18, 0.08)
            case .relaxed: (0.75, 0.24, 0.16)
            }
        }
    }

    /// Where the body lives: morphing out of the hardware notch, or floating as an island.
    enum ShapeStyle: String, CaseIterable, Identifiable {
        case auto, notch, island
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: "Automatic"
            case .notch: "Notch"
            case .island: "Island"
            }
        }
    }

    /// What the idle island shows.
    enum PillContent: String, CaseIterable, Identifiable {
        case clock, dateClock, battery, clockBattery, nothing
        var id: String { rawValue }
        var title: String {
            switch self {
            case .clock: "Clock"
            case .dateClock: "Date and clock"
            case .battery: "Battery"
            case .clockBattery: "Clock and battery"
            case .nothing: "Nothing"
            }
        }
    }

    /// How an agent's logo moves while its session works. Still by default.
    enum AgentMarkMotion: String, CaseIterable, Identifiable {
        case still, spin, pulse, shimmer
        var id: String { rawValue }
        var title: String {
            switch self {
            case .still: "Still"
            case .spin: "Spin"
            case .pulse: "Pulse"
            case .shimmer: "Shimmer"
            }
        }
    }

    /// Limits shared by the settings sliders, settings.json and the layout code. They are wide on
    /// purpose: the only hard bound is the window the body draws in (`Theme.Size.canvas`).
    enum Limits {
        static let panelWidth: ClosedRange<Double> = 0...1200
        static let panelHeight: ClosedRange<Double> = 0...600
        static let closedExtraWidth: ClosedRange<Double> = 0...800
        static let activityWidthScale: ClosedRange<Double> = 0...3
        static let cornerScale: ClosedRange<Double> = 0...3
        static let bodyOpacity: ClosedRange<Double> = 0...1
        /// 0 sizes the idle island to what it shows.
        static let islandWidth: ClosedRange<Double> = 0...800
        /// 0 fits the island inside the menu bar.
        static let islandHeight: ClosedRange<Double> = 0...120
        static let islandTop: ClosedRange<Double> = 0...200
    }

    private let defaults = UserDefaults.standard

    // MARK: Look
    @Published var displayMode: DisplayMode { didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) } }
    @Published var selectedDisplays: [String] { didSet { defaults.set(selectedDisplays, forKey: "selectedDisplays") } }
    @Published var openTrigger: OpenTrigger { didSet { defaults.set(openTrigger.rawValue, forKey: Keys.openTrigger) } }
    @Published var bodyStyle: BodyStyle { didSet { defaults.set(bodyStyle.rawValue, forKey: Keys.bodyStyle) } }
    @Published var tintHex: Int { didSet { defaults.set(tintHex, forKey: Keys.tintHex) } }
    @Published var accentHex: Int { didSet { defaults.set(accentHex, forKey: Keys.accentHex) } }
    /// Use the accent color chosen in System Settings instead of `accentHex`.
    @Published var accentFollowsSystem: Bool { didSet { save(accentFollowsSystem, Keys.accentFollowsSystem) } }
    /// The macOS accent color, refreshed when it changes in System Settings.
    @Published private(set) var systemAccent: Color = Preferences.currentSystemAccent()
    @Published var bodyOpacity: Double { didSet { defaults.set(bodyOpacity, forKey: Keys.bodyOpacity) } }
    @Published var cornerScale: Double { didSet { defaults.set(cornerScale, forKey: Keys.cornerScale) } }
    @Published var shadow: Bool { didSet { save(shadow, Keys.shadow) } }
    @Published var emissionIntensity: Double { didSet { defaults.set(emissionIntensity, forKey: Keys.emissionIntensity) } }
    @Published var glowNeedsYou: Bool { didSet { save(glowNeedsYou, Keys.glowNeedsYou) } }
    @Published var hideNotch: Bool { didSet { save(hideNotch, Keys.hideNotch) } }

    // MARK: Island
    /// Automatic floats an island on screens without a hardware notch (including a MacBook set
    /// to a resolution that leaves the notch area out) and uses the notch everywhere else.
    @Published var shapeStyle: ShapeStyle { didSet { defaults.set(shapeStyle.rawValue, forKey: Keys.shapeStyle) } }
    @Published var pillContent: PillContent { didSet { defaults.set(pillContent.rawValue, forKey: Keys.pillContent) } }
    @Published var agentMarkMotion: AgentMarkMotion { didSet { defaults.set(agentMarkMotion.rawValue, forKey: Keys.agentMarkMotion) } }
    @Published var use24Hour: Bool { didSet { save(use24Hour, Keys.use24Hour) } }
    @Published var islandSatellites: Bool { didSet { save(islandSatellites, Keys.islandSatellites) } }
    @Published var islandWidth: Double { didSet { defaults.set(islandWidth, forKey: Keys.islandWidth) } }
    @Published var islandHeight: Double { didSet { defaults.set(islandHeight, forKey: Keys.islandHeight) } }
    /// Gap between the top of the screen and the island.
    @Published var islandTop: Double { didSet { defaults.set(islandTop, forKey: Keys.islandTop) } }

    // MARK: Size
    @Published var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) } }
    @Published var panelHeight: Double { didSet { defaults.set(panelHeight, forKey: Keys.panelHeight) } }
    /// Extra width added to the closed notch beyond the camera housing (it can only grow).
    @Published var closedExtraWidth: Double { didSet { defaults.set(closedExtraWidth, forKey: Keys.closedExtraWidth) } }
    /// Scales how wide the wings and banners grow beside the notch.
    @Published var activityWidthScale: Double { didSet { defaults.set(activityWidthScale, forKey: Keys.activityWidthScale) } }

    // MARK: Motion
    @Published var animationSpeed: Double { didSet { defaults.set(animationSpeed, forKey: Keys.animationSpeed) } }
    @Published var bounce: Double { didSet { defaults.set(bounce, forKey: Keys.bounce) } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) } }
    @Published var closeDelay: Double { didSet { defaults.set(closeDelay, forKey: Keys.closeDelay) } }
    @Published var staggerContent: Bool { didSet { save(staggerContent, Keys.staggerContent) } }

    // MARK: Behavior
    @Published var haptics: Bool { didSet { save(haptics, "haptics") } }
    @Published var sounds: Bool { didSet { save(sounds, Keys.sounds) } }
    @Published var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }
    /// Global shortcut that opens the notch on the Clipboard tab; nil turns it off.
    @Published var clipboardShortcut: KeyShortcut? {
        didSet { defaults.set(clipboardShortcut?.dictionary ?? [:], forKey: Keys.clipboardShortcut) }
    }
    @Published var sayHello: Bool { didSet { save(sayHello, "sayHello") } }
    @Published var emissionEdge: Bool { didSet { save(emissionEdge, "emissionEdge") } }
    @Published var paceWarnings: Bool { didSet { save(paceWarnings, Keys.paceWarnings) } }
    /// Show what is left of each limit (like a battery) instead of what has been used.
    @Published var usageShowsRemaining: Bool { didSet { save(usageShowsRemaining, Keys.usageShowsRemaining) } }
    /// Swipe left or right on the open panel background to move through tabs.
    @Published var tabSwipeEnabled: Bool { didSet { save(tabSwipeEnabled, Keys.tabSwipe) } }
    /// Hide the notch on a display while a fullscreen app covers that display.
    @Published var hideOnFullscreen: Bool { didSet { save(hideOnFullscreen, Keys.hideOnFullscreen) } }
    /// Ask GitHub once a day whether a newer release exists.
    @Published var checkForUpdates: Bool { didSet { save(checkForUpdates, Keys.checkForUpdates) } }

    // MARK: Features
    @Published var musicEnabled: Bool { didSet { save(musicEnabled, "musicEnabled") } }
    @Published var musicWings: Bool { didSet { save(musicWings, "musicWings") } }
    @Published var hudEnabled: Bool { didSet { save(hudEnabled, "hudEnabled") } }
    @Published var replaceSystemHUD: Bool { didSet { save(replaceSystemHUD, "replaceSystemHUD") } }
    @Published var trayEnabled: Bool { didSet { save(trayEnabled, "trayEnabled") } }
    @Published var clipboardEnabled: Bool { didSet { save(clipboardEnabled, "clipboardEnabled") } }
    @Published var screenshotsEnabled: Bool { didSet { save(screenshotsEnabled, "screenshotsEnabled") } }
    @Published var downloadsEnabled: Bool { didSet { save(downloadsEnabled, "downloadsEnabled") } }
    /// Ask how long to keep each new download, then move it to the Trash when time is up.
    @Published var downloadCleanupEnabled: Bool { didSet { save(downloadCleanupEnabled, Keys.downloadCleanup) } }
    /// The stop highlighted when the notch asks.
    @Published var downloadDefaultChoice: KeepChoice { didSet { defaults.set(downloadDefaultChoice.rawValue, forKey: Keys.downloadDefault) } }
    /// When the question times out: true uses the highlighted stop, false keeps the file.
    @Published var downloadUnansweredUsesDefault: Bool { didSet { save(downloadUnansweredUsesDefault, Keys.downloadUnanswered) } }
    @Published var downloadTagTemporary: Bool { didSet { save(downloadTagTemporary, Keys.downloadTag) } }
    /// Remembered answers by file extension ("dmg" → "day"); these files are not asked about.
    @Published var downloadRules: [String: String] { didSet { defaults.set(downloadRules, forKey: Keys.downloadRules) } }
    /// Setup (pick a preset) has been seen; until then the Settings window opens on it at launch.
    @Published var setupCompleted: Bool { didSet { save(setupCompleted, Keys.setupCompleted) } }
    /// The preset last applied from Setup, for its selected state. Settings changed afterwards keep it.
    @Published var appliedPreset: String? { didSet { defaults.set(appliedPreset, forKey: Keys.appliedPreset) } }
    @Published var batteryEnabled: Bool { didSet { save(batteryEnabled, "batteryEnabled") } }
    @Published var accessoriesEnabled: Bool { didSet { save(accessoriesEnabled, "accessoriesEnabled") } }
    @Published var calendarEnabled: Bool { didSet { save(calendarEnabled, "calendarEnabled") } }
    @Published var agentsEnabled: Bool { didSet { save(agentsEnabled, "agentsEnabled") } }
    @Published var codexEnabled: Bool { didSet { save(codexEnabled, "codexEnabled") } }
    @Published var opencodeEnabled: Bool { didSet { save(opencodeEnabled, "opencodeEnabled") } }
    @Published var claudeUsageEnabled: Bool { didSet { save(claudeUsageEnabled, "claudeUsageEnabled") } }
    /// The user pressed Allow for reading Claude Code's sign-in from the keychain. Until then the
    /// keychain is never touched, so macOS never asks on its own.
    @Published var keychainAllowed: Bool { didSet { save(keychainAllowed, Keys.keychainAllowed) } }
    /// The user pressed Allow for Bluetooth. Until then IOBluetooth is never called, so the
    /// system prompt only appears when they ask for it.
    @Published var bluetoothAllowed: Bool { didSet { save(bluetoothAllowed, Keys.bluetoothAllowed) } }
    @Published var planUsageEnabled: Bool { didSet { save(planUsageEnabled, "planUsageEnabled") } }
    @Published var agentWings: Bool { didSet { save(agentWings, "agentWings") } }
    @Published var mirrorEnabled: Bool { didSet { save(mirrorEnabled, "mirrorEnabled") } }
    @Published var statsEnabled: Bool { didSet { save(statsEnabled, "statsEnabled") } }

    // MARK: Composition
    /// Tab order, including hidden tabs; unknown or missing tabs are appended.
    @Published var tabOrder: [String] { didSet { defaults.set(tabOrder, forKey: Keys.tabOrder) } }
    @Published var hiddenTabs: Set<String> { didSet { defaults.set(Array(hiddenTabs), forKey: Keys.hiddenTabs) } }
    /// Activity kinds (by name) the user switched off.
    @Published var disabledActivities: Set<String> { didSet { defaults.set(Array(disabledActivities), forKey: Keys.disabledActivities) } }
    /// Home rows in display order; rows not listed are hidden.
    @Published var homeRows: [String] { didSet { defaults.set(homeRows, forKey: Keys.homeRows) } }

    enum Keys {
        static let displayMode = "displayMode", openTrigger = "openTrigger"
        static let bodyStyle = "bodyStyle", tintHex = "tintHex", accentHex = "accentHex", bodyOpacity = "bodyOpacity"
        static let panelWidth = "panelWidth.v2", panelHeight = "panelHeight.v2", cornerScale = "cornerScale", shadow = "shadow"
        static let closedExtraWidth = "closedExtraWidth", activityWidthScale = "activityWidthScale.v2"
        static let animationSpeed = "animationSpeed", bounce = "bounce", hoverDelay = "hoverDelay", closeDelay = "closeDelay"
        static let staggerContent = "staggerContent"
        static let emissionIntensity = "emissionIntensity", glowNeedsYou = "glowNeedsYou", hideNotch = "hideNotch"
        static let paceWarnings = "paceWarnings", homeRows = "homeRows", usageShowsRemaining = "usageShowsRemaining"
        static let tabSwipe = "tabSwipe"
        static let hideOnFullscreen = "hideOnFullscreen", checkForUpdates = "checkForUpdates"
        static let sounds = "sounds", tabOrder = "tabOrder", hiddenTabs = "hiddenTabs", disabledActivities = "disabledActivities"
        static let widgetsTabAutomatic = "widgetsTabAutomatic"
        static let accentFollowsSystem = "accentFollowsSystem", clipboardShortcut = "clipboardShortcut"
        static let downloadCleanup = "downloadCleanup", downloadDefault = "downloadDefault", downloadUnanswered = "downloadUnansweredUsesDefault"
        static let downloadTag = "downloadTagTemporary", downloadRules = "downloadRules"
        static let setupCompleted = "setupCompleted", appliedPreset = "appliedPreset"
        static let keychainAllowed = "keychainAllowed", bluetoothAllowed = "bluetoothAllowed"
        static let shapeStyle = "shapeStyle", pillContent = "pillContent", use24Hour = "use24Hour"
        static let agentMarkMotion = "agentMarkMotion"
        static let islandSatellites = "islandSatellites", islandWidth = "islandWidth", islandHeight = "islandHeight", islandTop = "islandTop"
    }

    static let defaultHomeRows: [HomeRow] = [.keepAwake, .upNext, .timer, .system]

    static let factoryDefaults: [String: Any] = [
        Keys.emissionIntensity: 0.7, Keys.glowNeedsYou: true, Keys.hideNotch: false, Keys.paceWarnings: true,
        Keys.usageShowsRemaining: true, Keys.tabSwipe: true, Keys.hideOnFullscreen: true, Keys.checkForUpdates: true,
        Keys.panelWidth: 500.0, Keys.panelHeight: 148.0, Keys.closedExtraWidth: 0.0, Keys.activityWidthScale: 1.0,
        Keys.bodyOpacity: 1.0, Keys.cornerScale: 1.0, Keys.shadow: true,
        Keys.animationSpeed: 1.35, Keys.bounce: 0.12, Keys.hoverDelay: 0.04, Keys.closeDelay: 0.3, Keys.staggerContent: true,
        Keys.sounds: true, Keys.tintHex: 0x1C1B22, Keys.accentHex: 0x3DDBB0, Keys.accentFollowsSystem: false,
        Keys.clipboardShortcut: KeyShortcut.clipboardDefault.dictionary,
        Keys.downloadCleanup: true, Keys.downloadDefault: KeepChoice.day.rawValue, Keys.downloadUnanswered: false,
        Keys.downloadTag: false,
        Keys.shapeStyle: ShapeStyle.auto.rawValue, Keys.pillContent: PillContent.clock.rawValue, Keys.use24Hour: false,
        Keys.islandSatellites: true, Keys.islandWidth: 0.0, Keys.islandHeight: 0.0, Keys.islandTop: 2.0,
        "haptics": true, "showMenuBarIcon": true, "sayHello": true, "emissionEdge": true,
        "musicEnabled": true, "musicWings": true, "hudEnabled": true, "replaceSystemHUD": false,
        "trayEnabled": true, "clipboardEnabled": true, "screenshotsEnabled": true, "downloadsEnabled": true,
        "batteryEnabled": true, "accessoriesEnabled": true, "calendarEnabled": true, "agentsEnabled": true,
        "codexEnabled": true, "opencodeEnabled": true, "claudeUsageEnabled": true, "planUsageEnabled": true, "agentWings": true, "mirrorEnabled": false,
        "statsEnabled": true,
    ]

    /// A saved answer wins; without one, an install that finished Setup before consent existed
    /// keeps the access it already had, and a new install starts without it.
    nonisolated static func consent(stored: Bool?, alreadySetUp: Bool) -> Bool {
        stored ?? alreadySetUp
    }

    private init() {
        defaults.register(defaults: Self.factoryDefaults)
        // Migrate the old see-through switch.
        if defaults.object(forKey: Keys.bodyStyle) == nil, defaults.bool(forKey: "glassMode") {
            defaults.set(BodyStyle.glass.rawValue, forKey: Keys.bodyStyle)
        }
        displayMode = DisplayMode(rawValue: defaults.string(forKey: Keys.displayMode) ?? "") ?? .builtIn
        selectedDisplays = defaults.stringArray(forKey: "selectedDisplays") ?? []
        openTrigger = OpenTrigger(rawValue: defaults.string(forKey: Keys.openTrigger) ?? "") ?? .hover
        bodyStyle = BodyStyle(rawValue: defaults.string(forKey: Keys.bodyStyle) ?? "") ?? .black
        tintHex = defaults.integer(forKey: Keys.tintHex)
        accentHex = defaults.integer(forKey: Keys.accentHex)
        accentFollowsSystem = defaults.bool(forKey: Keys.accentFollowsSystem)
        clipboardShortcut = KeyShortcut(dictionary: defaults.dictionary(forKey: Keys.clipboardShortcut) ?? [:])
        bodyOpacity = defaults.double(forKey: Keys.bodyOpacity)
        cornerScale = defaults.double(forKey: Keys.cornerScale)
        shadow = defaults.bool(forKey: Keys.shadow)
        emissionIntensity = defaults.double(forKey: Keys.emissionIntensity)
        glowNeedsYou = defaults.bool(forKey: Keys.glowNeedsYou)
        hideNotch = defaults.bool(forKey: Keys.hideNotch)
        shapeStyle = ShapeStyle(rawValue: defaults.string(forKey: Keys.shapeStyle) ?? "") ?? .auto
        pillContent = PillContent(rawValue: defaults.string(forKey: Keys.pillContent) ?? "") ?? .clock
        agentMarkMotion = AgentMarkMotion(rawValue: defaults.string(forKey: Keys.agentMarkMotion) ?? "") ?? .still
        use24Hour = defaults.bool(forKey: Keys.use24Hour)
        islandSatellites = defaults.bool(forKey: Keys.islandSatellites)
        islandWidth = defaults.double(forKey: Keys.islandWidth)
        islandHeight = defaults.double(forKey: Keys.islandHeight)
        islandTop = defaults.double(forKey: Keys.islandTop)
        panelWidth = defaults.double(forKey: Keys.panelWidth)
        panelHeight = defaults.double(forKey: Keys.panelHeight)
        closedExtraWidth = defaults.double(forKey: Keys.closedExtraWidth)
        activityWidthScale = defaults.double(forKey: Keys.activityWidthScale)
        animationSpeed = defaults.double(forKey: Keys.animationSpeed)
        bounce = defaults.double(forKey: Keys.bounce)
        hoverDelay = defaults.double(forKey: Keys.hoverDelay)
        closeDelay = defaults.double(forKey: Keys.closeDelay)
        staggerContent = defaults.bool(forKey: Keys.staggerContent)
        paceWarnings = defaults.bool(forKey: Keys.paceWarnings)
        usageShowsRemaining = defaults.bool(forKey: Keys.usageShowsRemaining)
        tabSwipeEnabled = defaults.bool(forKey: Keys.tabSwipe)
        hideOnFullscreen = defaults.bool(forKey: Keys.hideOnFullscreen)
        checkForUpdates = defaults.bool(forKey: Keys.checkForUpdates)
        haptics = defaults.bool(forKey: "haptics")
        sounds = defaults.bool(forKey: Keys.sounds)
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        sayHello = defaults.bool(forKey: "sayHello")
        emissionEdge = defaults.bool(forKey: "emissionEdge")
        musicEnabled = defaults.bool(forKey: "musicEnabled")
        musicWings = defaults.bool(forKey: "musicWings")
        hudEnabled = defaults.bool(forKey: "hudEnabled")
        replaceSystemHUD = defaults.bool(forKey: "replaceSystemHUD")
        trayEnabled = defaults.bool(forKey: "trayEnabled")
        clipboardEnabled = defaults.bool(forKey: "clipboardEnabled")
        screenshotsEnabled = defaults.bool(forKey: "screenshotsEnabled")
        downloadsEnabled = defaults.bool(forKey: "downloadsEnabled")
        downloadCleanupEnabled = defaults.bool(forKey: Keys.downloadCleanup)
        downloadDefaultChoice = KeepChoice(rawValue: defaults.string(forKey: Keys.downloadDefault) ?? "") ?? .day
        downloadUnansweredUsesDefault = defaults.bool(forKey: Keys.downloadUnanswered)
        downloadTagTemporary = defaults.bool(forKey: Keys.downloadTag)
        downloadRules = defaults.dictionary(forKey: Keys.downloadRules) as? [String: String] ?? [:]
        setupCompleted = defaults.bool(forKey: Keys.setupCompleted)
        appliedPreset = defaults.string(forKey: Keys.appliedPreset)
        // Installs from before 1.3.1 already went through these prompts, so they keep working;
        // a new install asks nothing until the user presses Allow.
        // Saved right away: Setup marks itself done on the first launch, which must not grant these.
        let alreadySetUp = defaults.bool(forKey: Keys.setupCompleted)
        let keychain = Self.consent(stored: defaults.object(forKey: Keys.keychainAllowed) as? Bool, alreadySetUp: alreadySetUp)
        let bluetooth = Self.consent(stored: defaults.object(forKey: Keys.bluetoothAllowed) as? Bool, alreadySetUp: alreadySetUp)
        defaults.set(keychain, forKey: Keys.keychainAllowed)
        defaults.set(bluetooth, forKey: Keys.bluetoothAllowed)
        keychainAllowed = keychain
        bluetoothAllowed = bluetooth
        batteryEnabled = defaults.bool(forKey: "batteryEnabled")
        accessoriesEnabled = defaults.bool(forKey: "accessoriesEnabled")
        calendarEnabled = defaults.bool(forKey: "calendarEnabled")
        agentsEnabled = defaults.bool(forKey: "agentsEnabled")
        codexEnabled = defaults.bool(forKey: "codexEnabled")
        opencodeEnabled = defaults.bool(forKey: "opencodeEnabled")
        claudeUsageEnabled = defaults.bool(forKey: "claudeUsageEnabled")
        planUsageEnabled = defaults.bool(forKey: "planUsageEnabled")
        agentWings = defaults.bool(forKey: "agentWings")
        mirrorEnabled = defaults.bool(forKey: "mirrorEnabled")
        statsEnabled = defaults.bool(forKey: "statsEnabled")
        tabOrder = defaults.stringArray(forKey: Keys.tabOrder) ?? NotchTab.allCases.map(\.rawValue)
        var hidden = Set(defaults.stringArray(forKey: Keys.hiddenTabs) ?? Self.defaultHiddenTabs)
        // The Widgets tab now appears by itself once a widget exists, so the old default hiding
        // (1.2.1) is dropped once; the user can still hide it again.
        if !defaults.bool(forKey: Keys.widgetsTabAutomatic) {
            hidden.remove(NotchTab.widgets.rawValue)
            defaults.set(true, forKey: Keys.widgetsTabAutomatic)
            defaults.set(Array(hidden), forKey: Keys.hiddenTabs)
        }
        hiddenTabs = hidden
        disabledActivities = Set(defaults.stringArray(forKey: Keys.disabledActivities) ?? [])
        homeRows = defaults.stringArray(forKey: Keys.homeRows) ?? Self.defaultHomeRows.map(\.rawValue)
        observeSystemAccent()
    }

    private func observeSystemAccent() {
        // Both observers are delivered on the main queue.
        let refresh: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { Preferences.shared.systemAccent = Preferences.currentSystemAccent() }
        }
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main, using: refresh)
        DistributedNotificationCenter.default().addObserver(forName: Self.accentChangedNotification, object: nil, queue: .main, using: refresh)
    }

    private static let accentChangedNotification = Notification.Name("AppleColorPreferencesChangedNotification")

    /// A fixed sRGB copy of the dynamic system accent, so views compare and animate it as a value.
    static func currentSystemAccent() -> Color {
        Color(nsColor: NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor)
    }

    private func save(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: Derived

    var accent: Color { accentFollowsSystem ? systemAccent : Color(hex: UInt32(accentHex)) }
    var tint: Color { Color(hex: UInt32(tintHex)) }

    /// Tabs in the user's order, hidden and disabled ones removed.
    var orderedTabs: [NotchTab] {
        allTabsOrdered.filter { !hiddenTabs.contains($0.rawValue) && isFeatureEnabled($0) }
    }

    /// All tabs in order, for the settings editor.
    var allTabsOrdered: [NotchTab] {
        var order = tabOrder.compactMap(NotchTab.init(rawValue:))
        // A tab added in an update lands next to its neighbor in the default order, not at the end.
        for (index, tab) in NotchTab.allCases.enumerated() where !order.contains(tab) {
            let previous = NotchTab.allCases[..<index].last { order.contains($0) }
            order.insert(tab, at: previous.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        }
        return order
    }

    func moveTab(_ tab: NotchTab, by offset: Int) {
        var order = allTabsOrdered.map(\.rawValue)
        guard let index = order.firstIndex(of: tab.rawValue) else { return }
        let target = max(0, min(order.count - 1, index + offset))
        guard target != index else { return }
        order.remove(at: index)
        order.insert(tab.rawValue, at: target)
        withAnimation(Motion.state) { tabOrder = order }
    }

    /// Every tab shows by default; the Widgets tab still waits for its first widget.
    static let defaultHiddenTabs: [String] = []

    var visibleHomeRows: [HomeRow] { homeRows.compactMap(HomeRow.init(rawValue:)) }

    func setHomeRow(_ row: HomeRow, visible: Bool) {
        withAnimation(Motion.state) {
            if visible, !homeRows.contains(row.rawValue) {
                // Keep the canonical order when a row comes back.
                homeRows = HomeRow.allCases.map(\.rawValue).filter { homeRows.contains($0) || $0 == row.rawValue }
            } else if !visible {
                homeRows.removeAll { $0 == row.rawValue }
            }
        }
    }

    func isFeatureEnabled(_ tab: NotchTab) -> Bool {
        switch tab {
        case .home, .recent, .controls: true
        // Only once an agent (or the user) has added a widget file.
        case .widgets: !WidgetStore.shared.widgets.isEmpty
        case .agents: agentsEnabled
        case .tray: trayEnabled
        case .clipboard: clipboardEnabled
        case .downloads: downloadsEnabled && downloadCleanupEnabled
        case .mirror: mirrorEnabled
        }
    }

    func isActivityEnabled(_ kind: ActivityKind) -> Bool {
        !disabledActivities.contains(kind.name)
    }

    func setActivity(_ kind: ActivityKind, enabled: Bool) {
        if enabled { disabledActivities.remove(kind.name) } else { disabledActivities.insert(kind.name) }
    }

    func apply(_ preset: MotionPreset) {
        let values = preset.values
        withAnimation(Motion.state) {
            animationSpeed = values.speed
            bounce = values.bounce
            hoverDelay = values.hover
        }
    }

    /// Restores look, size, motion and composition settings (feature switches are kept).
    func resetCustomization() {
        let keys = [
            Keys.bodyStyle, Keys.tintHex, Keys.accentHex, Keys.accentFollowsSystem, Keys.bodyOpacity, Keys.panelWidth, Keys.panelHeight,
            Keys.closedExtraWidth, Keys.activityWidthScale, Keys.cornerScale, Keys.shadow, Keys.animationSpeed,
            Keys.bounce, Keys.hoverDelay, Keys.closeDelay, Keys.staggerContent, Keys.emissionIntensity,
            Keys.tabOrder, Keys.hiddenTabs, Keys.disabledActivities, Keys.homeRows,
            Keys.shapeStyle, Keys.pillContent, Keys.islandSatellites, Keys.islandWidth, Keys.islandHeight, Keys.islandTop,
        ]
        keys.forEach(defaults.removeObject(forKey:))
        withAnimation(Motion.state) {
            bodyStyle = .black
            tintHex = defaults.integer(forKey: Keys.tintHex)
            accentHex = defaults.integer(forKey: Keys.accentHex)
            accentFollowsSystem = false
            bodyOpacity = defaults.double(forKey: Keys.bodyOpacity)
            panelWidth = defaults.double(forKey: Keys.panelWidth)
            panelHeight = defaults.double(forKey: Keys.panelHeight)
            closedExtraWidth = defaults.double(forKey: Keys.closedExtraWidth)
            activityWidthScale = defaults.double(forKey: Keys.activityWidthScale)
            cornerScale = defaults.double(forKey: Keys.cornerScale)
            shadow = defaults.bool(forKey: Keys.shadow)
            animationSpeed = defaults.double(forKey: Keys.animationSpeed)
            bounce = defaults.double(forKey: Keys.bounce)
            hoverDelay = defaults.double(forKey: Keys.hoverDelay)
            closeDelay = defaults.double(forKey: Keys.closeDelay)
            staggerContent = defaults.bool(forKey: Keys.staggerContent)
            emissionIntensity = defaults.double(forKey: Keys.emissionIntensity)
            tabOrder = NotchTab.allCases.map(\.rawValue)
            hiddenTabs = Set(Self.defaultHiddenTabs)
            disabledActivities = []
            homeRows = Self.defaultHomeRows.map(\.rawValue)
            shapeStyle = .auto
            pillContent = .clock
            islandSatellites = defaults.bool(forKey: Keys.islandSatellites)
            islandWidth = defaults.double(forKey: Keys.islandWidth)
            islandHeight = defaults.double(forKey: Keys.islandHeight)
            islandTop = defaults.double(forKey: Keys.islandTop)
        }
    }
}

extension ActivityKind {
    var name: String { String(describing: self) }

    var title: String {
        switch self {
        case .hello: "Hello at login"
        case .needsYou: "Agent needs you"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .timerFinished: "Timer finished"
        case .usageWarning: "Usage limit warning"
        case .custom: "From your scripts and widgets"
        case .agentDone: "Agent finished"
        case .downloadKeep: "Keep new download for…"
        case .downloadDone: "Download finished"
        case .downloadTrashed: "Download moved to Trash"
        case .downloadExpiring: "Download about to expire"
        case .charging: "Charging"
        case .lowBattery: "Low battery"
        case .accessory: "Devices and connections"
        case .screenshot: "Screenshot"
        case .trayAdded: "Added to Tray"
        case .meetingSoon: "Meeting starting"
        case .download: "Download progress"
        case .timer: "Running timer"
        case .agentRunning: "Agent running"
        case .music: "Now playing"
        }
    }
}
