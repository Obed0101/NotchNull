import SwiftUI

/// Root of every notch window.
struct NotchRootView: View {
    @EnvironmentObject private var model: NotchViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                NotchBodyView()
                    .padding(.top, model.bodyTop)
                    .frame(width: Theme.Size.canvas.width, height: Theme.Size.canvas.height, alignment: .top)
                if let satellites = model.satelliteFrames {
                    IslandSatellite(side: .leading, frame: satellites.left)
                    IslandSatellite(side: .trailing, frame: satellites.right)
                }
            }
            .offset(y: Motion.reduceMotion ? 0 : model.concealOffset)
            .opacity(Motion.reduceMotion && model.isConcealed ? 0 : 1)
            .accessibilityHidden(model.isConcealed)
            .animation(Motion.isSnapshot ? nil : (model.isConcealed ? Motion.conceal : Motion.reveal), value: model.isConcealed)

            if model.isFullscreenActive && !model.isExpanded {
                WakeStrip()
            }
        }
        .frame(width: Theme.Size.canvas.width, height: Theme.Size.canvas.height, alignment: .topLeading)
        .animation(Motion.state, value: model.isIsland)
        .preferredColorScheme(.dark)
    }
}

/// Transparent top-centre target that brings a concealed notch back while a fullscreen app
/// covers the display. The pointer tracking is global; this view handles the click.
private struct WakeStrip: View {
    @EnvironmentObject private var model: NotchViewModel

    var body: some View {
        Color.clear
            .frame(width: model.closedSize.width, height: Theme.Size.fullscreenWakeHeight)
            .contentShape(Rectangle())
            .onTapGesture { model.open() }
            .frame(width: Theme.Size.canvas.width, height: Theme.Size.canvas.height, alignment: .top)
            .accessibilityHidden(true)
    }
}

/// One shape morphs between every phase, as a notch or as an island; content inside condenses from blur.
struct NotchBodyView: View {
    @EnvironmentObject private var model: NotchViewModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var nowPlaying: NowPlayingService
    @EnvironmentObject private var battery: BatteryService

    var body: some View {
        let phase = model.phase
        let island = model.isIsland
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius, capRadius: model.capRadius)
        ZStack(alignment: .top) {
            BodyFill(shape: AnyShape(shape), expanded: model.isExpanded, keepTopBlack: !island)
            if island {
                shape.stroke(Color.white.opacity(0.08), lineWidth: 1)
            }

            content(for: phase)
                .frame(width: model.bodySize.width, height: model.bodySize.height, alignment: .top)
                .frame(width: model.shapeSize.width, height: model.shapeSize.height, alignment: .top)
                .clipShape(shape)

            if preferences.emissionEdge, let tint = ActivityTint.color(for: phase, music: nowPlaying.tint, battery: battery.state) {
                EmissionEdge(tint: tint, topRadius: model.topRadius, bottomRadius: model.bottomRadius, capRadius: model.capRadius, intensity: model.isExpanded ? 0.45 : 0.9)
                    .drawingGroup()
                    .transition(.opacity)
            }

            ChasingOutline(
                tint: Theme.Accent.needsYou,
                topRadius: model.topRadius,
                bottomRadius: model.bottomRadius,
                capRadius: model.capRadius,
                active: ChasingOutline.isActive(phase: phase, visible: model.isWindowVisible, glowEnabled: preferences.glowNeedsYou)
            )
        }
        .frame(width: model.shapeSize.width, height: model.shapeSize.height)
        .contentShape(shape)
        .onTapGesture { handleTap(phase) }
        .environment(\.wingContext, WingContext(
            centerGap: model.wingGap,
            rowHeight: model.contentRowHeight,
            // The island's rounded top corners need more room than the notch's flares.
            horizontalPadding: model.contentRowInset
        ))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch")
    }

    @ViewBuilder
    private func content(for phase: NotchViewModel.Phase) -> some View {
        switch phase {
        case .closed:
            if model.isIsland {
                PillFace()
                    .frame(height: model.rowHeight)
                    .transition(.notchContent)
            } else {
                Color.clear
            }
        case .activity(let kind):
            ActivityContentView(kind: kind)
                .id(kind)
                .transition(.notchContent)
        case .open:
            ExpandedPanel()
                .transition(.notchContent)
        case .drop:
            DropPanel()
                .transition(.notchContent)
        }
    }

    private func handleTap(_ phase: NotchViewModel.Phase) {
        switch phase {
        case .closed:
            model.open()
        case .activity(.custom) where CustomActivityStore.shared.performCurrentAction():
            break
        case .activity(let kind):
            model.open(tab: kind.relatedTab)
        default:
            break
        }
    }
}

extension ActivityKind {
    /// The panel tab that explains an activity when the user taps it.
    var relatedTab: NotchTab {
        switch self {
        case .needsYou, .agentDone, .agentRunning, .usageWarning: .agents
        case .custom: .widgets
        case .trayAdded, .screenshot: .tray
        case .download, .downloadDone, .downloadKeep, .downloadTrashed, .downloadExpiring: .downloads
        case .volume, .brightness, .accessory: .controls
        default: .home
        }
    }
}

enum ActivityTint {
    static func color(for phase: NotchViewModel.Phase, music: Color, battery: BatteryState) -> Color? {
        guard case .activity(let kind) = phase else { return nil }
        switch kind {
        case .music: return music
        case .needsYou: return nil
        case .volume: return Theme.Accent.volumeHigh
        case .brightness: return Theme.Accent.brightness
        case .charging: return battery.chargeTint
        case .lowBattery: return Theme.Accent.danger
        case .timer, .timerFinished: return Theme.Accent.timer
        case .agentRunning: return Theme.Accent.claude
        case .agentDone: return Theme.Accent.success
        case .usageWarning: return Theme.Accent.warning
        case .custom: return MainActor.assumeIsolated { WidgetStyle.color(CustomActivityStore.shared.current?.tint) ?? Preferences.shared.accent }
        case .download, .downloadDone, .downloadKeep: return Theme.Accent.download
        case .downloadTrashed, .downloadExpiring: return Theme.Accent.warning
        case .trayAdded, .screenshot: return Theme.Accent.tray
        case .meetingSoon: return Theme.Accent.calendar
        case .accessory: return Color.white
        case .hello: return Color(hex: 0xA78BFA)
        }
    }
}

/// Body material from the user's style: black, Liquid Glass / vibrancy, or a tinted color.
/// In notch style the top band stays black so the body still reads as part of the hardware notch.
struct BodyFill: View {
    let shape: AnyShape
    var expanded: Bool
    var keepTopBlack = false
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        ZStack {
            switch preferences.bodyStyle {
            case .black:
                shape.fill(Theme.Palette.body.opacity(preferences.bodyOpacity))
            case .tinted:
                shape.fill(preferences.tint.opacity(preferences.bodyOpacity))
                shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom))
            case .glass:
                glass
            }
            if keepTopBlack && preferences.bodyStyle != .black {
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
                    .clipShape(shape)
            }
        }
        .modifier(ChromeCache(enabled: preferences.bodyStyle != .glass))
        .shadow(
            color: .black.opacity(expanded && preferences.shadow ? 0.45 : 0),
            radius: expanded ? 18 : 0, x: 0, y: expanded ? 10 : 0
        )
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.45 * preferences.bodyOpacity)), in: shape)
        } else {
            VisualEffectBlur()
                .clipShape(shape)
                .overlay(shape.fill(Color.black.opacity(0.35 * preferences.bodyOpacity)))
        }
    }
}

/// Caches static chrome so a ticking label does not re-rasterize the body fill. The glass body is
/// excluded: its pre-macOS 26 fallback is an AppKit view, which a SwiftUI raster group cannot draw.
private struct ChromeCache: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
