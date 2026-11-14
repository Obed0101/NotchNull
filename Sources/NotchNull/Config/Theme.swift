import SwiftUI

/// Visual tokens. Every color, radius and type role used by the notch lives here.
enum Theme {
    enum Palette {
        static let body = Color.black
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.62)
        static let textTertiary = Color.white.opacity(0.38)
        static let surface = Color.white.opacity(0.06)
        static let surfaceHover = Color.white.opacity(0.10)
        static let surfaceActive = Color.white.opacity(0.16)
        static let hairline = Color.white.opacity(0.10)
        static let track = Color.white.opacity(0.12)
    }

    enum Accent {
        static let music = Color(hex: 0xFF5E8A)
        static let tray = Color(hex: 0xA78BFA)
        static let copy = Color(hex: 0x34D399)
        static let airdrop = Color(hex: 0x60A5FA)
        static let volumeLow = Color.white
        static let volumeHigh = Color(hex: 0xFFB35C)
        static let brightness = Color(hex: 0xFFD66B)
        static let timer = Color(hex: 0xFF9F0A)
        static let claude = Color(hex: 0xD97757)
        static let needsYou = Color(hex: 0xFF4FA3)
        static let codex = Color(hex: 0x8FA8FF)
        static let opencode = Color(hex: 0xF5F4F0)
        static let glm = Color(hex: 0x4F7BFF)
        static let kimi = Color(hex: 0x3CC8E8)
        static let minimax = Color(hex: 0xFF5C7A)
        static let copilot = Color(hex: 0xB392F0)
        static let battery = Color(hex: 0x30D158)
        static let lowPower = Color(hex: 0xFFD60A)
        /// Battery in each energy mode: orange in Low Power, blue in High Power (Automatic uses `battery`).
        static let lowPowerMode = Color(hex: 0xFF9F0A)
        static let highPower = Color(hex: 0x0A84FF)
        static let warning = Color(hex: 0xFFB020)
        static let danger = Color(hex: 0xFF453A)
        static let download = Color(hex: 0x0A84FF)
        static let clipboard = Color(hex: 0x2DD4BF)
        static let calendar = Color(hex: 0xFF6B6B)
        static let awake = Color(hex: 0x5AC8FA)
        static let system = Color(hex: 0x9CA3AF)
        static let mirror = Color(hex: 0xF472B6)
        static let success = Color(hex: 0x30D158)
    }

    enum Radius {
        static let closedTop: CGFloat = 6
        static let closedBottom: CGFloat = 14
        static let compactBottom: CGFloat = 16
        static let openTop: CGFloat = 19
        static let openBottom: CGFloat = 32
        static let panelPadding: CGFloat = 12
        /// Concentric with `openBottom` minus `panelPadding`.
        static let surface: CGFloat = 18
        static let control: CGFloat = 10
        static let chip: CGFloat = 8
    }

    enum Size {
        static let openWidth: CGFloat = 660
        static let openContentHeight: CGFloat = 196
        static let headerHeight: CGFloat = 30
        static let dropContentHeight: CGFloat = 118
        static let wingWidth: CGFloat = 84
        static let wideWingWidth: CGFloat = 124
        static let alertBodyHeight: CGFloat = 46
        /// Canvas the panel window reserves so the SwiftUI body can animate without resizing the
        /// window. Transparent areas pass clicks through.
        /// Large enough for the widest and tallest panel the size settings allow.
        static let canvas = CGSize(width: 1320, height: 720)
        /// Size used when the display has no hardware notch.
        static let virtualNotch = CGSize(width: 190, height: 32)
        /// Island: space between the two wings of an activity (there is no camera to clear).
        static let islandWingGap: CGFloat = 16
        /// Island: gap between the pill and a satellite.
        static let satelliteGap: CGFloat = 8
        /// How far past the body the fullscreen slide travels, clearing its shadow and emission edge.
        static let fullscreenSlideMargin: CGFloat = 40
        /// Height of the top-centre hover target while the notch is concealed for fullscreen.
        static let fullscreenWakeHeight: CGFloat = 8
    }

    enum Typeface {
        static let label = Font.system(size: 11, weight: .semibold)
        static let caption = Font.system(size: 10.5, weight: .medium)
        static let body = Font.system(size: 12, weight: .regular)
        static let bodyStrong = Font.system(size: 12, weight: .semibold)
        static let title = Font.system(size: 13, weight: .semibold)
        static let wing = Font.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit()
        static let metric = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
        static let hero = Font.system(size: 28, weight: .medium, design: .rounded).monospacedDigit()
        static let heroSmall = Font.system(size: 22, weight: .medium, design: .rounded).monospacedDigit()
        static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
