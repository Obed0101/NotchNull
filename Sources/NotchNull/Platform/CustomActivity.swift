import Combine
import SwiftUI

/// Something your script, agent or widget shows beside the notch.
struct CustomActivity: Identifiable, Equatable {
    let id: String
    var symbol: String?
    var tint: JSONValue?
    /// Short text beside the symbol, left of the camera.
    var leading: String?
    /// Short text right of the camera.
    var trailing: String?
    /// A banner row under the notch.
    var title: String?
    var subtitle: String?
    /// 0…1 draws a progress bar under the banner.
    var progress: Double?
    /// Widget-style views for the two sides, instead of text.
    var leadingView: JSONValue?
    var trailingView: JSONValue?
    var scope: JSONValue = .null
    /// Clicking the activity performs this (`{"open": "https://…"}`, `{"run": "…"}`, `{"copy": "…"}`).
    var action: JSONValue?
    var expiresAt: Date?
    var widgetID: String?
    var updatedAt = Date()

    var hasBanner: Bool { title != nil || subtitle != nil }

    /// `POST /v1/activity` and `notchnull show`.
    init?(payload: JSONValue) {
        guard let object = payload.object else { return nil }
        id = object["id"]?.string ?? "default"
        symbol = object["symbol"]?.string
        tint = object["tint"]
        leading = object["leading"]?.string
        trailing = object["trailing"]?.string
        title = object["title"]?.string
        subtitle = object["subtitle"]?.string
        progress = object["progress"]?.double.map { min(max($0, 0), 1) }
        leadingView = object["leadingView"]
        trailingView = object["trailingView"]
        action = object["action"]
        let persistent = object["persistent"]?.bool ?? false
        let seconds = object["duration"]?.double ?? 4
        expiresAt = persistent ? nil : Date().addingTimeInterval(min(max(seconds, 0.5), 3600))
        guard symbol != nil || leading != nil || trailing != nil || hasBanner || leadingView != nil || trailingView != nil else { return nil }
    }

    /// A widget's `wing` block.
    init(widget: LoadedWidget, wing: [String: JSONValue], scope: JSONValue) {
        id = "widget:\(widget.id)"
        widgetID = widget.id
        symbol = wing["symbol"]?.string ?? widget.definition?.symbol
        tint = wing["tint"] ?? widget.definition?.tint
        leading = wing["leadingText"].map { Template.text($0, in: scope) }
        trailing = wing["trailingText"].map { Template.text($0, in: scope) }
        title = wing["title"].map { Template.text($0, in: scope) }
        subtitle = wing["subtitle"].map { Template.text($0, in: scope) }
        progress = wing["progress"].flatMap { Template.resolve($0, in: scope)?.double }.map { min(max($0, 0), 1) }
        leadingView = wing["leading"]
        trailingView = wing["trailing"]
        action = wing["action"]
        self.scope = scope
    }

    static func == (lhs: CustomActivity, rhs: CustomActivity) -> Bool {
        lhs.id == rhs.id && lhs.symbol == rhs.symbol && lhs.leading == rhs.leading && lhs.trailing == rhs.trailing
            && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.progress == rhs.progress
            && lhs.scope == rhs.scope && lhs.tint == rhs.tint && lhs.expiresAt == rhs.expiresAt
    }
}

/// Every custom activity that is up; the most recent one owns the notch.
@MainActor
final class CustomActivityStore: ObservableObject {
    static let shared = CustomActivityStore()

    @Published private(set) var items: [String: CustomActivity] = [:]
    private var expiryTimer: Timer?
    private let center: ActivityCenter
    /// Tests use a private store and must not rewrite the user's status file.
    private let writesStatus: Bool

    init(center: ActivityCenter, writesStatus: Bool = true) {
        self.center = center
        self.writesStatus = writesStatus
    }

    convenience init() {
        self.init(center: ActivityCenter.shared)
    }

    var current: CustomActivity? { items.values.max { $0.updatedAt < $1.updatedAt } }

    func set(_ activity: CustomActivity) {
        var activity = activity
        if let existing = items[activity.id], existing == activity { return }
        activity.updatedAt = Date()
        withAnimation(Motion.value) { items[activity.id] = activity }
        refresh()
    }

    func remove(id: String) {
        guard items[id] != nil else { return }
        items[id] = nil
        refresh()
    }

    func removeAll() {
        items = [:]
        refresh()
    }

    private func refresh() {
        let now = Date()
        items = items.filter { ($0.value.expiresAt ?? .distantFuture) > now }
        center.setPersistent(.custom, active: !items.isEmpty)
        expiryTimer?.invalidate()
        if let next = items.values.compactMap(\.expiresAt).min() {
            expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, next.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        if writesStatus { NotchStatus.write() }
    }

    /// Size of the custom activity's body, which depends on what it shows.
    var layout: ActivityLayout {
        guard let current else { return ActivityLayout(wing: 70) }
        if current.hasBanner {
            return ActivityLayout(wing: 40, extraHeight: current.progress == nil ? 46 : 56, minWidth: 420, interactive: current.action != nil)
        }
        return ActivityLayout(wing: 70, extraHeight: current.progress == nil ? 0 : 10)
    }

    /// Clicking a custom activity: its action, or the panel when it has none.
    func performCurrentAction() -> Bool {
        guard let current, let action = current.action else { return false }
        WidgetStore.shared.perform(action, widget: current.widgetID ?? "", scope: current.scope)
        return true
    }
}

struct CustomActivityView: View {
    @EnvironmentObject private var store: CustomActivityStore

    var body: some View {
        let activity = store.current
        let tint = WidgetStyle.color(activity?.tint) ?? Preferences.shared.accent
        WingsLayout {
            HStack(spacing: 6) {
                if let node = activity?.leadingView {
                    WidgetNodeView(node: node, scope: activity?.scope ?? .null, widgetID: activity?.widgetID ?? "", tint: tint)
                } else {
                    if let symbol = activity?.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    if let leading = activity?.leading {
                        Text(leading)
                            .font(Theme.Typeface.wing)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .contentTransition(.numericText())
                    }
                }
            }
        } trailing: {
            if let node = activity?.trailingView {
                WidgetNodeView(node: node, scope: activity?.scope ?? .null, widgetID: activity?.widgetID ?? "", tint: tint)
            } else if let trailing = activity?.trailing {
                Text(trailing)
                    .font(Theme.Typeface.wing)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .contentTransition(.numericText())
            }
        } bottom: {
            if let activity, activity.hasBanner || activity.progress != nil {
                VStack(spacing: 6) {
                    if activity.hasBanner {
                        BannerText(title: activity.title ?? "", subtitle: activity.subtitle ?? "")
                    }
                    if let progress = activity.progress {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.track)
                                Capsule().fill(tint).frame(width: max(3, proxy.size.width * progress))
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 2)
                        .animation(Motion.value, value: progress)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
        }
        .animation(Motion.state, value: activity)
        .accessibilityElement(children: .combine)
    }
}
