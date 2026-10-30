import ImageIO
import SwiftUI

/// Settings › Setup: pick how much the notch shows (Minimal, Balanced, Complete) and a look, then
/// learn that none of it is fixed. Opens on first launch; any time after from the sidebar.
struct SetupSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var presets = Recipes.load(.preset)
    @State private var themes = Recipes.load(.theme)
    @State private var problems: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick a starting point. Your agent does the rest.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("None of this is fixed. Every preset is a file, and so is everything the notch shows. Ask Claude Code or Codex on this Mac for anything: a widget, a wing, a new look or animation, even a new Settings page. It edits the notch, checks a render and the change is live.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        SettingsGroup(title: "Shape", footer: "Automatic uses the notch when the screen shows one and floats an island when it does not, for example on a MacBook set to a resolution that leaves the notch area out.") {
            HStack(spacing: 8) {
                ForEach(Preferences.ShapeStyle.allCases) { style in
                    ShapeCard(style: style, selected: preferences.shapeStyle == style) {
                        withAnimation(Motion.state) {
                            preferences.shapeStyle = style
                            // A starting shape applies to every screen.
                            preferences.displayShapes = [:]
                        }
                        preferences.setupCompleted = true
                    }
                }
            }
            .padding(10)
        }

        VStack(spacing: 10) {
            ForEach(presets) { preset in
                PresetCard(preset: preset, selected: preferences.appliedPreset == preset.id) { apply(preset) }
            }
        }

        SettingsGroup(title: "Look", footer: "Looks only change colors, corners and glow. Each one is a file: copy one from ~/.notchnull/skill/themes into ~/.notchnull/themes and edit it, or ask your agent for a new one. Yours show up here and no update touches them.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 6) {
                ForEach(themes) { theme in
                    ThemeSwatch(theme: theme, selected: isCurrent(theme)) { apply(theme) }
                }
            }
            .padding(10)
        }

        SettingsGroup(title: "Permissions", footer: "All optional, and nothing is asked until you press Allow. Skip any of them; each feature asks again where it lives, and Settings › Permissions has the same list.") {
            PermissionList()
        }

        if !problems.isEmpty {
            SettingsGroup {
                ForEach(problems, id: \.self) { problem in
                    SettingsRow(title: problem, symbol: "exclamationmark.triangle.fill", tint: Theme.Accent.danger) { EmptyView() }
                }
            }
        }

        SettingsGroup(title: "Now make it yours", footer: "Everything the notch shows is a file in ~/.notchnull, and the app itself is open source. Your agent can change either.") {
            SettingsRow(
                title: "Teach your agent",
                subtitle: "Install the notchnull skill for Claude Code or Codex, then ask for what you want.",
                symbol: "hammer.fill",
                tint: Theme.Accent.clipboard
            ) {
                Button("Open Build") { withAnimation(Motion.state) { SettingsNavigation.shared.section = .build } }
            }
            SettingsRow(title: "Try asking", subtitle: "“\(BuildSettings.starterPrompt)”", symbol: "text.bubble.fill", tint: Theme.Accent.clipboard) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(BuildSettings.starterPrompt, forType: .string)
                }
            }
        }

        HStack {
            Spacer()
            Button("Done") {
                preferences.setupCompleted = true
                SettingsWindowController.shared.close()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
    }

    private func apply(_ recipe: NotchRecipe) {
        withAnimation(Motion.state) { problems = Recipes.apply(recipe) }
        preferences.setupCompleted = true
    }

    /// A look is current when the body and accent it sets are the ones in use.
    private func isCurrent(_ theme: NotchRecipe) -> Bool {
        guard let look = theme.settings["look"] else { return false }
        if look["body"]?.string != preferences.bodyStyle.rawValue { return false }
        if look["accentFollowsMac"]?.bool == true { return preferences.accentFollowsSystem }
        guard let accent = look["accent"]?.string, let hex = Int(accent.dropFirst(), radix: 16) else { return false }
        return !preferences.accentFollowsSystem && preferences.accentHex == hex
    }
}

/// One preset: its real render on the left, name and what it keeps on the right.
private struct PresetCard: View {
    let preset: NotchRecipe
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                preview
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(preset.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Preferences.shared.accent)
                                .transition(.scale(scale: 0.25).combined(with: .opacity))
                        }
                    }
                    Text(preset.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Preferences.shared.accent.opacity(0.8) : Theme.Palette.hairline, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(hoverFill: Theme.Palette.surfaceHover, cornerRadius: 14, padding: EdgeInsets()))
        .animation(Motion.state, value: selected)
        .accessibilityLabel("\(preset.name) preset. \(preset.summary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The preset's render hanging from the top edge of a dark strip, like the notch from the screen.
    private var preview: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x1B1C1F))
            if let image = Self.image(at: preset.preview) {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 10)
            }
        }
        .frame(width: 188, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }

    private static func image(at url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// One shape as a small drawing of the top of a screen: the notch hanging from the edge, the
/// island floating with its satellites, or both for Automatic.
private struct ShapeCard: View {
    let style: Preferences.ShapeStyle
    let selected: Bool
    let action: () -> Void
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x2B3A55), Color(hex: 0x4A2C4F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    drawing
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(spacing: 2) {
                    Text(style == .notch ? "Classic notch" : style.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? preferences.accent.opacity(0.85) : Theme.Palette.hairline, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(hoverFill: Theme.Palette.surfaceHover, cornerRadius: 12, padding: EdgeInsets()))
        .animation(Motion.state, value: selected)
        .accessibilityLabel("\(style.title) shape. \(caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var caption: String {
        switch style {
        case .auto: "Notch or island, whichever the screen suits."
        case .notch: "Grows out of the camera housing."
        case .island: "A floating pill with satellites."
        }
    }

    @ViewBuilder
    private var drawing: some View {
        switch style {
        case .notch:
            notch.padding(.top, 0)
        case .island:
            island.padding(.top, 8)
        case .auto:
            HStack(spacing: 14) {
                notch
                island.padding(.top, 8)
            }
            .scaleEffect(0.78, anchor: .top)
        }
    }

    private var notch: some View {
        NotchShape(topRadius: 3, bottomRadius: 8)
            .fill(Color.black)
            .frame(width: 58, height: 16)
    }

    private var island: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.black).frame(width: 13, height: 13)
            Capsule().fill(Color.black).frame(width: 46, height: 13)
            Circle().fill(Color.black).frame(width: 13, height: 13)
        }
    }
}

/// A look as a disc: its body color with its accent as a dot, and the name under it.
private struct ThemeSwatch: View {
    let theme: NotchRecipe
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let swatch = theme.swatch
        let body = WidgetStyle.color(swatch.body) ?? .black
        let accent = WidgetStyle.color(swatch.accent) ?? Preferences.shared.accent
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(theme.settings["look"]?["body"]?.string == "glass" ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(body))
                    Circle().strokeBorder(Color.white.opacity(0.14))
                    Circle().fill(accent).frame(width: 12, height: 12)
                }
                .frame(width: 38, height: 38)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? accent : Color.clear, lineWidth: 2))
                Text(theme.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(hoverFill: Theme.Palette.surfaceHover, cornerRadius: 10, padding: EdgeInsets()))
        .help(theme.summary)
        .accessibilityLabel("\(theme.name) look")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(Motion.state, value: selected)
    }
}
