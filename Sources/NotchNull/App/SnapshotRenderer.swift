import AppKit
import SwiftUI

/// `NotchNull --snapshots <dir>` renders every notch state to PNG with synthetic fixture data,
/// for visual review without triggering real system events. Fixture values are demo data only.
@MainActor
enum SnapshotRenderer {
    /// With `transparent`, the wallpaper and menu bar are left out (for compositing on the website).
    static func renderAll(to directory: URL, transparent: Bool = false) {
        self.transparent = transparent
        Motion.isSnapshot = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let services = AppServices()
        seed(services)
        let geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchSize: CGSize(width: 185, height: 32),
            hasHardwareNotch: true
        )

        typealias State = (name: String, phase: NotchViewModel.Phase, tab: NotchTab)
        var states: [State] = [
            ("00-closed", .closed, .home),
            ("10-open-home", .open, .home),
            ("11-open-agents", .open, .agents),
            ("12-open-tray", .open, .tray),
            ("13-open-clipboard", .open, .clipboard),
            ("14-open-mirror", .open, .mirror),
            ("15-open-controls", .open, .controls),
            ("16-open-downloads", .open, .downloads),
            ("17-open-widgets", .open, .widgets),
            ("18-open-recent", .open, .recent),
            ("20-drop", .drop, .home),
        ]
        for kind in ActivityKind.allCases {
            states.append(("3\(String(format: "%02d", kind.rawValue))-activity-\(kind)", .activity(kind), .home))
        }
        // The same panels at a roomy size, and a wider closed notch.
        let large: [State] = [("50-large-home", .open, .home), ("51-large-agents", .open, .agents), ("52-large-controls", .open, .controls)]
        let medium: [State] = [("40-medium-home", .open, .home), ("41-medium-agents", .open, .agents), ("42-medium-controls", .open, .controls)]
        let wideClosed: [State] = [("60-wide-closed", .closed, .home), ("61-wide-music", .activity(.music), .home), ("62-wide-volume", .activity(.volume), .home)]

        let preferences = Preferences.shared
        let saved = (preferences.panelWidth, preferences.panelHeight, preferences.closedExtraWidth)
        render(states, geometry: geometry, services: services, to: directory)
        preferences.panelWidth = 540
        preferences.panelHeight = 172
        render(medium, geometry: geometry, services: services, to: directory)
        preferences.panelWidth = 680
        preferences.panelHeight = 200
        render(large, geometry: geometry, services: services, to: directory)
        (preferences.panelWidth, preferences.panelHeight) = (saved.0, saved.1)
        preferences.closedExtraWidth = 90
        render(wideClosed, geometry: geometry, services: services, to: directory)
        preferences.closedExtraWidth = saved.2
        // A screen without a hardware notch (or a MacBook at a resolution that leaves it out): the island.
        let islandGeometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1125),
            notchSize: CGSize(width: Theme.Size.virtualNotch.width, height: 30),
            hasHardwareNotch: false
        )
        let island: [State] = [
            ("90-island-closed", .closed, .home), ("91-island-music", .activity(.music), .home),
            ("92-island-needs-you", .activity(.needsYou), .home), ("93-island-timer", .activity(.timer), .home),
            ("94-island-open-home", .open, .home), ("95-island-open-controls", .open, .controls),
            ("96-island-download-keep", .activity(.downloadKeep), .home), ("89-island-volume", .activity(.volume), .home),
        ]
        render(island, geometry: islandGeometry, services: services, to: directory)
        // Hovering a satellite grows it into its card.
        render([("98-island-media-card", .closed, .home)], geometry: islandGeometry, services: services, to: directory, satellite: .leading)
        render([("99-island-controls-card", .closed, .home)], geometry: islandGeometry, services: services, to: directory, satellite: .trailing)
        let savedContent = preferences.pillContent
        preferences.pillContent = .dateClock
        render([("97-island-date-clock", .closed, .home)], geometry: islandGeometry, services: services, to: directory)
        preferences.pillContent = savedContent
        services.devices.preview(DeviceEvent(change: .connected, name: "ESP32 / CP210x board", symbol: "cpu", detail: "/dev/cu.usbserial-0001"))
        render([("70-device-serial", .activity(.accessory), .home)], geometry: geometry, services: services, to: directory)
        services.devices.preview(DeviceEvent(change: .disconnected, name: "JBL LIVE660NC", symbol: "headphones", detail: "Bluetooth"))
        render([("71-device-disconnected", .activity(.accessory), .home)], geometry: geometry, services: services, to: directory)
        // Claude and Codex running together: both marks overlap in the wing.
        services.agents.sessions.upsert(id: "d", provider: .claude) {
            $0.cwd = "/Users/demo/docs"
            $0.status = .running
            $0.turnStartedAt = Date().addingTimeInterval(-75)
        }
        render([("72-agents-both-running", .activity(.agentRunning), .home)], geometry: geometry, services: services, to: directory)
        // Two agents asking at once stack in one banner, a row each.
        services.agents.sessions.upsert(id: "b", provider: .codex) {
            $0.status = .needsYou(ClaudeHookHandler.describePermission(["tool_name": "AskUserQuestion", "tool_input": ["questions": [["question": "Should the API keep v1 routes during the migration?"]]]]))
        }
        render([("75-needs-you-stacked", .activity(.needsYou), .home)], geometry: geometry, services: services, to: directory)
        render([("76-island-needs-you-stacked", .activity(.needsYou), .home)], geometry: islandGeometry, services: services, to: directory)
        // Clipboard opened with the shortcut, second tile highlighted from the keyboard.
        services.clipboardPicker.begin()
        services.clipboardPicker.move(.right, itemCount: services.clipboard.items.count)
        render([("73-open-clipboard-keyboard", .open, .clipboard)], geometry: geometry, services: services, to: directory)
        services.clipboardPicker.end()
        // Without the deploy banner, the CI widget's wing (it has a failing check) owns the notch.
        CustomActivityStore.shared.remove(id: "deploy")
        render([("74-widget-wing", .activity(.custom), .home)], geometry: geometry, services: services, to: directory)
        renderSettingsPage("80-settings-build", services: services, to: directory) { BuildSettings() }
        renderSettingsPage("81-settings-setup", services: services, to: directory) { SetupSettings() }
        renderSettingsPage("82-settings-style", services: services, to: directory) { StyleSettings() }
        renderSettingsPage("85-settings-displays", services: services, to: directory) { DisplaySettings() }
        renderSettingsPage("83-settings-about", services: services, to: directory) { AboutSettings() }
        if let next = AppVersion("\(AppVersion.current.parts.first ?? 0).99.0") {
            services.updates.preview(.available(.init(version: next, page: Constants.Links.releases, asset: Constants.Links.releases, sha256: nil)))
            renderSettingsPage("84-settings-about-update", services: services, to: directory) { AboutSettings() }
            services.updates.preview(.idle)
        }
        let count: Int = [states.count, medium.count, large.count, wideClosed.count, island.count, 9].reduce(0, +)
        print("Rendered \(count) snapshots to \(directory.path)")
    }

    private static var transparent = false

    enum RenderError: LocalizedError {
        case drawFailed
        case noWing
        var errorDescription: String? {
            switch self {
            case .drawFailed: "The view could not be drawn."
            case .noWing: "No wing is up: no widget's wing.when is true with its current data."
            }
        }
    }

    /// `notchnull render`: one PNG of the notch with the user's live settings.json and widgets
    /// (commands run once), cropped to the body. `demo` fills music, agents and the rest with
    /// fixture data so the whole look can be judged.
    static func renderLive(to url: URL, phase: NotchViewModel.Phase, tab: NotchTab, demo: Bool, fullCanvas: Bool, transparent: Bool = false) throws {
        Motion.isSnapshot = true
        let services = AppServices()
        if demo { seed(services) }
        if let data = try? Data(contentsOf: NotchHome.settings) { SettingsFile.shared.apply(data) }
        WidgetStore.shared.loadSynchronously()
        if phase == .activity(.custom), CustomActivityStore.shared.current == nil { throw RenderError.noWing }
        let screen = NSScreen.screens.first(where: NotchGeometry.isBuiltIn) ?? NSScreen.main
        let geometry = screen.map(NotchGeometry.init(screen:)).map {
            NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: $0.notchSize, hasHardwareNotch: $0.hasHardwareNotch)
        } ?? NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true)
        let model = NotchViewModel(geometry: geometry, center: ActivityCenter())
        model.preview(phase: phase, tab: tab)
        let view = SnapshotStage(transparent: transparent) {
            NotchRootView()
                .environmentObject(model)
                .withServices(services)
        }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard var image = renderer.cgImage else { throw RenderError.drawFailed }
        if !fullCanvas {
            // The body plus a margin, so the picture is about the notch and not the wallpaper.
            let size = model.shapeSize
            let width = min(Theme.Size.canvas.width, size.width + 80)
            let height = min(Theme.Size.canvas.height, size.height + 36)
            let crop = CGRect(x: (Theme.Size.canvas.width - width) / 2 * 2, y: 0, width: width * 2, height: height * 2)
            image = image.cropping(to: crop) ?? image
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.drawFailed }
        try png.write(to: url)
    }

    /// One Settings section at the window's content width, on the window's background.
    private static func renderSettingsPage<Page: View>(_ name: String, services: AppServices, to directory: URL, @ViewBuilder page: () -> Page) {
        let view = VStack(alignment: .leading, spacing: 18) { page() }
            .padding(28)
            .frame(width: 560, alignment: .topLeading)
            .background(Color(hex: 0x111214))
            .environment(\.colorScheme, .dark)
            .withServices(services)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private static func render(
        _ states: [(name: String, phase: NotchViewModel.Phase, tab: NotchTab)],
        geometry: NotchGeometry, services: AppServices, to directory: URL,
        satellite: NotchViewModel.SatelliteSide? = nil
    ) {
        for (name, phase, tab) in states {
            let model = NotchViewModel(geometry: geometry, center: ActivityCenter())
            model.preview(phase: phase, tab: tab, satellite: satellite)
            let view = SnapshotStage(transparent: transparent) {
                NotchRootView()
                    .environmentObject(model)
                    .withServices(services)
            }
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    private static func seed(_ services: AppServices) {
        let now = Date()
        services.nowPlaying.preview(
            NowPlaying(title: "Afterglow", artist: "Sunset Grid", album: "Night Drive", duration: 214, position: 71, sampledAt: now, isPlaying: true, trackID: "demo", bundleID: "com.apple.Music", sourceName: "Music"),
            artwork: DemoArt.synthwave(),
            tint: Color(hex: 0xFF6FA8)
        )
        services.levels.preview(.init(kind: .volume, value: 0.63, muted: false))
        services.agents.claudeUsage.preview(ProviderUsage(
            provider: .claude, plan: "Max",
            windows: [
                UsageWindow(id: "session", label: "5 hours", percent: 42, resetsAt: now.addingTimeInterval(2.1 * 3600), duration: 5 * 3600),
                UsageWindow(id: "weekly_all", label: "Week", percent: 18, resetsAt: now.addingTimeInterval(3.2 * 86_400), duration: 7 * 86_400),
            ],
            breakdown: [UsageShare(id: "claude_code", label: "Claude Code", percent: 92), UsageShare(id: "chat", label: "Chats", percent: 8)],
            updatedAt: now, state: .ready
        ))
        var claudeTokens = TokenTally()
        claudeTokens.today = 18_420_000
        claudeTokens.output = 412_000
        claudeTokens.messages = 812
        claudeTokens.hourly = [0, 0, 0, 0, 0, 0, 0, 0, 2, 5, 9, 12, 7, 4, 11, 16, 13, 8, 3, 0, 0, 0, 0, 0].map { $0 * 90_000 }
        services.agents.claudeTokens.preview(claudeTokens)
        var codexTokens = TokenTally()
        codexTokens.today = 3_100_000
        codexTokens.hourly = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 2, 0, 0, 4, 6, 2, 1, 0, 0, 0, 0, 0, 0].map { $0 * 100_000 }
        services.agents.codex.preview(
            usage: ProviderUsage(
                provider: .codex, plan: "Pro",
                windows: [
                    UsageWindow(id: "primary", label: "5 hours", percent: 71, resetsAt: now.addingTimeInterval(3.8 * 3600), duration: 5 * 3600),
                    UsageWindow(id: "secondary", label: "Week", percent: 9, resetsAt: now.addingTimeInterval(4.5 * 86_400), duration: 7 * 86_400),
                ],
                updatedAt: now.addingTimeInterval(-240), state: .ready
            ),
            tokens: codexTokens
        )
        var opencodeTokens = TokenTally()
        opencodeTokens.today = 1_240_000
        opencodeTokens.output = 96_000
        opencodeTokens.messages = 148
        opencodeTokens.hourly = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 4, 6, 3, 2, 5, 1, 0, 0, 0, 0, 0, 0, 0].map { $0 * 40_000 }
        services.agents.opencode.preview(
            usage: ProviderUsage(
                provider: .opencode, plan: "build • big-pickle",
                updatedAt: now.addingTimeInterval(-90), state: .ready
            ),
            tokens: opencodeTokens
        )
        services.agents.plans.preview([
            PlanUsage(
                id: "zai", title: "GLM Coding Plan", monogram: "Z", tint: Theme.Accent.glm, source: "Claude Code settings", plan: "Pro",
                windows: [
                    UsageWindow(id: "zai-300", label: "5 hours", percent: 23, resetsAt: now.addingTimeInterval(1.4 * 3600), duration: 5 * 3600),
                    UsageWindow(id: "zai-mcp", label: "MCP", percent: 6, resetsAt: now.addingTimeInterval(17 * 86_400), duration: 30 * 86_400),
                ],
                updatedAt: now, state: .ready
            ),
            PlanUsage(
                id: "kimi", title: "Kimi Code", monogram: "K", tint: Theme.Accent.kimi, source: "OpenCode", plan: "Allegretto",
                windows: [UsageWindow(id: "kimi-limit_7d", label: "Week", percent: 64, resetsAt: now.addingTimeInterval(2 * 86_400), duration: 7 * 86_400)],
                updatedAt: now, state: .ready
            ),
        ])
        services.agents.preview(
            warning: .init(provider: "Codex", window: UsageWindow(id: "primary", label: "5 hours", percent: 82, resetsAt: now.addingTimeInterval(3.1 * 3600), duration: 5 * 3600)),
            hooksInstalled: true
        )
        let store = services.agents.sessions
        store.upsert(id: "a", provider: .claude) {
            $0.cwd = "/Users/demo/web-app"
            $0.status = .running
            $0.terminalBundleID = "com.apple.Terminal"
        }
        store.upsert(id: "a", provider: .claude) { $0.status = .needsYou("Wants to edit TourViews.swift") }
        store.upsert(id: "b", provider: .codex) {
            $0.cwd = "/Users/demo/api-server"
            $0.status = .running
            $0.turnStartedAt = now.addingTimeInterval(-192)
        }
        store.upsert(id: "c", provider: .claude) {
            $0.cwd = "/Users/demo/landing"
            $0.status = .running
            $0.turnStartedAt = now.addingTimeInterval(-252)
        }
        store.upsert(id: "c", provider: .claude) {
            $0.status = .done
            $0.detail = "Added the pricing section and fixed the mobile nav"
        }
        store.upsert(id: "d", provider: .opencode) {
            $0.cwd = "/Users/demo/opencode-app"
            $0.status = .running
            $0.detail = "Refactoring the theme loader"
            $0.origin = "build • big-pickle"
            $0.turnStartedAt = now.addingTimeInterval(-96)
        }
        services.battery.preview(BatteryState(percent: 82, isCharging: true, isPluggedIn: true, isCharged: false, minutesToEmpty: nil, minutesToFull: 38, hasBattery: true))
        let airpods = AccessoryInfo(id: "demo", name: "AirPods Pro", symbol: "airpodspro", left: 84, right: 80, caseLevel: 62)
        services.accessories.preview(airpods)
        services.devices.preview(DeviceEvent(change: .connected, name: "AirPods Pro", symbol: "airpodspro", accessory: airpods))
        services.calendar.preview([
            UpcomingEvent(id: "e1", title: "Standup", start: now.addingTimeInterval(4 * 60 + 20), end: now.addingTimeInterval(1800), calendarColor: Theme.Accent.calendar, meetingURL: URL(string: "https://meet.google.com/demo"), location: "Google Meet"),
        ])
        services.timer.start(25 * 60)
        services.stats.preview(SystemSnapshot(cpu: 0.18, memoryUsed: 7.4e9, memoryTotal: 16e9, downloadRate: 1.2e6, uploadRate: 90_000, diskFree: 212e9))
        services.downloads.preview(
            active: [ActiveDownload(id: "d", name: "Xcode_26.dmg", bytes: 4_300_000_000, total: 4_900_000_000, bytesPerSecond: 24_000_000, updatedAt: now)],
            finished: URL(fileURLWithPath: "/Users/demo/Downloads/launch-poster.jpg")
        )
        func demoDownload(_ name: String, source: String, size: Int64, expiresIn: TimeInterval?) -> TrackedDownload {
            TrackedDownload(id: UUID(), name: name, bookmark: Data(), addedAt: now, size: size, source: source, expiresAt: expiresIn.map { now.addingTimeInterval($0) })
        }
        let downloadsFolder = URL(fileURLWithPath: "/Users/demo/Downloads")
        services.cleanup.preview(
            pending: [demoDownload("Figma-126.3.dmg", source: "figma.com", size: 312_000_000, expiresIn: nil),
                      demoDownload("invoice-0924.pdf", source: "stripe.com", size: 184_000, expiresIn: nil)],
            expiring: [demoDownload("esp32-firmware.bin", source: "github.com", size: 1_240_000, expiresIn: 24),
                       demoDownload("wallpaper-dune.jpg", source: "unsplash.com", size: 6_800_000, expiresIn: 42 * 60),
                       demoDownload("dataset-q3.zip", source: "drive.google.com", size: 88_000_000, expiresIn: 2 * 86_400 + 3 * 3600)],
            trashed: TrashedDownload(name: "Zoom-installer.pkg", original: downloadsFolder.appendingPathComponent("Zoom-installer.pkg"),
                                     trashed: URL(fileURLWithPath: "/Users/demo/.Trash/Zoom-installer.pkg"), at: now)
        )
        let shot = DemoArt.screenshot()
        services.screenshots.preview(url: URL(fileURLWithPath: "/Users/demo/Desktop/Screenshot 2026-09-28 at 9.41.12.png"), image: shot)
        services.controls.preview(
            wifi: "Atlantis 5G", bluetooth: true, dark: true,
            outputs: [
                AudioOutputDevice(id: 1, name: "MacBook Pro Speakers", symbol: "laptopcomputer"),
                AudioOutputDevice(id: 2, name: "AirPods Pro", symbol: "airpodspro"),
            ]
        )
        services.log.add(symbol: "checkmark.circle.fill", tint: Theme.Accent.success, title: "landing finished", detail: "Added the pricing section")
        services.log.add(symbol: "arrow.down.circle.fill", tint: Theme.Accent.download, title: "Downloaded", detail: "launch-poster.jpg")
        services.log.add(symbol: "camera.viewfinder", tint: Theme.Accent.tray, title: "Screenshot saved to Tray", detail: "Screenshot 2026-09-30 at 10.12.png")
        services.log.add(symbol: "timer", tint: Theme.Accent.timer, title: "Focus finished", detail: "25:00")
        services.log.add(symbol: "video.fill", tint: Theme.Accent.calendar, title: "Design sync", detail: "Starts 11:00 AM")
        let lorem = ["npm run build && npm run test -- --watch=false", "https://developer.apple.com/documentation/swiftui", "#FF5E8A", "Meeting notes: ship the tray, polish the HUD, write docs"]
        services.clipboard.preview(lorem.enumerated().map { index, text in
            ClipItem(
                id: UUID(), kind: ClipboardService.isColor(text) ? .color : (text.hasPrefix("http") ? .link : .text),
                text: text, sourceApp: ["Terminal", "Safari", "Figma", "Notes"][index],
                date: now.addingTimeInterval(Double(-index) * 400), pinned: index == 3
            )
        })
        seedWidgets(now: now)
    }

    /// Three widget files as an agent would write them, with their command output already in.
    private static func seedWidgets(now: Date) {
        let files: [(id: String, json: String, data: String)] = [
            ("ci", """
            {"title": "CI", "symbol": "checkmark.seal.fill", "tint": "green", "size": "medium",
             "view": {"type": "column", "spacing": 6, "children": [
               {"type": "row", "children": [
                 {"type": "value", "value": "{{data.passing}}", "unit": "/{{data.total}}", "label": "checks passing", "style": "small"},
                 {"type": "spacer"},
                 {"type": "gauge", "value": "{{data.ratio}}", "size": 40}]},
               {"type": "list", "items": "{{data.failing}}", "limit": 2, "item":
                 {"type": "row", "children": [
                   {"type": "symbol", "name": "xmark.circle.fill", "size": 10, "color": "red"},
                   {"type": "text", "text": "{{item}}", "style": "caption", "color": "secondary"}]}}]},
             "wing": {"when": "{{data.failing | count}}", "symbol": "xmark.seal.fill", "tint": "red", "trailingText": "{{data.failing | count}} failing"}}
            """, #"{"passing": 11, "total": 12, "ratio": 0.92, "failing": ["e2e / checkout"]}"#),
            ("focus", """
            {"title": "Deep work", "symbol": "brain.head.profile", "tint": "purple", "size": "small",
             "view": {"type": "column", "spacing": 4, "children": [
               {"type": "value", "value": "{{data.hours}}", "unit": "h", "label": "today"},
               {"type": "bar", "value": "{{data.goal}}", "color": "purple"}]}}
            """, #"{"hours": 3.4, "goal": 0.68}"#),
            ("traffic", """
            {"title": "Visitors", "symbol": "chart.xyaxis.line", "tint": "sky", "size": "medium",
             "view": {"type": "column", "spacing": 6, "children": [
               {"type": "row", "children": [
                 {"type": "value", "value": "{{data.now}}", "label": "on the site now", "style": "small"},
                 {"type": "spacer"},
                 {"type": "badge", "text": "+{{data.change | percent}}", "color": "green"}]},
               {"type": "sparkline", "values": "{{data.series}}", "height": 26}]}}
            """, #"{"now": 214, "change": 0.18, "series": [80, 96, 90, 120, 142, 130, 168, 190, 176, 214]}"#),
        ]
        let widgets = files.compactMap { file -> LoadedWidget? in
            let url = NotchHome.widgets.appendingPathComponent("\(file.id).json")
            guard let json = JSONValue.parse(Data(file.json.utf8)),
                  let definition = try? WidgetDefinition(file: url, json: json) else { return nil }
            return LoadedWidget(id: file.id, file: url, definition: definition, state: .ready(WidgetStore.data(from: file.data), now))
        }
        WidgetStore.shared.preview(widgets)
        let banner = JSONValue.parse(Data(#"{"id": "deploy", "symbol": "paperplane.fill", "tint": "accent", "title": "Deploying landing", "subtitle": "vercel · production", "progress": 0.64, "persistent": true}"#.utf8))
        if let activity = banner.flatMap(CustomActivity.init(payload:)) { CustomActivityStore.shared.set(activity) }
    }
}

/// Wallpaper and menu bar behind the notch so snapshots read like the real screen.
private struct SnapshotStage<Content: View>: View {
    var transparent = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            if !transparent {
                SnapshotWallpaper()
                SnapshotMenuBar()
            }
            content
        }
        .frame(width: Theme.Size.canvas.width, height: Theme.Size.canvas.height)
    }
}

/// A plain graphite wallpaper: neutral, so nothing competes with the notch. The README's pictures
/// put the same transparent renders on a photo instead (scripts/readme-images.py).
private struct SnapshotWallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x2E2F33), Color(hex: 0x18191B)], startPoint: .top, endPoint: .bottom)
            .frame(width: Theme.Size.canvas.width, height: Theme.Size.canvas.height)
    }
}

/// A plain menu bar: an app menu on the left and the clock on the right, like a real screen.
private struct SnapshotMenuBar: View {
    var body: some View {
        HStack(spacing: 18) {
            Text("Terminal").fontWeight(.bold)
            // Short enough that the island's music card never lands on a menu title.
            ForEach(["Shell", "Edit"], id: \.self) { Text($0) }
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "magnifyingglass")
            // The island pill shows the real time, so the menu bar clock matches it.
            Text(Date(), format: .dateTime.weekday(.abbreviated).hour().minute())
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 20)
        .frame(height: 32)
        .background(Color.white.opacity(0.08))
    }
}

/// Synthetic artwork for fixtures.
enum DemoArt {
    static func synthwave(size: CGFloat = 200) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSGradient(colors: [NSColor(hex: 0x1B0B3A), NSColor(hex: 0x7B1E6B), NSColor(hex: 0xFF7A59)])?.draw(in: rect, angle: -90)
            let sun = NSRect(x: rect.midX - size * 0.26, y: size * 0.34, width: size * 0.52, height: size * 0.52)
            NSGradient(colors: [NSColor(hex: 0xFFD36E), NSColor(hex: 0xFF4F9A)])?.draw(in: NSBezierPath(ovalIn: sun), angle: -90)
            NSColor(hex: 0x1B0B3A).setFill()
            NSRect(x: 0, y: 0, width: size, height: size * 0.36).fill()
            NSColor(hex: 0xFF4FD8, alpha: 0.8).setStroke()
            for index in 0..<7 {
                let y = size * 0.36 * pow(Double(index) / 7, 1.8)
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 0, y: y))
                line.line(to: NSPoint(x: size, y: y))
                line.lineWidth = 1
                line.stroke()
            }
            for index in -6...6 {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: rect.midX + CGFloat(index) * 6, y: size * 0.36))
                line.line(to: NSPoint(x: rect.midX + CGFloat(index) * 40, y: 0))
                line.lineWidth = 1
                line.stroke()
            }
            return true
        }
    }

    static func screenshot() -> NSImage {
        NSImage(size: NSSize(width: 320, height: 200), flipped: false) { rect in
            NSColor(hex: 0xF4F4F6).setFill()
            rect.fill()
            NSColor(hex: 0xE2E2E6).setFill()
            NSRect(x: 0, y: rect.height - 22, width: rect.width, height: 22).fill()
            NSColor(hex: 0x2B2B30).setFill()
            NSRect(x: 20, y: 140, width: 160, height: 12).fill()
            NSColor(hex: 0xCACAD0).setFill()
            for row in 0..<4 { NSRect(x: 20, y: 110 - row * 16, width: 240, height: 6).fill() }
            NSColor(hex: 0xBBD5F7).setFill()
            NSRect(x: 20, y: 20, width: 200, height: 30).fill()
            return true
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
