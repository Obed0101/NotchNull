import AppKit

struct NotchDisplay: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let persistentID: String
    let name: String
    let frame: CGRect
    let builtIn: Bool
    let hasNotch: Bool
    let scale: CGFloat

    @MainActor
    static var connected: [NotchDisplay] {
        NSScreen.screens.map { screen in
            let id = NotchGeometry.screenID(screen)
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()
            return NotchDisplay(id: id, persistentID: CFUUIDCreateString(nil, uuid) as String,
                name: screen.localizedName, frame: screen.frame, builtIn: NotchGeometry.isBuiltIn(screen),
                hasNotch: NotchGeometry(screen: screen).hasHardwareNotch, scale: screen.backingScaleFactor)
        }
    }
}

@MainActor
enum DisplaySelection {
    /// NSScreen.main follows keyboard focus; the first screen is the macOS main display.
    static func eligible(_ displays: [NotchDisplay], mode: Preferences.DisplayMode, selected: [String]) -> [NotchDisplay] {
        switch mode {
        case .all: displays
        case .main: Array(displays.prefix(1))
        case .builtIn: displays.first(where: \.builtIn).map { [$0] } ?? Array(displays.prefix(1))
        case .selected: displays.filter { selected.contains($0.persistentID) }
        }
    }

    static func target(_ displays: [NotchDisplay], pointer: CGPoint) -> CGDirectDisplayID? {
        displays.first { $0.frame.contains(pointer) }?.id
            ?? displays.first(where: \.builtIn)?.id ?? displays.first?.id
    }
}
