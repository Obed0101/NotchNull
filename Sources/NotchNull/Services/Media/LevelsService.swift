import AppKit
import ApplicationServices
import Combine
import CoreAudio
import SwiftUI

/// Volume and brightness levels for the HUD. Observes changes from any source; when
/// "Replace system HUD" is on and Accessibility is granted, a media-key tap consumes the keys so
/// only the notch HUD appears.
@MainActor
final class LevelsService: ObservableObject {
    enum Kind { case volume, brightness }

    fileprivate enum MediaKeyCode: Int32 {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    struct Level: Equatable {
        var kind: Kind
        var value: Float
        var muted: Bool
    }

    @Published private(set) var level = Level(kind: .volume, value: 0, muted: false)
    @Published private(set) var keyTapActive = false
    /// Current output volume (0 when muted) for in-panel sliders.
    @Published private(set) var outputVolume: Float = 0
    /// Every notch is in fullscreen concealment, so nothing here can show a level.
    var notchIsHidden = false

    private var device: AudioDeviceID?
    private var lastVolume: Float?
    private var lastMuted = false
    private var lastBrightness: Float?
    private var brightnessTimer: Timer?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var cancellables: Set<AnyCancellable> = []
    private let listenerQueue = DispatchQueue(label: "dev.notchnull.audio-listener")
    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { self?.volumeChanged() } }
    }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { self?.attachToDefaultDevice() } }
    }

    static let step: Float = 1 / 16
    static let fineStep: Float = 1 / 64

    func start() {
        var address = AudioVolume.defaultDeviceAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, deviceListener)
        attachToDefaultDevice()

        lastBrightness = DisplayBrightness.brightness()
        scheduleBrightnessPoll(every: Constants.Intervals.brightnessPoll)

        Preferences.shared.$replaceSystemHUD
            .combineLatest(Preferences.shared.$hudEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] replace, enabled in self?.configureTap(enabled && replace) }
            .store(in: &cancellables)
    }

    /// Fixture entry point for snapshot rendering.
    func preview(_ level: Level) {
        self.level = level
        outputVolume = level.value
    }

    /// Re-evaluates the key tap after the user grants Accessibility.
    func retryKeyTap() {
        configureTap(Preferences.shared.hudEnabled && Preferences.shared.replaceSystemHUD)
    }

    // MARK: Volume

    private func attachToDefaultDevice() {
        if let device {
            var volume = AudioVolume.volumeAddress
            var mute = AudioVolume.muteAddress
            AudioObjectRemovePropertyListenerBlock(device, &volume, listenerQueue, volumeListener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, listenerQueue, volumeListener)
        }
        device = AudioVolume.defaultOutputDevice()
        guard let device else { return }
        var volume = AudioVolume.volumeAddress
        var mute = AudioVolume.muteAddress
        AudioObjectAddPropertyListenerBlock(device, &volume, listenerQueue, volumeListener)
        AudioObjectAddPropertyListenerBlock(device, &mute, listenerQueue, volumeListener)
        lastVolume = AudioVolume.volume(of: device)
        lastMuted = AudioVolume.isMuted(device)
        outputVolume = lastMuted ? 0 : (lastVolume ?? 0)
    }

    private func volumeChanged() {
        guard let device, let volume = AudioVolume.volume(of: device) else { return }
        let muted = AudioVolume.isMuted(device)
        defer {
            lastVolume = volume
            lastMuted = muted
            outputVolume = muted ? 0 : volume
        }
        guard volume != lastVolume || muted != lastMuted else { return }
        show(Level(kind: .volume, value: volume, muted: muted))
    }

    func adjustVolume(by delta: Float) {
        guard let device, let current = AudioVolume.volume(of: device) else { return }
        let next = max(0, min(1, (current / abs(delta)).rounded() * abs(delta) + delta))
        if AudioVolume.isMuted(device) { AudioVolume.setMuted(false, on: device) }
        AudioVolume.setVolume(next, on: device)
        show(Level(kind: .volume, value: next, muted: false))
    }

    func toggleMute() {
        guard let device else { return }
        let muted = !AudioVolume.isMuted(device)
        AudioVolume.setMuted(muted, on: device)
        show(Level(kind: .volume, value: AudioVolume.volume(of: device) ?? 0, muted: muted))
    }

    func setVolume(_ value: Float) {
        guard let device else { return }
        if AudioVolume.isMuted(device) { AudioVolume.setMuted(false, on: device) }
        AudioVolume.setVolume(value, on: device)
        outputVolume = value
        lastVolume = value
        lastMuted = false
    }

    var currentVolume: Float { device.flatMap(AudioVolume.volume(of:)) ?? 0 }

    // MARK: Brightness

    private var brightnessActiveUntil: Date?
    private var brightnessQuietUntil: Date?

    /// The power adapter was plugged in or out: the display brightness macOS changes because of it
    /// is not the user's, so it stays out of the notch for a moment. Brightness keys still show.
    func powerSourceChanged() {
        brightnessQuietUntil = Date().addingTimeInterval(Constants.Durations.powerChangeBrightnessQuiet)
        ActivityCenter.shared.dismiss(.brightness)
    }

    private func scheduleBrightnessPoll(every interval: TimeInterval) {
        brightnessTimer?.invalidate()
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBrightness() }
        }
        brightnessTimer?.tolerance = interval * 0.2
    }

    /// Polls slowly while idle; after a change it polls fast for a moment so held keys track closely.
    private func pollBrightness() {
        guard Preferences.shared.hudEnabled, let value = DisplayBrightness.brightness() else { return }
        defer { lastBrightness = value }
        let now = Date()
        guard let last = lastBrightness, abs(last - value) > 0.004 else {
            if let until = brightnessActiveUntil, now > until {
                brightnessActiveUntil = nil
                scheduleBrightnessPoll(every: Constants.Intervals.brightnessPoll)
            }
            return
        }
        if brightnessActiveUntil == nil { scheduleBrightnessPoll(every: Constants.Intervals.brightnessActivePoll) }
        brightnessActiveUntil = now.addingTimeInterval(1.2)
        if let quiet = brightnessQuietUntil, now < quiet { return }
        show(Level(kind: .brightness, value: value, muted: false))
    }

    func adjustBrightness(by delta: Float) {
        guard let current = DisplayBrightness.brightness() else { return }
        let next = max(0, min(1, (current / abs(delta)).rounded() * abs(delta) + delta))
        DisplayBrightness.setBrightness(next)
        lastBrightness = next
        show(Level(kind: .brightness, value: next, muted: false))
    }

    private func show(_ next: Level) {
        guard Preferences.shared.hudEnabled else { return }
        withAnimation(Motion.value) { level = next }
        ActivityCenter.shared.post(next.kind == .volume ? .volume : .brightness, for: Constants.Durations.hud)
    }

    // MARK: Media key tap

    private func configureTap(_ enabled: Bool) {
        if !enabled {
            removeTap()
            return
        }
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            keyTapActive = false
            return
        }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            // Intercept at the same HID boundary used by BoringNotch. This is before the
            // window-server/session handling that causes macOS's BezelServices HUD to appear.
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyCallback,
            userInfo: refcon
        ) else {
            Log.media.error("Media key tap could not be created")
            keyTapActive = false
            return
        }
        tap = port
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        keyTapActive = true
        Log.media.info("Media key tap active")
    }

    private func removeTap() {
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        tapSource = nil
        keyTapActive = false
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the key was handled and must be swallowed.
    fileprivate func handleMediaKey(code: MediaKeyCode, fine: Bool) -> Bool {
        guard !notchIsHidden else { return false }
        let step = fine ? Self.fineStep : Self.step
        switch code {
        case .soundUp:
            guard device.flatMap(AudioVolume.volume(of:)) != nil else { return false }
            adjustVolume(by: step)
        case .soundDown:
            guard device.flatMap(AudioVolume.volume(of:)) != nil else { return false }
            adjustVolume(by: -step)
        case .mute:
            toggleMute()
        case .brightnessUp:
            guard DisplayBrightness.brightness() != nil else { return false }
            adjustBrightness(by: step)
        case .brightnessDown:
            guard DisplayBrightness.brightness() != nil else { return false }
            adjustBrightness(by: -step)
        }
        return true
    }
}

private let mediaKeyCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<LevelsService>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { service.reenableTap() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let data = nsEvent.data1
    let code = Int32((data & 0xFFFF_0000) >> 16)
    let flags = data & 0x0000_FFFF
    let isDown = ((flags & 0xFF00) >> 8) == 0x0A
    guard let keyCode = LevelsService.MediaKeyCode(rawValue: code) else {
        return Unmanaged.passUnretained(event)
    }
    // Consume only the key-down event. Passing key-up through avoids leaving the system's
    // media-key state pressed while still preventing the native HUD from being shown.
    guard isDown else { return Unmanaged.passUnretained(event) }
    let fine = nsEvent.modifierFlags.contains([.option, .shift])
    let handled = MainActor.assumeIsolated { service.handleMediaKey(code: keyCode, fine: fine) }
    return handled ? nil : Unmanaged.passUnretained(event)
}
