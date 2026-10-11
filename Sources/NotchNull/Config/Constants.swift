import Foundation

/// Non-visual configuration: endpoints, paths, polling intervals and identifiers.
enum Constants {
    static let appName = "NotchNull"
    static let bundleIdentifier = "dev.notchnull.app"

    enum Links {
        static let author = "Obed"
        static let authorProfile = URL(string: "https://github.com/Obed0101")!
        static let repository = URL(string: "https://github.com/Obed0101/NotchNull")!
        static let website = URL(string: "https://notchnull.vercel.app")!
        static let releases = URL(string: "https://github.com/Obed0101/NotchNull/releases")!
        static let issues = URL(string: "https://github.com/Obed0101/NotchNull/issues")!
    }

    enum Updates {
        static let latestRelease = URL(string: "https://api.github.com/repos/Obed0101/NotchNull/releases/latest")!
        /// The only place an update is downloaded from; a release that points elsewhere is not installed.
        static let assetPrefix = "https://github.com/Obed0101/NotchNull/releases/download/"
        static let assetName = "NotchNull.zip"
        static let checkEvery: TimeInterval = 24 * 60 * 60
        /// How often the app looks at the clock to see whether a check is due.
        static let schedulerTick: TimeInterval = 60 * 60
        static let launchDelay: TimeInterval = 20
        static let requestTimeout: TimeInterval = 20
        static let availableBanner: TimeInterval = 8
    }

    enum Agents {
        static let eventServerPort: UInt16 = 47_823
        static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        static let claudeOAuthBeta = "oauth-2025-04-20"
        static let claudeKeychainService = "Claude Code-credentials"
        static let claudeUsageInterval: TimeInterval = 10 * 60
        static let codexUsageInterval: TimeInterval = 10 * 60
        static let claudeUsageMaxBackoff: TimeInterval = 30 * 60
        /// Other coding subscriptions (GLM, Kimi, MiniMax, OpenCode Go, Copilot) change slowly.
        static let planUsageInterval: TimeInterval = 10 * 60
        static let codexPollInterval: TimeInterval = 2
        static let codexActiveWindow: TimeInterval = 15 * 60
        static let opencodePollInterval: TimeInterval = 2
        static let opencodeActiveWindow: TimeInterval = 15 * 60
        static let tokenStatsInterval: TimeInterval = 120
        static let doneLingerSeconds: TimeInterval = 6
        static let sessionForgetAfter: TimeInterval = 3 * 60 * 60
        static let hookEvents = [
            "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification",
            "PostToolUse", "Stop", "SessionEnd",
        ]
        static let hookMarker = "notchnull-hook"
        /// How Claude Code's transcript marks a turn the user stopped with Esc.
        static let claudeInterruptPrefix = "[Request interrupted"
        /// Transcript `user` lines that record a local command or its output, not a prompt.
        static let claudeLocalOutputPrefixes = [
            "<command-name>", "<command-message>", "<local-command-", "<bash-input>", "<bash-stdout>", "<bash-stderr>",
        ]
    }

    enum Paths {
        static let home = FileManager.default.homeDirectoryForCurrentUser
        static let claudeSettings = home.appendingPathComponent(".claude/settings.json")
        static let claudeProjects = home.appendingPathComponent(".claude/projects")
        static let codexSessions = home.appendingPathComponent(".codex/sessions")
        static let opencodeDB = home.appendingPathComponent(".local/share/opencode/opencode.db")
        static let opencodePlugin = home.appendingPathComponent(".config/opencode/plugins/notchnull.js")
        static let downloads = home.appendingPathComponent("Downloads")

        static var support: URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = base.appendingPathComponent(appName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        static var tray: URL { support.appendingPathComponent("Tray", isDirectory: true) }
        static var trayIndex: URL { support.appendingPathComponent("tray.json") }
        static var clipboardStore: URL { support.appendingPathComponent("clipboard.sealed") }
        static var clipboardKey: URL { support.appendingPathComponent("clipboard.key") }
        static var hookScript: URL { support.appendingPathComponent("claude-hook.sh") }
        static var hookToken: URL { support.appendingPathComponent("hook-token") }
    }

    enum Intervals {
        static let clipboardPoll: TimeInterval = 0.5
        static let mediaPoll: TimeInterval = 1
        static let statsSample: TimeInterval = 2
        static let downloadPoll: TimeInterval = 0.5
        static let downloadStalledPoll: TimeInterval = 5
        static let calendarRefresh: TimeInterval = 60
        static let brightnessPoll: TimeInterval = 0.15
        /// Faster polling right after a change, so held brightness keys track without lag.
        static let brightnessActivePoll: TimeInterval = 0.04
        static let batteryEnergySample: TimeInterval = 10
        static let powerModePoll: TimeInterval = 20
        /// Backstop for fullscreen transitions that post no notification; events refresh immediately.
        static let fullscreenPoll: TimeInterval = 2.5
    }

    enum Durations {
        static let hud: TimeInterval = 1.5
        /// macOS dims or restores the display when the power adapter changes; brightness changes
        /// this soon after are the system's, so they do not raise the HUD over the power event.
        static let powerChangeBrightnessQuiet: TimeInterval = 4
        static let charging: TimeInterval = 3.2
        static let accessory: TimeInterval = 4
        /// Devices reported this soon after launch were already attached, so they are not announced.
        static let deviceLaunchQuiet: TimeInterval = 4
        static let screenshot: TimeInterval = 4.5
        static let downloadDone: TimeInterval = 4
        /// A partial file not written for this long is paused, cancelled or left behind.
        static let downloadStalled: TimeInterval = 30
        /// How long the notch asks how long to keep a new download before the fallback applies.
        static let downloadKeep: TimeInterval = 15
        static let downloadTrashed: TimeInterval = 6
        /// The notch counts the last seconds before a download goes to the Trash.
        static let downloadCountdown: TimeInterval = 30
        static let hello: TimeInterval = 3.4
        static let usageWarning: TimeInterval = 5
        static let meetingLead: TimeInterval = 5 * 60
    }

    enum Limits {
        static let clipboardItems = 60
        static let clipboardTextBytes = 200_000
        static let clipboardImageBytes = 6_000_000
        static let trayItems = 40
        static let statsHistory = 40
        static let backups = 12
    }

    enum Clipboard {
        static let ignoredTypes = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
            "com.agilebits.onepassword",
        ]
    }

    enum Meeting {
        static let hosts = [
            "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
            "webex.com", "whereby.com", "around.co", "meet.jit.si", "facetime.apple.com",
        ]
    }

    /// Terminal-like apps we can bring forward when an agent needs attention.
    static let terminalBundleIDs: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "zed": "dev.zed.Zed",
    ]
}
