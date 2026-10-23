import Foundation
import UsageCore

final class UsageTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func data(_ string: String) -> Data { Data(string.utf8) }

    func testClaudeSubscriptionWindows() throws {
        let snapshot = try UsageParser.claude(data("""
        {"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":80,"resets_at":1800600000}},"session_id":"must-not-persist","workspace":{"current_dir":"private"}}
        """), at: now)
        expectEqual(snapshot.windows.count, 2)
        expectEqual(snapshot.windows[0].remaining, 76.5)
        expectEqual(snapshot.windows[1].title, "Weekly")
        expectEqual(snapshot.remaining(at: now), 20)
        let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8)!
        expectFalse(encoded.contains("must-not-persist"))
        expectFalse(encoded.contains("private"))
    }
    func testMissingAndInvalidClaudeFields() throws {
        for input in ["{}", "{\"rate_limits\":null}", "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":true}}}", "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":-1}}}"] {
            expectThrows(try UsageParser.claude(data(input)))
        }
    }
    func testPartialWindowHasUnknownReset() throws {
        let snapshot = try UsageParser.claude(data("{\"rate_limits\":{\"seven_day\":{\"used_percentage\":0}}}"), at: now)
        expectEqual(snapshot.windows.count, 1)
        expectNil(snapshot.windows[0].resetsAt)
        expectEqual(snapshot.remaining(at: now), 100)
        expectTrue(AlertLedger().candidates(for: snapshot, at: now).isEmpty)
    }
    func testCodexLegacyUsesReportedDurations() throws {
        let snapshot = try UsageParser.codex(data("""
        {"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":15,"resetsAt":1800003600},"secondary":null,"planType":"plus"}}}
        """), at: now)
        expectEqual(snapshot.windows.count, 1)
        expectEqual(snapshot.windows[0].title, "15 min")
        expectEqual(snapshot.plan, "plus")
    }
    func testCodexMultipleBucketsAndNoDuplicateLegacy() throws {
        let snapshot = try UsageParser.codex(data("""
        {"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300},"secondary":{"usedPercent":10,"windowDurationMins":10080}},"review":{"limitName":"Review","primary":{"usedPercent":0,"windowDurationMins":60}}}}
        """), at: now)
        expectEqual(snapshot.windows.count, 3)
        expectEqual(Set(snapshot.windows.map(\.id)).count, 3)
        expectTrue(snapshot.windows.contains(where: { $0.title == "Review · 1 hours" }))
        expectFalse(snapshot.windows.contains(where: { $0.usedPercent == 99 }))
    }
    func testCodexMissingLimitsAndInvalidPercent() {
        expectThrows(try UsageParser.codex(data("{\"rateLimits\":null}")))
        expectThrows(try UsageParser.codex(data("{\"rateLimits\":{\"primary\":{\"usedPercent\":101}}}")))
    }
    func sample(used: Double, observed: Date? = nil, reset: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(provider: .codex, observedAt: observed ?? now, windows: [UsageWindow(id: "p", title: "5 hours", usedPercent: used, resetsAt: reset ?? now.addingTimeInterval(3600))])
    }
    func testStaleExpiredAndFutureSnapshots() {
        expectNil(sample(used: 20, observed: now.addingTimeInterval(-901)).remaining(at: now))
        expectNil(sample(used: 20, reset: now).remaining(at: now))
        expectNil(sample(used: 20, observed: now.addingTimeInterval(120)).remaining(at: now))
        expectEqual(sample(used: 100).remaining(at: now), 0)
    }
    func testAlertThresholdsAndPersistence() throws {
        var ledger = AlertLedger()
        expectTrue(ledger.candidates(for: sample(used: 79), at: now).isEmpty)
        let alert80 = try require(ledger.candidates(for: sample(used: 80), at: now).first)
        expectEqual(alert80.threshold, 80)
        ledger.markDelivered(alert80, at: now)
        expectTrue(ledger.candidates(for: sample(used: 90), at: now).isEmpty)
        let alert95 = try require(ledger.candidates(for: sample(used: 96), at: now).first)
        expectEqual(alert95.threshold, 95)
        ledger.markDelivered(alert95, at: now)
        let restored = try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(ledger))
        expectTrue(restored.candidates(for: sample(used: 100), at: now).isEmpty)
        expectEqual(restored.candidates(for: sample(used: 96, reset: now.addingTimeInterval(7200)), at: now).count, 1)
    }
    func testFirstHighReadingSuppressesLowerThresholdAndOldData() throws {
        var ledger = AlertLedger()
        let alert = try require(ledger.candidates(for: sample(used: 97), at: now).first)
        ledger.markDelivered(alert, at: now)
        expectTrue(ledger.candidates(for: sample(used: 81), at: now).isEmpty)
        expectTrue(AlertLedger().candidates(for: sample(used: 97, observed: now.addingTimeInterval(-1000)), at: now).isEmpty)
        expectTrue(AlertLedger().candidates(for: sample(used: 97, reset: now), at: now).isEmpty)
    }
    func testAlertToleratesResetPrecision() throws {
        var ledger = AlertLedger()
        let alert = try require(ledger.candidates(for: sample(used: 85), at: now).first)
        ledger.markDelivered(alert, at: now)
        expectTrue(ledger.candidates(for: sample(used: 85, reset: now.addingTimeInterval(3600 - 59)), at: now).isEmpty)
        expectTrue(ledger.candidates(for: sample(used: 85, reset: now.addingTimeInterval(3600 + 59)), at: now).isEmpty)
        // A genuinely new window alerts again.
        expectEqual(ledger.candidates(for: sample(used: 85, reset: now.addingTimeInterval(3600 + 18000)), at: now).count, 1)
    }
    func testSnapshotProviderAndAtomicCapture() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":42,\"resets_at\":1800003600}}}")
        try ClaudeCapture.capture(input, directory: directory, at: now)
        try ClaudeCapture.capture(input, directory: directory, at: now.addingTimeInterval(-60))
        let read = try ClaudeCapture.read(directory: directory)
        expectEqual(read.observedAt, now)
        expectEqual(read.windows.first?.usedPercent, 42)
        expectThrows(try ClaudeCapture.capture(data("{}"), directory: directory))
        let retained = try ClaudeCapture.read(directory: directory)
        expectEqual(retained, read)
    }
}
