import Foundation

/// No XCTest dependency: this runs with both Xcode and standalone Command Line Tools.
@main
struct CheckRunner {
    static func main() async {
        let usage = UsageTests()
        let checks: [(String, () async throws -> Void)] = [
            ("Claude subscription windows and privacy", { try usage.testClaudeSubscriptionWindows() }),
            ("Missing and invalid Claude fields", { try usage.testMissingAndInvalidClaudeFields() }),
            ("Unknown reset", { try usage.testPartialWindowHasUnknownReset() }),
            ("Codex legacy and durations", { try usage.testCodexLegacyUsesReportedDurations() }),
            ("Codex multiple buckets", { try usage.testCodexMultipleBucketsAndNoDuplicateLegacy() }),
            ("Codex invalid data", { usage.testCodexMissingLimitsAndInvalidPercent() }),
            ("Stale, future and expired readings", { usage.testStaleExpiredAndFutureSnapshots() }),
            ("Alert thresholds and persistence", { try usage.testAlertThresholdsAndPersistence() }),
            ("Alert deduplication and stale suppression", { try usage.testFirstHighReadingSuppressesLowerThresholdAndOldData() }),
            ("Atomic capture and monotonic snapshots", { try await usage.testSnapshotProviderAndAtomicCapture() }),
            ("Settings restoration preserves edits", { try IntegrationTests().testInstallAndRestorePreserveOtherChanges() }),
            ("Fresh setup and idempotence", { try IntegrationTests().testFreshInstallIsIdempotentAndRestorable() }),
            ("Changed status-line protection", { try IntegrationTests().testRefusesToOverwriteChangedStatusLine() }),
            ("Malformed settings protection", { try IntegrationTests().testMalformedSettingsAreUntouched() }),
            ("Shell quoting", { try IntegrationTests().testShellQuotingHandlesApostrophes() }),
            ("Codex JSON-RPC", { try await IntegrationTests().testCodexRPCHandshakeAndResponse() }),
            ("Codex authentication failure", { try await IntegrationTests().testCodexAuthErrorIsActionable() }),
            ("Missing Codex executable", { try await IntegrationTests().testMissingExecutableIsActionable() })
        ]
        for (name, check) in checks {
            let before = CheckLog.failures
            do { try await check() }
            catch { fail("\(name): \(error)") }
            print("\(CheckLog.failures == before ? "PASS" : "FAIL") \(name)")
        }
        print("\(checks.count) checks, \(CheckLog.failures) failures")
        exit(CheckLog.failures == 0 ? 0 : 1)
    }
}
