import Foundation

/// No XCTest dependency: this runs with both Xcode and standalone Command Line Tools.
@main
struct CheckRunner {
    static func main() async {
        let usage = UsageTests()
        let agents = AgentTests()
        let checks: [(String, () async throws -> Void)] = [
            ("Terminal replay and Claude quota parsing", { try agents.testTerminalAndQuotaParsing() }),
            ("Incremental terminal replay", { agents.testIncrementalScreenMatchesFullReplay() }),
            ("Claude reset labels", { try agents.testClaudeResetLabels() }),
            ("Account scopes and login URL restrictions", { agents.testScopesAndLoginURLs() }),
            ("Executable discovery", { try agents.testDiscovery() }),
            ("Claude probe without a chat", { try await agents.testClaudeProbeWithoutChat() }),
            ("Claude status-line fast path", { try await agents.testClaudeStatusLineFastPath() }),
            ("Claude refresh preserves probe metadata", { try await agents.testClaudeRefreshPreservesProbeMetadata() }),
            ("Claude diagnostic omits private output", { try agents.testClaudeDiagnosticOmitsPrivateOutput() }),
            ("Claude failures, deadline, and cancellation", { try await agents.testClaudeFailuresAndCancellation() }),
            ("Claude cursor queries, scoped trust, and crashes", { try await agents.testClaudeTerminalQueriesAndTrust() }),
            ("Claude waits for a delayed startup prompt", { try await agents.testClaudeWaitsForStartupPrompt() }),
            ("Codex account reads and browser sign-in", { try await agents.testCodexAccountAndBrowserLogin() }),
            ("Monitor serialization, pause, and late results", { try await agents.testMonitorSerializationPauseAndLateResults() }),
            ("Verified cache restoration and rate-limit cooldown", { try await agents.testVerifiedCacheAndRateLimitCooldown() }),
            ("Claude subscription windows and privacy", { try usage.testClaudeSubscriptionWindows() }),
            ("Missing and invalid Claude fields", { try usage.testMissingAndInvalidClaudeFields() }),
            ("Unknown reset", { try usage.testPartialWindowHasUnknownReset() }),
            ("Codex legacy and durations", { try usage.testCodexLegacyUsesReportedDurations() }),
            ("Codex multiple buckets", { try usage.testCodexMultipleBucketsAndNoDuplicateLegacy() }),
            ("Codex invalid data", { usage.testCodexMissingLimitsAndInvalidPercent() }),
            ("Stale, future and expired readings", { usage.testStaleExpiredAndFutureSnapshots() }),
            ("Alert thresholds and persistence", { try usage.testAlertThresholdsAndPersistence() }),
            ("Alert deduplication and stale suppression", { try usage.testFirstHighReadingSuppressesLowerThresholdAndOldData() }),
            ("Alert deduplication across reset precision", { try usage.testAlertToleratesResetPrecision() }),
            ("Atomic capture and monotonic snapshots", { try await usage.testSnapshotProviderAndAtomicCapture() }),
            ("Settings restoration preserves edits", { try IntegrationTests().testInstallAndRestorePreserveOtherChanges() }),
            ("Fresh setup and idempotence", { try IntegrationTests().testFreshInstallIsIdempotentAndRestorable() }),
            ("Helper refresh after app updates", { try IntegrationTests().testHelperRefreshTracksAppUpdates() }),
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
