import AppKit

/// Centralizes the Force Touch "little click" behind the `haptics` preference, so the middle
/// pill and the island satellites stay in sync.
@MainActor
enum Haptics {
    static func play(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard Preferences.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
