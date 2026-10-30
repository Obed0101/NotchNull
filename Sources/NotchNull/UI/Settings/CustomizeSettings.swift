import AppKit
import SwiftUI

// MARK: Style

struct StyleSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var displays = NotchDisplay.connected

    private static let accentSwatches: [Int] = [0x3DDBB0, 0x5AC8FA, 0xA78BFA, 0xFF5E8A, 0xFF9F0A, 0xFFD60A, 0x30D158, 0xFFFFFF]
    private static let tintSwatches: [Int] = [0x1C1B22, 0x10213A, 0x2A1433, 0x1E2A1F, 0x2B1A12, 0x2A2A2E]

    /// Whether the built-in screen shows its hardware notch at the current resolution.
    private var screenHasNotch: Bool {
        let screen = NSScreen.screens.first(where: NotchGeometry.isBuiltIn) ?? NSScreen.main
        return screen.map { NotchGeometry(screen: $0).hasHardwareNotch } ?? false
    }

    private var islandInUse: Bool {
        switch preferences.shapeStyle {
        case .auto: !screenHasNotch
        case .notch: false
        case .island: true
        }
    }

    /// The island's own knobs are global, so they show whenever any screen can use them.
    private var showsIslandSettings: Bool {
        preferences.shapeStyle != .notch || eligibleDisplays.contains(where: resolvedIsland)
    }

    /// Screens that currently get a panel, in the order macOS reports them.
    private var eligibleDisplays: [NotchDisplay] {
        DisplaySelection.eligible(displays, mode: preferences.displayMode, selected: preferences.selectedDisplays)
    }

    /// Overrides saved for screens that are not connected right now.
    private var disconnectedOverrides: [String] {
        let connected = Set(displays.map(\.persistentID))
        return preferences.displayShapes.keys.filter { !connected.contains($0) }.sorted()
    }

    /// Per-screen rows matter once screens can differ, once one is overridden, or when a screen
    /// could offer the housing option.
    private var showsScreenRows: Bool {
        eligibleDisplays.count > 1 || !preferences.displayShapes.isEmpty || eligibleDisplays.contains { !$0.hasNotch }
    }

    /// What Automatic resolves to right now for the global default.
    private var shapeSubtitle: String {
        guard preferences.shapeStyle == .auto else { return preferences.shapeStyle == .island ? "Floating island everywhere." : "Grows out of the notch everywhere." }
        return screenHasNotch ? "This screen shows its notch, so the notch is used." : "No notch on this screen, so it floats as an island."
    }

    private func resolvedStyle(_ display: NotchDisplay) -> Preferences.ShapeStyle {
        preferences.displayShapes[display.persistentID]?.style ?? preferences.shapeStyle
    }

    private func resolvedIsland(_ display: NotchDisplay) -> Bool {
        switch resolvedStyle(display) {
        case .auto: !display.hasNotch
        case .notch: false
        case .island: true
        }
    }

    private func screenSubtitle(_ display: NotchDisplay) -> String {
        let size = "\(Int(display.frame.width)) × \(Int(display.frame.height)) pt"
        let effective: String
        if resolvedIsland(display) {
            effective = "Island"
        } else if !display.hasNotch, preferences.displayShapes[display.persistentID]?.housingGap == false {
            effective = "Notch, no camera housing"
        } else {
            effective = "Notch"
        }
        return "\(size) · \(effective)"
    }

    /// Nil means Default: the screen follows the global shape and stores no entry.
    private func shapeBinding(for display: NotchDisplay) -> Binding<Preferences.ShapeStyle?> {
        Binding(
            get: { preferences.displayShapes[display.persistentID]?.style },
            set: { style in
                var shapes = preferences.displayShapes
                if let style {
                    var entry = shapes[display.persistentID] ?? Preferences.DisplayShape(style: style)
                    entry.style = style
                    shapes[display.persistentID] = entry
                } else {
                    shapes[display.persistentID] = nil
                }
                preferences.displayShapes = shapes
            }
        )
    }

    /// Editing the housing stores the screen's current shape, so the row becomes explicit.
    private func housingBinding(for display: NotchDisplay) -> Binding<Bool> {
        Binding(
            get: { preferences.displayShapes[display.persistentID]?.housingGap ?? true },
            set: { on in
                var shapes = preferences.displayShapes
                var entry = shapes[display.persistentID] ?? Preferences.DisplayShape(style: resolvedStyle(display))
                entry.housingGap = on
                shapes[display.persistentID] = entry
                preferences.displayShapes = shapes
            }
        )
    }

    var body: some View {
        SettingsGroup(title: "Shape", footer: "Automatic floats an island on screens without a hardware notch, including a MacBook set to a resolution that leaves the notch area out, and grows out of the notch everywhere else. Each screen can keep its own shape; Default follows this picker. On a screen with no notch, Notch can drop the assumed camera housing so OSDs and the open panel use the full width.") {
            SettingsRow(title: "Shape", subtitle: shapeSubtitle, symbol: "capsule.fill", tint: Theme.Accent.tray) {
                Picker("", selection: $preferences.shapeStyle.animation(Motion.state)) {
                    ForEach(Preferences.ShapeStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            if showsScreenRows {
                ForEach(eligibleDisplays) { display in
                    SettingsRow(title: display.name, subtitle: screenSubtitle(display),
                        symbol: display.builtIn ? "laptopcomputer" : "display", tint: Theme.Accent.system) {
                        Picker("", selection: shapeBinding(for: display).animation(Motion.state)) {
                            Text("Default").tag(Preferences.ShapeStyle?.none)
                            ForEach([Preferences.ShapeStyle.notch, .island]) { style in
                                Text(style.title).tag(Optional(style))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                    if !display.hasNotch, resolvedStyle(display) == .notch {
                        SettingsToggle(
                            title: "Assume a camera housing",
                            subtitle: "On \(display.name): off lets OSDs and the open panel use the middle.",
                            symbol: "camera.metering.unknown",
                            tint: Theme.Accent.tray,
                            isOn: housingBinding(for: display).animation(Motion.state)
                        )
                        .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                ForEach(disconnectedOverrides, id: \.self) { id in
                    SettingsRow(title: "Disconnected display", subtitle: id, symbol: "display.slash", tint: Theme.Accent.warning) {
                        Button("Forget") { preferences.displayShapes[id] = nil }
                    }
                }
            }
            if showsIslandSettings {
                SettingsRow(title: "Island shows", symbol: "clock.fill", tint: Theme.Accent.tray) {
                    Picker("", selection: $preferences.pillContent.animation(Motion.state)) {
                        ForEach(Preferences.PillContent.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                SettingsToggle(title: "24-hour clock", symbol: "24.circle.fill", tint: Theme.Accent.tray, isOn: $preferences.use24Hour)
                SettingsToggle(title: "Satellites", subtitle: "Two small circles beside the island: what is playing, and Controls.", symbol: "circle.circle.fill", tint: Theme.Accent.tray, isOn: $preferences.islandSatellites.animation(Motion.state))
                SliderRow(title: "Island width", symbol: "arrow.left.and.right", tint: Theme.Accent.tray, value: $preferences.islandWidth, range: Preferences.Limits.islandWidth, step: 2, format: { $0 < 1 ? "Fit" : "\(Int($0)) pt" })
                SliderRow(title: "Island height", symbol: "arrow.up.and.down", tint: Theme.Accent.tray, value: $preferences.islandHeight, range: Preferences.Limits.islandHeight, step: 1, format: { $0 < 1 ? "Menu bar" : "\(Int($0)) pt" })
                SliderRow(title: "Distance from top", symbol: "arrow.down.to.line", tint: Theme.Accent.tray, value: $preferences.islandTop, range: Preferences.Limits.islandTop, step: 1, format: { "\(Int($0)) pt" })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = NotchDisplay.connected
        }

        SettingsGroup(title: "Size", footer: "Type any value by clicking the number. On a notched screen the closed notch can only grow, since nothing can be drawn over the camera housing. The Agents tab fits its content up to the open panel height; other tabs keep that height.") {
            SizePreview(island: islandInUse)
                .frame(height: 118)
                .padding(12)
            SliderRow(title: "Notch width", symbol: "rectangle.topthird.inset.filled", tint: Theme.Accent.codex, value: $preferences.closedExtraWidth, range: Preferences.Limits.closedExtraWidth, step: 2, format: { $0 < 1 ? "Hardware" : "+\(Int($0)) pt" })
            SliderRow(title: "Wings and banners", symbol: "arrow.left.and.right.square", tint: Theme.Accent.codex, value: $preferences.activityWidthScale, range: Preferences.Limits.activityWidthScale, typedScale: 100, format: { "\(Int($0 * 100))%" })
            SliderRow(title: "Open panel width", symbol: "arrow.left.and.right", tint: Theme.Accent.codex, value: $preferences.panelWidth, range: Preferences.Limits.panelWidth, step: 10, format: { "\(Int($0)) pt" })
            SliderRow(title: "Open panel height", symbol: "arrow.up.and.down", tint: Theme.Accent.codex, value: $preferences.panelHeight, range: Preferences.Limits.panelHeight, step: 4, format: { "\(Int($0)) pt" })
            SliderRow(title: "Roundness", symbol: "app", tint: Theme.Accent.codex, value: $preferences.cornerScale, range: Preferences.Limits.cornerScale, typedScale: 100, format: { "\(Int($0 * 100))%" })
        }

        SettingsGroup(title: "Body", footer: "Glass uses Liquid Glass on macOS 26 and later, vibrancy before that. The top edge always stays black so it blends with the camera housing.") {
            SettingsRow(title: "Material", symbol: "square.fill.on.square.fill", tint: Theme.Accent.airdrop) {
                Picker("", selection: $preferences.bodyStyle.animation(Motion.state)) {
                    ForEach(Preferences.BodyStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            if preferences.bodyStyle == .tinted {
                SettingsRow(title: "Tint", symbol: "drop.fill", tint: preferences.tint == .black ? .white : preferences.tint) {
                    SwatchRow(values: Self.tintSwatches, selection: $preferences.tintHex)
                    ColorPicker("", selection: hexBinding(\.tintHex), supportsOpacity: false).labelsHidden()
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
            SliderRow(title: "Opacity", symbol: "circle.dotted", tint: Theme.Accent.system, value: $preferences.bodyOpacity, range: Preferences.Limits.bodyOpacity, typedScale: 100, format: { "\(Int($0 * 100))%" })
            SettingsToggle(title: "Shadow when open", symbol: "shadow", tint: Theme.Accent.system, isOn: $preferences.shadow)
            SettingsToggle(title: "Emission edge", subtitle: "Soft light along the edge tinted by what is playing or happening.", symbol: "light.max", tint: Theme.Accent.warning, isOn: $preferences.emissionEdge)
            if preferences.emissionEdge {
                SliderRow(title: "Edge intensity", symbol: "sun.min.fill", tint: Theme.Accent.warning, value: $preferences.emissionIntensity, range: 0.2...1, format: { "\(Int($0 * 100))%" })
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
            SettingsToggle(title: "Glow when an agent needs you", subtitle: "A light runs around the outline until you answer.", symbol: "sparkles", tint: Theme.Accent.needsYou, isOn: $preferences.glowNeedsYou)
            if screenHasNotch {
                SettingsToggle(title: "Hide the hardware notch", subtitle: "Paints the menu bar black so the camera housing disappears into it.", symbol: "menubar.rectangle", tint: .white, isOn: $preferences.hideNotch)
            }
        }

        SettingsGroup(title: "Accent", footer: "Used for the selected tab, toggles and sliders.") {
            SettingsToggle(
                title: "Match macOS",
                subtitle: "Follows the accent color in System Settings › Appearance.",
                symbol: "macbook",
                tint: preferences.systemAccent,
                isOn: $preferences.accentFollowsSystem
            )
            if !preferences.accentFollowsSystem {
                SettingsRow(title: "Accent color", symbol: "paintpalette.fill", tint: preferences.accent) {
                    SwatchRow(values: Self.accentSwatches, selection: $preferences.accentHex)
                    ColorPicker("", selection: hexBinding(\.accentHex), supportsOpacity: false).labelsHidden()
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }

        HStack {
            Spacer()
            Button("Reset look, size and motion") { preferences.resetCustomization() }
        }
    }

    private func hexBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, Int>) -> Binding<Color> {
        Binding(
            get: { Color(hex: UInt32(preferences[keyPath: keyPath])) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let value = (Int(rgb.redComponent * 255) << 16) | (Int(rgb.greenComponent * 255) << 8) | Int(rgb.blueComponent * 255)
                preferences[keyPath: keyPath] = value
            }
        )
    }
}

/// To-scale sketch of the closed notch and the open panel, updating as the sliders move.
private struct SizePreview: View {
    /// Draw the island instead of the notch.
    let island: Bool
    @EnvironmentObject private var preferences: Preferences
    private let hardware = CGSize(width: 185, height: 32)

    var body: some View {
        GeometryReader { proxy in
            let open = openSize
            let closed = closedSize
            // Fit the biggest thing drawn, so a huge panel still shows whole.
            let scale = min(1, (proxy.size.width - 24) / max(780, open.width + 40), (proxy.size.height - 8) / max(1, open.height + top))
            let openShape = NotchShape(
                topRadius: island ? 0 : 8 * scale,
                bottomRadius: 32 * scale * preferences.cornerScale,
                capRadius: island ? 32 * scale * preferences.cornerScale : 0
            )
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B3A55), Color(hex: 0x4A2C4F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                openShape
                    .fill(Color.black.opacity(0.35))
                    .overlay(openShape.stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .frame(width: open.width * scale, height: open.height * scale)
                    .padding(.top, top * scale)
                NotchShape(
                    topRadius: island ? 0 : 4 * scale,
                    bottomRadius: island ? closed.height * scale / 2 : 12 * scale,
                    capRadius: island ? closed.height * scale / 2 : 0
                )
                .fill(Color.black)
                .frame(width: closed.width * scale, height: closed.height * scale)
                .padding(.top, top * scale)
                if !island {
                    RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: hardware.width * scale, height: hardware.height * scale)
                        .help("Camera housing")
                }
            }
            .animation(Motion.value, value: preferences.panelWidth)
            .animation(Motion.value, value: preferences.panelHeight)
            .animation(Motion.value, value: preferences.closedExtraWidth)
            .animation(Motion.value, value: island)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Size preview")
    }

    private var top: CGFloat { island ? CGFloat(preferences.islandTop) : 0 }

    private var rowHeight: CGFloat {
        guard island else { return hardware.height }
        return preferences.islandHeight > 0 ? CGFloat(preferences.islandHeight) : 26
    }

    private var closedSize: CGSize {
        guard island else { return CGSize(width: hardware.width + preferences.closedExtraWidth, height: hardware.height) }
        let width = preferences.islandWidth > 0 ? CGFloat(preferences.islandWidth) : NotchViewModel.pillWidth(for: preferences.pillContent, height: rowHeight)
        return CGSize(width: width, height: rowHeight)
    }

    private var openSize: CGSize {
        let width = island ? CGFloat(preferences.panelWidth) : max(CGFloat(preferences.panelWidth), closedSize.width + 40)
        return CGSize(width: width, height: rowHeight + CGFloat(preferences.panelHeight))
    }
}

private struct SwatchRow: View {
    let values: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(values, id: \.self) { value in
                Button {
                    withAnimation(Motion.state) { selection = value }
                } label: {
                    Circle()
                        .fill(Color(hex: UInt32(value)))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white.opacity(selection == value ? 0.9 : 0.15), lineWidth: selection == value ? 2 : 1))
                        .scaleEffect(selection == value ? 1.12 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: "#%06X", value))
            }
        }
    }
}

// MARK: Motion

struct MotionSettings: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        SettingsGroup(title: "Preview", footer: "Hover the preview to open it with your current settings.") {
            MotionPreview()
                .frame(height: 150)
                .padding(12)
        }
        SettingsGroup(title: "Presets") {
            HStack(spacing: 8) {
                ForEach(Preferences.MotionPreset.allCases) { preset in
                    let active = abs(preferences.animationSpeed - preset.values.speed) < 0.01 && abs(preferences.bounce - preset.values.bounce) < 0.01
                    Button(preset.title) { preferences.apply(preset) }
                        .buttonStyle(.bordered)
                        .tint(active ? preferences.accent : nil)
                }
                Spacer()
            }
            .padding(12)
        }
        SettingsGroup(title: "Tuning", footer: "Closing is always a little faster than opening and never overshoots. Reduce Motion in System Settings replaces movement with fades.") {
            SliderRow(title: "Speed", symbol: "hare.fill", tint: Theme.Accent.awake, value: $preferences.animationSpeed, range: 0.5...2, format: { $0 >= 1.99 ? "Instant" : String(format: "%.2g×", $0) })
            SliderRow(title: "Bounce", symbol: "arrow.up.and.down.and.sparkles", tint: Theme.Accent.awake, value: $preferences.bounce, range: 0...0.4, format: { "\(Int($0 * 100))%" })
            SliderRow(title: "Hover delay", symbol: "cursorarrow.and.square.on.square.dashed", tint: Theme.Accent.awake, value: $preferences.hoverDelay, range: 0...0.5, step: 0.01, format: { "\(Int($0 * 1000)) ms" })
            SliderRow(title: "Close delay", symbol: "clock.arrow.circlepath", tint: Theme.Accent.awake, value: $preferences.closeDelay, range: 0.05...1.2, step: 0.05, format: { "\(Int($0 * 1000)) ms" })
            SettingsToggle(title: "Cascade content", subtitle: "Rows arrive one after another instead of all at once.", symbol: "text.line.first.and.arrowtriangle.forward", tint: Theme.Accent.awake, isOn: $preferences.staggerContent)
            SettingsToggle(title: "Swipe to switch tabs", subtitle: "Two-finger swipe left or right on the open panel.", symbol: "arrow.left.and.right", tint: Theme.Accent.awake, isOn: $preferences.tabSwipeEnabled)
            SettingsRow(title: "Open the notch on", symbol: "cursorarrow.motionlines", tint: Theme.Accent.airdrop) {
                Picker("", selection: $preferences.openTrigger) {
                    ForEach(Preferences.OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }
}

/// A miniature notch that opens on hover with the live motion settings.
private struct MotionPreview: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var open = false
    @State private var closeWork: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x2B3A55), Color(hex: 0x4A2C4F)], startPoint: .topLeading, endPoint: .bottomTrailing))
            BodyFill(shape: AnyShape(NotchShape(topRadius: open ? 10 : 4, bottomRadius: open ? 22 : 8)), expanded: open)
                .frame(width: open ? 300 : 110, height: open ? 104 : 18)
                .overlay(alignment: .top) { previewContent.padding(.top, 22) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            closeWork?.cancel()
            let work = DispatchWorkItem {
                withAnimation(hovering ? Motion.open : Motion.close) { open = hovering }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (hovering ? Motion.hoverOpenDelay : Motion.hoverCloseDelay), execute: work)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if open {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(index == 0 ? preferences.accent.opacity(0.8) : Theme.Palette.surfaceHover)
                        .frame(width: 80, height: 58)
                        .condense(delay: Motion.stagger(index + 1))
                }
            }
            .transition(.notchContent)
        }
    }
}

// MARK: Tabs & wings

struct LayoutSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var activities: ActivityCenter

    var body: some View {
        SettingsGroup(title: "Panel tabs", footer: "Order and visibility of the tabs in the open panel.") {
            ForEach(Array(preferences.allTabsOrdered.enumerated()), id: \.element) { index, tab in
                SettingsRow(title: tab.title, subtitle: preferences.isFeatureEnabled(tab) ? nil : tab == .widgets ? "Appears when an agent adds a widget" : "Feature is off", symbol: tab.symbol, tint: preferences.accent) {
                    Button { preferences.moveTab(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .accessibilityLabel("Move \(tab.title) up")
                    Button { preferences.moveTab(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(index == preferences.allTabsOrdered.count - 1)
                        .accessibilityLabel("Move \(tab.title) down")
                    Toggle("", isOn: Binding(
                        get: { !preferences.hiddenTabs.contains(tab.rawValue) },
                        set: { visible in
                            withAnimation(Motion.state) {
                                if visible { preferences.hiddenTabs.remove(tab.rawValue) } else if tab != .home { preferences.hiddenTabs.insert(tab.rawValue) }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(tab == .home)
                }
            }
        }
        HomeRowsSettings()
        SettingsGroup(title: "What slides out", footer: "Turn off any live activity you do not want to see beside the notch.") {
            ForEach(ActivityKind.allCases, id: \.self) { kind in
                SettingsToggle(
                    title: kind.title,
                    isOn: Binding(
                        get: { preferences.isActivityEnabled(kind) },
                        set: { enabled in
                            preferences.setActivity(kind, enabled: enabled)
                            activities.refresh()
                        }
                    )
                )
            }
        }
    }
}

// MARK: Shared rows

struct SliderRow: View {
    let title: String
    var symbol: String?
    var tint: Color = Theme.Accent.system
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// What a typed number is multiplied by for display: 100 when the value shows as a percent.
    var typedScale: Double = 1
    let format: (Double) -> String

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        SettingsRow(title: title, symbol: symbol, tint: tint) {
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .controlSize(.small)
            .frame(width: 180)
            .tint(tint)
            valueField
                .frame(width: 64, alignment: .trailing)
        }
    }

    /// The value as text; click it to type an exact number.
    @ViewBuilder
    private var valueField: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .focused($fieldFocused)
                .onSubmit(commit)
                .onChange(of: fieldFocused) { _, focused in if !focused { commit() } }
                .onExitCommand { editing = false }
                .onAppear { fieldFocused = true }
        } else {
            Button {
                draft = Self.plain(value * typedScale)
                editing = true
            } label: {
                Text(format(value))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to type a value from \(Self.plain(range.lowerBound * typedScale)) to \(Self.plain(range.upperBound * typedScale))")
            .accessibilityLabel("\(title): \(format(value)). Edit")
        }
    }

    private func commit() {
        let digits = draft.filter { $0.isNumber || $0 == "." || $0 == "-" }
        if let typed = Double(digits) {
            withAnimation(Motion.state) { value = min(max(typed / typedScale, range.lowerBound), range.upperBound) }
        }
        editing = false
    }

    private static func plain(_ number: Double) -> String {
        number.rounded() == number ? String(Int(number)) : String(format: "%.2f", number)
    }
}
