import Foundation

/// The active OpenCode account, read through OpenCode's own `opencode auth export`.
///
/// The export contains secrets, so it stays in memory: NotchNull never writes it, logs it, puts it
/// in diagnostics or snapshots, and ignores the refresh token, expiry and metadata. It is read-only
/// and interpreted: NotchNull never logs in, switches, refreshes or deletes an account — it only
/// picks the one OpenCode already marked active, and refuses to guess when that is ambiguous.
enum OpenCodeAuthExport {
    /// Integration ids that carry the OpenCode Console sign-in. The modern server uses `opencode`;
    /// `opencode-go` is kept for older databases that stored the subscription under that id.
    static let integrationIDs = ["opencode", "opencode-go"]

    /// The fields NotchNull reads from one exported credential; everything else is ignored.
    struct Credential: Equatable, Sendable {
        var integrationID: String
        var label: String
        var active: Bool
        /// The bearer token: `access` for an OAuth credential, `key` for an API-key credential.
        /// Nil for an `external` credential, whose secret lives outside OpenCode.
        var token: String?
    }

    /// The single active account chosen for usage, or why none can be.
    enum Selection: Equatable, Sendable {
        /// Exactly one active Console account with a usable token.
        case account(token: String, label: String)
        /// The `opencode` CLI was not found on this Mac.
        case cliMissing
        /// The CLI ran but gave nothing usable: unreadable output, no active Console account, or an
        /// active account whose secret lives elsewhere.
        case noAccount
        /// More than one active Console account; NotchNull will not pick one.
        case ambiguous
    }

    /// Pure: the credentials NotchNull understands, or nil when the JSON is not an export at all
    /// (an empty array is a valid, empty export).
    static func parse(_ data: Data) -> [Credential]? {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let entries = root as? [[String: Any]] else { return nil }
        return entries.compactMap { entry in
            guard let integrationID = entry["integrationID"] as? String,
                  let active = entry["active"] as? Bool else { return nil }
            let value = entry["value"] as? [String: Any]
            let raw: String? = switch value?["type"] as? String {
            case "oauth": value?["access"] as? String
            case "key": value?["key"] as? String
            default: nil
            }
            let token = (raw?.isEmpty == false) ? raw : nil
            return Credential(
                integrationID: integrationID,
                label: entry["label"] as? String ?? "Default",
                active: active,
                token: token
            )
        }
    }

    /// Pure: picks the single active Console credential. Order in the export is never trusted — only
    /// the `active` flag is.
    static func select(_ credentials: [Credential]) -> Selection {
        let matches = credentials.filter { integrationIDs.contains($0.integrationID) && $0.active && $0.token != nil }
        guard !matches.isEmpty else { return .noAccount }
        guard matches.count == 1, let token = matches[0].token else { return .ambiguous }
        return .account(token: token, label: matches[0].label)
    }

    /// The resolution seam: given the CLI's location (if any) and a way to run it, decide. Tests pass
    /// a fixed executable and runner so they never spawn a process or need a real account.
    static func resolve(executable: URL?, run: (URL) -> Data?) -> Selection {
        guard let executable else { return .cliMissing }
        guard let data = run(executable), let credentials = parse(data) else { return .noAccount }
        return select(credentials)
    }

    /// The real resolution: find the CLI, run `auth export`, parse and pick.
    static func resolve(
        home: URL = Constants.Paths.home,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Selection {
        resolve(executable: executable(home: home, environment: environment), run: { run(executable: $0) })
    }

    /// Where the `opencode` CLI may live, mirroring `CodexLimitsClient`.
    static func executable(
        home: URL = Constants.Paths.home,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates = [
            home.appendingPathComponent(".opencode/bin/opencode").path,
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
        ]
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/opencode" }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Runs the CLI and returns its standard output. Every failure — a launch error, the deadline,
    /// output past `maxBytes`, or a nonzero exit — is nil, so a caller can never take a partial or
    /// error stream for credentials. Runs on a utility queue; the arguments are a fixed list, never
    /// a shell string.
    static func run(
        executable: URL,
        arguments: [String] = ["auth", "export"],
        timeout: TimeInterval = 15,
        maxBytes: Int = 1_000_000
    ) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        do { try process.run() } catch { return nil }

        let buffer = PipeBuffer()
        let reading = DispatchSemaphore(value: 0)
        let handle = stdout.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                if buffer.data.count + chunk.count > maxBytes { buffer.overflowed = true; break }
                buffer.data.append(chunk)
            }
            reading.signal()
        }

        let finished = reading.wait(timeout: .now() + timeout) == .success
        if !finished || buffer.overflowed { process.terminate() }
        process.waitUntilExit()
        guard finished, !buffer.overflowed, process.terminationStatus == 0 else { return nil }
        return buffer.data
    }
}

/// Carrier for the pipe reader, which fills it off the calling thread.
private final class PipeBuffer: @unchecked Sendable {
    var data = Data()
    var overflowed = false
}
