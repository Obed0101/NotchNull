import SwiftUI

/// Inset surface inside the panel. Radius is concentric with the body's bottom corners.
struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.surface, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
    }
}

/// A labeled row with a leading tinted icon, used in the Home and Agents lists.
struct InfoRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.infoRowHeight) private var height

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 19, height: 19)
                .background(Circle().fill(tint.opacity(0.16)))
            Text(title)
                .font(Theme.Typeface.bodyStrong)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            trailing
        }
        .frame(height: height)
    }
}

extension EnvironmentValues {
    /// Height of an `InfoRow`; a list that would otherwise overflow by a few points tightens it.
    @Entry var infoRowHeight: CGFloat = 26
}

/// Compact switch that animates its knob; the notch never uses the stock macOS switch.
struct NotchToggle: View {
    @Binding var isOn: Bool
    var tint: Color = Theme.Accent.success
    var label: String

    var body: some View {
        Button {
            withAnimation(Motion.state) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? tint : Theme.Palette.track)
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .frame(width: 28, height: 16)
        }
        .buttonStyle(PressableStyle(hoverFill: .clear, cornerRadius: 8, padding: EdgeInsets()))
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Small rounded choice chip.
struct Chip: View {
    let title: String
    var selected = false
    var tint: Color = Theme.Palette.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.caption)
                .foregroundStyle(selected ? Color.black : tint)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(selected ? tint : Theme.Palette.surfaceHover))
        }
        .buttonStyle(PressableStyle(hoverFill: .clear, cornerRadius: 10, padding: EdgeInsets()))
    }
}

/// Inline control shown when a feature is blocked by a missing permission.
struct PermissionPrompt: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Accent.warning)
            Text(message)
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Chip(title: actionTitle, tint: Theme.Accent.warning, action: action)
        }
    }
}
