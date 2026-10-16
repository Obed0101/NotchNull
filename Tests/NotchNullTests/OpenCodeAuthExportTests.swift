import XCTest
@testable import NotchNull

/// The active OpenCode account reader. All fixtures are synthetic; a real `auth export` value is
/// never used, copied or logged.
final class OpenCodeAuthExportTests: XCTestCase {
    private let oauthExport = #"""
    [{"id":"cred_1","integrationID":"opencode","label":"Default","active":true,
      "value":{"type":"oauth","methodID":"device","refresh":"ignored","access":"access-token",
               "expires":1794668022829,"metadata":{"email":"a@b.c"}}}]
    """#

    func testParsesOAuthAndKeyCredentialsAndKeepsOnlyWhatIsNeeded() throws {
        let oauth = try XCTUnwrap(OpenCodeAuthExport.parse(Data(oauthExport.utf8)))
        XCTAssertEqual(oauth, [.init(integrationID: "opencode", label: "Default", active: true, token: "access-token")])
        XCTAssertEqual(OpenCodeAuthExport.select(oauth), .account(token: "access-token", label: "Default"))

        let key = #"[{"integrationID":"opencode","label":"Work","active":true,"value":{"type":"key","key":"key-token"}}]"#
        XCTAssertEqual(OpenCodeAuthExport.select(try XCTUnwrap(OpenCodeAuthExport.parse(Data(key.utf8)))), .account(token: "key-token", label: "Work"))
    }

    func testSelectsTheActiveAccountRegardlessOfExportOrder() throws {
        let json = #"""
        [{"integrationID":"opencode","label":"Old","active":false,"value":{"type":"key","key":"old"}},
         {"integrationID":"opencode","label":"New","active":true,"value":{"type":"key","key":"new"}}]
        """#
        XCTAssertEqual(OpenCodeAuthExport.select(try XCTUnwrap(OpenCodeAuthExport.parse(Data(json.utf8)))), .account(token: "new", label: "New"))
    }

    func testTwoActiveAccountsAreAmbiguous() throws {
        let json = #"""
        [{"integrationID":"opencode","label":"A","active":true,"value":{"type":"key","key":"a"}},
         {"integrationID":"opencode-go","label":"B","active":true,"value":{"type":"oauth","access":"b"}}]
        """#
        XCTAssertEqual(OpenCodeAuthExport.select(try XCTUnwrap(OpenCodeAuthExport.parse(Data(json.utf8)))), .ambiguous)
    }

    func testUnrelatedInactiveAndExternalCredentialsAreNoAccount() throws {
        let unrelated = #"[{"integrationID":"anthropic","label":"x","active":true,"value":{"type":"key","key":"a"}}]"#
        XCTAssertEqual(OpenCodeAuthExport.select(try XCTUnwrap(OpenCodeAuthExport.parse(Data(unrelated.utf8)))), .noAccount)

        let external = #"[{"integrationID":"opencode","label":"x","active":true,"value":{"type":"external","methodID":"m"}}]"#
        let parsed = try XCTUnwrap(OpenCodeAuthExport.parse(Data(external.utf8)))
        XCTAssertNil(parsed.first?.token)
        XCTAssertEqual(OpenCodeAuthExport.select(parsed), .noAccount)

        let inactive = #"[{"integrationID":"opencode","label":"x","active":false,"value":{"type":"key","key":"a"}}]"#
        XCTAssertEqual(OpenCodeAuthExport.select(try XCTUnwrap(OpenCodeAuthExport.parse(Data(inactive.utf8)))), .noAccount)
    }

    func testMalformedExportIsUnreadableButAnEmptyOneIsValid() {
        XCTAssertNil(OpenCodeAuthExport.parse(Data("{not json".utf8)))
        XCTAssertNil(OpenCodeAuthExport.parse(Data("{}".utf8)))
        XCTAssertEqual(OpenCodeAuthExport.parse(Data("[]".utf8))?.isEmpty, true)
    }

    func testResolveReportsAMissingCliAndTurnsEveryRunFailureIntoNoAccount() throws {
        XCTAssertEqual(OpenCodeAuthExport.resolve(executable: nil, run: { _ in nil }), .cliMissing)
        let executable = URL(fileURLWithPath: "/usr/bin/true")
        XCTAssertEqual(OpenCodeAuthExport.resolve(executable: executable, run: { _ in nil }), .noAccount)
        XCTAssertEqual(OpenCodeAuthExport.resolve(executable: executable, run: { _ in Data("nope".utf8) }), .noAccount)
        XCTAssertEqual(OpenCodeAuthExport.resolve(executable: executable, run: { _ in Data(oauthExport.utf8) }), .account(token: "access-token", label: "Default"))
    }

    func testSubprocessFailuresAreSafeAndNeverLeakASecret() {
        // A nonzero exit.
        XCTAssertNil(OpenCodeAuthExport.run(executable: URL(fileURLWithPath: "/usr/bin/false")))
        // Output past the cap: `yes` prints forever, so the reader must stop and kill it.
        XCTAssertNil(OpenCodeAuthExport.run(executable: URL(fileURLWithPath: "/usr/bin/yes"), timeout: 5, maxBytes: 10_000))
        // The deadline: a command that never answers is terminated, not waited on.
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("nn-slow-\(UUID().uuidString)")
        try? "#!/bin/sh\nsleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }
        XCTAssertNil(OpenCodeAuthExport.run(executable: script, timeout: 0.5))
    }
}
