import Foundation

/// Read-only account request through Codex's own authenticated client. No prompts or token files.
enum CodexLimitsClient {
    static func executable(home: URL = Constants.Paths.home) -> URL? {
        let candidates = [home.appendingPathComponent(".local/bin/codex").path,
                          "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    /// Called only on the monitor's utility queue; a deadline stops an unresponsive subprocess.
    static func read() -> [String: Any]? {
        guard let executable = executable() else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: deadline)
        defer {
            deadline.cancel()
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        do {
            try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "notchnull", "version": "1.0"]]])
            var buffer = Data()
            while process.isRunning {
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { return nil }
                buffer.append(chunk)
                guard buffer.count <= 2_000_000 else { return nil }
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let id = object["id"] as? Int else { continue }
                    guard object["error"] == nil else { return nil }
                    if id == 1 {
                        try send(["method": "initialized"])
                        try send(["id": 2, "method": "account/rateLimits/read"])
                    } else if id == 2 {
                        guard let result = object["result"] as? [String: Any] else { return nil }
                        return normalize(result)
                    }
                }
            }
        } catch { return nil }
        return nil
    }

    static func normalize(_ result: [String: Any]) -> [String: Any]? {
        let byID = result["rateLimitsByLimitId"] as? [String: Any]
        guard let limits = (byID?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]) else { return nil }
        var payload: [String: Any] = [:]
        payload["plan_type"] = limits["planType"] as? String
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any],
                  let percent = window["usedPercent"] as? NSNumber else { continue }
            var entry: [String: Any] = ["used_percent": percent]
            entry["window_minutes"] = window["windowDurationMins"]
            entry["resets_at"] = window["resetsAt"]
            payload[key] = entry
        }
        return payload["primary"] != nil || payload["secondary"] != nil ? payload : nil
    }
}
