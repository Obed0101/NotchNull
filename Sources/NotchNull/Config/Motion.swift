import AppKit
import SwiftUI

/// Motion tokens. Timing scales with the user's animation speed and bounce preferences (read
/// straight from UserDefaults so every caller sees the same values). Opening may overshoot a
/// little, closing never does and is faster. With Reduce Motion enabled every spatial animation
/// collapses to a short opacity fade.
enum Motion {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Set while rendering static snapshots: entrances start in their settled state.
    nonisolated(unsafe) static var isSnapshot = false

    private static var defaults: UserDefaults { .standard }

    /// 0.5 (slow) … 2.0 (fast); 2.0 means "instant" for routine transitions.
    static var speed: Double { max(0.5, min(2.0, defaults.double(forKey: Preferences.Keys.animationSpeed))) }
    /// 0 … 0.4 overshoot on opening springs.
    static var bounce: Double { max(0, min(0.4, defaults.double(forKey: Preferences.Keys.bounce))) }
    static var isInstant: Bool { speed >= 1.99 }

    static func spring(_ response: Double, bounce extra: Double? = nil) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        if isInstant { return .easeOut(duration: 0.1) }
        let damping = 1 - (extra ?? bounce)
        return .spring(response: response / speed, dampingFraction: max(0.55, damping))
    }

    static var open: Animation { spring(0.34) }
    static var close: Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        if isInstant { return .easeOut(duration: 0.08) }
        return .spring(response: 0.26 / speed, dampingFraction: 1)
    }

    /// Wings sliding out of the notch for live activities.
    static var activity: Animation { spring(0.32) }

    /// Sliding the body out of the way while a fullscreen app covers the display. Closing
    /// never overshoots; Reduce Motion leaves the view in place and the caller fades instead.
    static var conceal: Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        if isInstant { return .easeOut(duration: 0.1) }
        return spring(0.30, bounce: 0)
    }

    /// Bringing the concealed body back down.
    static var reveal: Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        if isInstant { return .easeOut(duration: 0.1) }
        return spring(0.38)
    }

    /// Routine state change inside the panel (tab switch, toggles, rows).
    static var state: Animation { spring(0.26, bounce: bounce * 0.5) }

    /// Hover and press feedback. Kept short because it fires constantly.
    static let feedback = Animation.easeOut(duration: 0.12)

    /// Values that move continuously (levels, progress).
    static var value: Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.24, dampingFraction: 0.9)
    }

    /// Content condensing in after the body has started to open.
    static var content: Animation {
        if reduceMotion || isInstant { return .easeOut(duration: 0.1) }
        return .easeOut(duration: 0.2 / speed)
    }

    static let staggerCap = 6

    static func stagger(_ index: Int) -> Double {
        guard !reduceMotion, !isInstant, defaults.bool(forKey: Preferences.Keys.staggerContent) else { return 0 }
        return Double(min(index, staggerCap)) * 0.022 / speed
    }

    static let contentBlur: CGFloat = 6
    static let pressScale: CGFloat = 0.96

    static var hoverOpenDelay: TimeInterval { max(0, min(0.6, defaults.double(forKey: Preferences.Keys.hoverDelay))) }
    static var hoverCloseDelay: TimeInterval { max(0.05, min(1.5, defaults.double(forKey: Preferences.Keys.closeDelay))) }
}
