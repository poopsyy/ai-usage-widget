import Foundation
import UsageCore

final class IntegrationTests {
    var directory: URL!
    var settings: URL!
    var helper: URL!
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("AI Usage '\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = directory.appendingPathComponent("config/settings.json")
        helper = directory.appendingPathComponent("helper")
        try Data("helper".utf8).write(to: helper)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: root).write(to: settings)
    }
    func read() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any] }
    var integration: ClaudeIntegration { ClaudeIntegration(directory: directory.appendingPathComponent("data"), settingsURL: settings) }

    func testInstallAndRestorePreserveOtherChanges() throws {
        try write(["theme": "dark", "statusLine": ["type": "command", "command": "printf 'original'", "padding": 2]])
        try integration.install(helper: helper)
        expectTrue(integration.isInstalled)
        var root = try read()
        expectEqual((root["statusLine"] as? [String: Any])?["padding"] as? Int, 2)
        root["theme"] = "light"
        try write(root)
        try integration.restore()
        expectFalse(integration.isInstalled)
        let restored = try read()
        expectEqual(restored["theme"] as? String, "light")
        expectEqual((restored["statusLine"] as? [String: Any])?["command"] as? String, "printf 'original'")
    }
    func testFreshInstallIsIdempotentAndRestorable() throws {
        try integration.install(helper: helper)
        let before = try Data(contentsOf: settings)
        try integration.install(helper: helper)
        expectEqual(try Data(contentsOf: settings), before)
        expectTrue(integration.isInstalled)
        try integration.restore()
        expectNil(try read()["statusLine"])
    }
    func testRefusesToOverwriteChangedStatusLine() throws {
        try write(["statusLine": ["type": "command", "command": "old"]])
        try integration.install(helper: helper)
        try write(["statusLine": ["type": "command", "command": "new"]])
        let before = try Data(contentsOf: settings)
        expectThrows(try integration.restore())
        expectThrows(try integration.install(helper: helper))
        expectEqual(try Data(contentsOf: settings), before)
    }
    func testMalformedSettingsAreUntouched() throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = Data("{ broken".utf8)
        try invalid.write(to: settings)
        expectThrows(try integration.install(helper: helper))
        expectEqual(try Data(contentsOf: settings), invalid)
    }
    func testShellQuotingHandlesApostrophes() throws {
        let value = "a 'quote' $(false) `false` path"
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s " + ClaudeIntegration.shellQuote(value)]
        process.standardOutput = output
        try process.run(); process.waitUntilExit()
        expectEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), value)
    }
    func fakeCodex(error: Bool = false) throws -> URL {
        let file = directory.appendingPathComponent("codex")
        let response = error ? #"{"error":{"message":"authentication required"}}"# : #"{"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1900000000}}}}"#
        let script = #"""
        #!/usr/bin/python3
        import json, sys
        initialized = False
        for line in sys.stdin:
            request = json.loads(line)
            method = request['method']
            if method == 'initialize': response = {'result':{}}
            elif method == 'initialized':
                initialized = True
                continue
            elif method == 'account/read':
                assert initialized
                response = {'result':{'account':{'type':'chatgpt','email':'sample@example.test'}}}
            elif method == 'account/rateLimits/read':
                assert initialized
                response = json.loads('\#(response)')
            else: raise AssertionError('Unexpected method')
            response['id'] = request['id']
            print(json.dumps(response), flush=True)
        """#
        try Data(script.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }
    func testCodexRPCHandshakeAndResponse() async throws {
        let executable = try fakeCodex()
        let snapshot = try await CodexProvider(executableOverride: executable.path).fetch()
        expectEqual(snapshot.provider, .codex)
        expectEqual(snapshot.windows.first?.remaining, 88)
    }
    func testCodexAuthErrorIsActionable() async throws {
        let executable = try fakeCodex(error: true)
        do { _ = try await CodexProvider(executableOverride: executable.path).fetch(); fail("Expected auth failure") }
        catch { expectTrue(error.localizedDescription.contains("codex login")) }
    }
    func testMissingExecutableIsActionable() async {
        do { _ = try await CodexProvider(executableOverride: "/does/not/exist").fetch(); fail("Expected missing executable") }
        catch { expectTrue(error.localizedDescription.contains("Install Codex")) }
    }
}
