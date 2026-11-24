import XCTest
@testable import NotchNull

final class PlatformTests: XCTestCase {
    private func json(_ text: String) -> JSONValue {
        guard let value = JSONValue.parse(Data(text.utf8)) else {
            XCTFail("Fixture is not valid JSON: \(text)")
            return .null
        }
        return value
    }

    private let scope = JSONValue.object([
        "data": .object([
            "count": .number(3),
            "ratio": .number(0.425),
            "size": .number(1_840_000),
            "name": .string("landing"),
            "items": .array([.object(["title": .string("First")]), .object(["title": .string("Second")])]),
            "empty": .array([]),
        ]),
    ])

    // MARK: Templates

    func testSingleExpressionKeepsTheValueType() {
        XCTAssertEqual(Template.resolve(.string("{{data.ratio}}"), in: scope), .number(0.425))
        XCTAssertEqual(Template.resolve(.string("{{data.items}}"), in: scope)?.array?.count, 2)
    }

    func testMixedTextInterpolatesEveryExpression() {
        XCTAssertEqual(Template.text(.string("{{data.count}} open in {{data.name | upper}}"), in: scope), "3 open in LANDING")
    }

    func testPathsFollowArrayIndexes() {
        XCTAssertEqual(Template.text(.string("{{data.items.1.title}}"), in: scope), "Second")
        XCTAssertEqual(Template.text(.string("{{data.items.9.title}}"), in: scope), "")
    }

    func testFiltersFormatAndChain() {
        XCTAssertEqual(Template.text(.string("{{data.ratio | percent}}"), in: scope), "43%")
        XCTAssertEqual(Template.text(.string("{{data.items | count}}"), in: scope), "2")
        XCTAssertEqual(Template.text(.string("{{data.items | first}}"), in: scope), #"{"title":"First"}"#)
        XCTAssertEqual(Template.resolve(.string("{{data.count | div 4}}"), in: scope), .number(0.75))
        XCTAssertEqual(Template.text(.string("{{data.missing | default 'none'}}"), in: scope), "none")
        XCTAssertEqual(Template.resolve(.string("{{data.empty | not}}"), in: scope), .bool(true))
        XCTAssertFalse(Template.text(.string("{{data.size | bytes}}"), in: scope).isEmpty)
    }

    func testUnknownFiltersAndPathsNeverThrow() {
        XCTAssertEqual(Template.text(.string("{{data.name | sparkle}}"), in: scope), "landing")
        XCTAssertEqual(Template.resolve(.string("{{nothing.here}}"), in: scope), .null)
        XCTAssertEqual(Template.text(.string("unclosed {{data.count"), in: scope), "unclosed {{data.count")
    }

    func testNumbersPrintWithoutTrailingZeros() {
        XCTAssertEqual(JSONValue.number(3.4).text, "3.4")
        XCTAssertEqual(JSONValue.number(0.25).text, "0.25")
        XCTAssertEqual(JSONValue.number(12).text, "12")
        XCTAssertEqual(JSONValue.number(2.999).text, "3")
    }

    func testSerializedNumbersUseTheShortestDecimal() throws {
        let data = try JSONSerialization.data(withJSONObject: JSONValue.object(["speed": .number(1.35), "width": .number(620)]).any, options: [.sortedKeys])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"speed":1.35,"width":620}"#)
    }

    func testTruthinessTreatsEmptyZeroAndFalseAsOff() {
        XCTAssertFalse(JSONValue.null.isTruthy)
        XCTAssertFalse(JSONValue.number(0).isTruthy)
        XCTAssertFalse(JSONValue.string("0").isTruthy)
        XCTAssertFalse(JSONValue.string("False").isTruthy)
        XCTAssertFalse(JSONValue.array([]).isTruthy)
        XCTAssertTrue(JSONValue.string("no failures").isTruthy)
        XCTAssertTrue(JSONValue.number(-1).isTruthy)
    }

    // MARK: Widgets

    func testCommandOutputIsJSONWhenItParsesAndTextOtherwise() {
        XCTAssertEqual(WidgetStore.data(from: " 42\n"), .number(42))
        XCTAssertEqual(WidgetStore.data(from: #"{"ok": true}"#), .object(["ok": .bool(true)]))
        let text = WidgetStore.data(from: "first\nsecond\n")
        XCTAssertEqual(text["text"], .string("first\nsecond"))
        XCTAssertEqual(text["lines"], .array([.string("first"), .string("second")]))
    }

    func testWidgetFileNeedsAViewAndClampsItsSchedule() throws {
        let file = URL(fileURLWithPath: "/tmp/widgets/ci.json")
        XCTAssertThrowsError(try WidgetDefinition(file: file, json: json(#"{"title": "No view"}"#)))
        XCTAssertThrowsError(try WidgetDefinition(file: file, json: json(#"{"view": {"type": "text"}, "enabled": false}"#))) { error in
            XCTAssertEqual(error as? WidgetError, .disabled)
        }
        let definition = try WidgetDefinition(file: file, json: json(#"{"view": {"type": "text"}, "refresh": 0.5, "timeout": 500, "size": "huge"}"#))
        XCTAssertEqual(definition.id, "ci")
        XCTAssertEqual(definition.title, "ci")
        XCTAssertEqual(definition.refresh, 2)
        XCTAssertEqual(definition.timeout, 120)
        XCTAssertEqual(definition.size, .medium)
    }

    func testShellCommandReportsExitStatusAndTimeout() {
        let ok = ShellCommand.run("printf hi", timeout: 5)
        XCTAssertEqual(ok.status, 0)
        XCTAssertEqual(ok.stdout, "hi")
        let failed = ShellCommand.run("echo broken >&2; exit 3", timeout: 5)
        XCTAssertEqual(failed.status, 3)
        XCTAssertEqual(failed.stderr, "broken")
        let slow = ShellCommand.run("sleep 5", timeout: 1)
        XCTAssertTrue(slow.timedOut)
    }

    // MARK: Custom activities

    @MainActor
    func testActivityPayloadNeedsSomethingToShow() {
        XCTAssertNil(CustomActivity(payload: json(#"{"id": "empty"}"#)))
        let banner = CustomActivity(payload: json(#"{"id": "deploy", "title": "Deploying", "progress": 4, "persistent": true}"#))
        XCTAssertEqual(banner?.hasBanner, true)
        XCTAssertEqual(banner?.progress, 1)
        XCTAssertNil(banner?.expiresAt)
        let wing = CustomActivity(payload: json(#"{"symbol": "bell.fill", "duration": 9999}"#))
        XCTAssertEqual(wing?.id, "default")
        XCTAssertLessThanOrEqual(wing?.expiresAt?.timeIntervalSinceNow ?? .infinity, 3600)
    }

    // MARK: Settings file

    @MainActor
    func testEverySettingHasASectionedUniqueKeyInTheReference() throws {
        let keys = SettingsFile.fields.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
        for key in keys {
            XCTAssertEqual(key.split(separator: ".").count, 2, key)
            XCTAssertTrue(SettingsFile.reference.contains("`\(key)`"), key)
        }
        let snapshot = try JSONSerialization.data(withJSONObject: SettingsFile.shared.snapshot().any, options: [.sortedKeys])
        let roundTrip = JSONValue.parse(snapshot)
        XCTAssertEqual(roundTrip, SettingsFile.shared.snapshot())
    }

    @MainActor
    func testPanelHeightReferenceExplainsTheAgentsMaximum() {
        let reference = SettingsFile.reference
        XCTAssertTrue(reference.contains("`size.panelHeight`"))
        XCTAssertTrue(reference.contains("The Agents tab fits its content up to this maximum"))
    }

    func testShortcutsRoundTripThroughText() {
        XCTAssertEqual(KeyShortcut.clipboardDefault.string, "ctrl+cmd+v")
        XCTAssertEqual(KeyShortcut(string: "ctrl+cmd+v"), KeyShortcut.clipboardDefault)
        XCTAssertEqual(KeyShortcut(string: "Cmd + Shift + Space")?.string, "shift+cmd+space")
        XCTAssertNil(KeyShortcut(string: "shift+v"), "shift alone is not a shortcut")
        XCTAssertNil(KeyShortcut(string: "hyper+v"))
    }

    // MARK: Downloads cleanup

    func testKeepChoicesAreOrderedAndForeverHasNoDeadline() {
        let durations = KeepChoice.timed.compactMap(\.duration)
        XCTAssertEqual(durations, durations.sorted())
        XCTAssertEqual(durations.count, KeepChoice.timed.count)
        XCTAssertNil(KeepChoice.forever.duration)
    }

    func testDownloadKindsComeFromTheExtension() {
        XCTAssertEqual(DownloadKind(fileExtension: "dmg"), .installer)
        XCTAssertEqual(DownloadKind(fileExtension: "zip"), .archive)
        XCTAssertEqual(DownloadKind(fileExtension: "pdf"), .pdf)
        XCTAssertEqual(DownloadKind(fileExtension: "png"), .image)
        XCTAssertEqual(DownloadKind(fileExtension: "mov"), .movie)
        XCTAssertEqual(DownloadKind(fileExtension: "bin"), .code)
    }

    func testRemainingTimeStaysShort() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(24), now: now), "0:24")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(42 * 60), now: now), "42m")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(3 * 3600), now: now), "3h")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(2 * 86_400 + 3 * 3600), now: now), "2d 3h")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(9 * 86_400), now: now), "9d")
        XCTAssertEqual(Formatting.remaining(until: now.addingTimeInterval(-5), now: now), "0:00")
    }

    func testDeadlineSaysTodayOrTomorrowWhenClose() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9))!
        XCTAssertTrue(Formatting.deadline(calendar.date(byAdding: .hour, value: 3, to: now)!, now: now).hasPrefix("Today"))
        XCTAssertTrue(Formatting.deadline(calendar.date(byAdding: .hour, value: 26, to: now)!, now: now).hasPrefix("Tomorrow"))
        XCTAssertFalse(Formatting.deadline(calendar.date(byAdding: .day, value: 20, to: now)!, now: now).contains(":"))
    }

    // MARK: Recipes and examples shipped in the skill

    private func settingKeys(of recipe: NotchRecipe) -> [String] {
        (recipe.settings.object ?? [:]).flatMap { section, value in
            (value.object ?? [:]).keys.map { "\(section).\($0)" }
        }
    }

    @MainActor
    func testSetupOffersMinimalBalancedCompleteInOrderWithPreviews() {
        let presets = Recipes.load(.preset)
        XCTAssertEqual(presets.map(\.id), ["minimal", "balanced", "complete"])
        for preset in presets {
            XCTAssertFalse(preset.summary.isEmpty, preset.id)
            XCTAssertNotNil(preset.preview, "\(preset.id) has no rendered preview")
        }
    }

    @MainActor
    func testEveryPresetAndLookOnlyUsesKnownSettings() {
        let known = Set(SettingsFile.fields.map(\.key))
        let recipes = Recipes.load(.preset) + Recipes.load(.theme)
        XCTAssertGreaterThanOrEqual(Recipes.load(.theme).count, 3)
        for recipe in recipes {
            let keys = settingKeys(of: recipe)
            XCTAssertFalse(keys.isEmpty, recipe.id)
            for key in keys { XCTAssertTrue(known.contains(key), "\(recipe.id) sets unknown \(key)") }
        }
    }

    @MainActor
    func testLooksOnlyChangeTheLookSection() {
        for theme in Recipes.load(.theme) {
            XCTAssertEqual(theme.settings.object?.keys.sorted(), ["look"], theme.id)
        }
    }

    @MainActor
    func testEveryExampleIsAValidDescribedWidget() throws {
        let examples = Recipes.examples()
        XCTAssertGreaterThanOrEqual(examples.count, 5)
        for example in examples {
            XCTAssertFalse(example.summary.isEmpty, "\(example.id) has no description")
            let data = try Data(contentsOf: example.file)
            XCTAssertNoThrow(try WidgetDefinition(file: example.file, json: json(String(decoding: data, as: UTF8.self))), example.id)
        }
    }
}
