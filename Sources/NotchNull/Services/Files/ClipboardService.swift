import AppKit
import Combine
import CryptoKit
import Security
import SwiftUI

struct ClipItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, link, image, file, color }

    let id: UUID
    let kind: Kind
    var text: String?
    var imagePNG: Data?
    var fileURLs: [URL]?
    var sourceApp: String?
    var sourceBundle: String?
    var date: Date
    var pinned: Bool

    var preview: String {
        switch kind {
        case .text, .link, .color: (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: "Image"
        case .file: fileURLs?.map(\.lastPathComponent).joined(separator: ", ") ?? "File"
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return preview.localizedCaseInsensitiveContains(query) || (sourceApp?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

/// Clipboard history. Password-manager and transient pasteboard types are skipped; history is
/// sealed with AES-GCM using a key kept in the login keychain.
@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var lastCopiedID: UUID?

    private var timer: Timer?
    private var changeCount = NSPasteboard.general.changeCount
    private var saveWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    func start() {
        try? FileManager.default.removeItem(at: Self.openScratch)
        items = load()
        Preferences.shared.$clipboardEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.setPolling(enabled) }
            .store(in: &cancellables)
    }

    /// Fixture entry point for snapshot rendering.
    func preview(_ items: [ClipItem], copied: UUID? = nil) {
        self.items = items
        lastCopiedID = copied
    }

    private func setPolling(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        changeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: Constants.Intervals.clipboardPoll, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !types.contains(where: { Constants.Clipboard.ignoredTypes.contains($0) }) else { return }
        guard let item = Self.capture(pasteboard) else { return }
        insert(item)
    }

    private func insert(_ item: ClipItem) {
        withAnimation(Motion.state) {
            if let existing = items.firstIndex(where: { $0.kind == item.kind && $0.text == item.text && $0.imagePNG == item.imagePNG && $0.fileURLs == item.fileURLs }) {
                var moved = items.remove(at: existing)
                moved.date = item.date
                items.insert(moved, at: 0)
            } else {
                items.insert(item, at: 0)
            }
            trim()
        }
        scheduleSave()
    }

    private func trim() {
        var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1
            return unpinned <= Constants.Limits.clipboardItems
        }
    }

    func copy(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text, .link, .color:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let data = item.imagePNG { pasteboard.setData(data, forType: .png) }
        case .file:
            pasteboard.writeObjects((item.fileURLs ?? []) as [NSURL])
        }
        changeCount = pasteboard.changeCount
        withAnimation(Motion.state) { lastCopiedID = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard self?.lastCopiedID == item.id else { return }
            withAnimation(Motion.state) { self?.lastCopiedID = nil }
        }
    }

    /// Opens an item without copying it: files in their app, a link in the browser, an image or
    /// text as a temporary copy in the app that views it. False when there is nothing to open
    /// (the files are gone).
    @discardableResult
    func open(_ item: ClipItem) -> Bool {
        let targets = Self.openTargets(for: item, scratch: Self.openScratch)
        targets.forEach { NSWorkspace.shared.open($0) }
        return !targets.isEmpty
    }

    /// Where the temporary copy of an opened image or text lives; emptied before each use and
    /// when the app starts.
    static let openScratch = FileManager.default.temporaryDirectory.appendingPathComponent("NotchNull-clipboard", isDirectory: true)

    /// What opening an item shows. An image or text is written into `scratch`, which holds one
    /// item at a time: history is encrypted on disk, so an earlier copy must not linger there.
    static func openTargets(for item: ClipItem, scratch: URL) -> [URL] {
        let fm = FileManager.default
        try? fm.removeItem(at: scratch)
        switch item.kind {
        case .file:
            return (item.fileURLs ?? []).filter { fm.fileExists(atPath: $0.path) }
        case .link:
            if let url = URL(string: item.preview), url.scheme != nil { return [url] }
            return temporaryCopy(Data((item.text ?? "").utf8), named: "Clipboard.txt", in: scratch)
        case .image:
            return item.imagePNG.map { temporaryCopy($0, named: "Clipboard.png", in: scratch) } ?? []
        case .text, .color:
            guard let text = item.text, !text.isEmpty else { return [] }
            return temporaryCopy(Data(text.utf8), named: "Clipboard.txt", in: scratch)
        }
    }

    private static func temporaryCopy(_ data: Data, named name: String, in scratch: URL) -> [URL] {
        let file = scratch.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            return [file]
        } catch {
            Log.files.error("Clipboard item could not be opened: \(error.localizedDescription)")
            return []
        }
    }

    /// Sends ⌘V to the app in front. Posting keyboard events needs Accessibility; without it the
    /// item stays copied and nothing is typed.
    @discardableResult
    static func pasteIntoFrontApp() -> Bool {
        guard Permissions.accessibilityGranted else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(9) // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(Motion.state) { items[index].pinned.toggle() }
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        withAnimation(Motion.state) { items.removeAll { $0.id == item.id } }
        scheduleSave()
    }

    func clearUnpinned() {
        withAnimation(Motion.state) { items.removeAll { !$0.pinned } }
        scheduleSave()
    }

    // MARK: Capture

    private static func capture(_ pasteboard: NSPasteboard) -> ClipItem? {
        let front = NSWorkspace.shared.frontmostApplication
        let base = { (kind: ClipItem.Kind) in
            ClipItem(id: UUID(), kind: kind, sourceApp: front?.localizedName, sourceBundle: front?.bundleIdentifier, date: Date(), pinned: false)
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            var item = base(.file)
            item.fileURLs = urls
            return item
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), let png = normalizedPNG(data) {
            var item = base(.image)
            item.imagePNG = png
            return item
        }
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard string.utf8.count <= Constants.Limits.clipboardTextBytes else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: ClipItem.Kind
            if isColor(trimmed) {
                kind = .color
            } else if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, !trimmed.contains(" ") {
                kind = .link
            } else {
                kind = .text
            }
            var item = base(kind)
            item.text = string
            return item
        }
        return nil
    }

    static func isColor(_ text: String) -> Bool {
        text.range(of: "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$", options: .regularExpression) != nil
    }

    private static func normalizedPNG(_ data: Data) -> Data? {
        guard let image = NSImage(data: data), let rep = image.representations.first else { return nil }
        let maxSide: CGFloat = 1600
        let width = CGFloat(rep.pixelsWide), height = CGFloat(rep.pixelsHigh)
        let scale = min(1, maxSide / max(width, height, 1))
        let size = NSSize(width: max(1, width * scale), height: max(1, height * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]), png.count <= Constants.Limits.clipboardImageBytes else { return nil }
        return png
    }

    // MARK: Sealed storage

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = items
        let work = DispatchWorkItem {
            guard let key = Self.storeKey(), let data = try? JSONEncoder().encode(snapshot),
                  let sealed = try? AES.GCM.seal(data, using: key).combined else { return }
            try? sealed.write(to: Constants.Paths.clipboardStore, options: .atomic)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func load() -> [ClipItem] {
        guard let sealed = try? Data(contentsOf: Constants.Paths.clipboardStore),
              let key = Self.storeKey(),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let data = try? AES.GCM.open(box, using: key),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return [] }
        return decoded
    }

    /// Store key kept in a user-only file (0600) next to the sealed history. A keychain item would
    /// be tied to the code signature and prompt again after every update of an ad-hoc signed build.
    private nonisolated static func storeKey() -> SymmetricKey? {
        let url = Constants.Paths.clipboardKey
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: Constants.Paths.clipboardStore)
            return key
        } catch {
            return nil
        }
    }
}
