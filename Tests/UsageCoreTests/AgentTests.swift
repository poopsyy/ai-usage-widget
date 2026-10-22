import Darwin
import Foundation
import UsageCore
import Security

final class AgentTests {
    func testTerminalAndQuotaParsing() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let raw = "Current session\r\n99% used\r\n\u{1b}[2J\u{1b}[HCurrent session\r\n\u{1b}[32m42.5% used\u{1b}[0m\r\nResets in 2h 30m\r\nCurrent week (all models)\r\n80% used\r\nResets 2030-01-01T10:00:00Z\r\nCurrent week (Sonnet only)\r\n25% remaining\r\nResets Tue 3pm (Asia/Jakarta)\r\n"
        let screen = ClaudeCLIScreen.render(raw)
        expectFalse(screen.contains("99%"))
        let result = try ClaudeCLIUsage.snapshot(screen: screen, at: now)
        expectEqual(result.windows.map(\.id), ["five_hour", "seven_day", "seven_day_sonnet"])
        expectEqual(result.windows[0].remaining, 57.5)
        expectEqual(result.windows[0].resetsAt, now.addingTimeInterval(9000))
        expectTrue(result.windows[1].resetsAt != nil)
        expectNil(result.windows[2].resetsAt)
        expectEqual(result.windows[2].usedPercent, 75)
        expectThrows(try ClaudeCLIUsage.snapshot(screen: "Current session\nNo data\nSession stats\n25% used"))
        expectThrows(try ClaudeCLIUsage.snapshot(screen: "Current session\n101% used"))
        expectThrows(try ClaudeCLIUsage.snapshot(screen: "Current week\nNaN% used"))
        let partial = try ClaudeCLIUsage.snapshot(screen: "Current session\nLoading…\nCurrent week\n0% used")
        expectEqual(partial.windows.count, 1); expectEqual(partial.windows[0].remaining, 100)
        let erased = ClaudeCLIScreen.render("Current session\r\n42% used\u{1b}[2K\rLoading…")
        expectThrows(try ClaudeCLIUsage.snapshot(screen: erased))
        let expired = try ClaudeCLIUsage.snapshot(screen: "Current session\n90% used\nResets 2020-01-01T00:00:00Z", at: now)
        expectTrue(expired.windows[0].isExpired(at: now)); expectNil(expired.remaining(at: now))
    }
    func testScopesAndLoginURLs() {
        let first = AccountIdentity(provider: .claude, accountID: "a", workspaceID: "one", displayName: "Sample", profile: "one")
        var other = first; other.profile = "two"; expectFalse(first.scope == other.scope)
        other = first; other.accountID = "b"; expectFalse(first.scope == other.scope)
        other = first; other.workspaceID = "two"; expectFalse(first.scope == other.scope)
        other = first; other.displayName = "Renamed"; expectEqual(first.scope, other.scope)
        expectEqual(first.scope.count, 64)
        expectTrue(CodexProvider.allowsAuthorizationURL(URL(string: "https://auth.openai.com/authorize?synthetic=1")!))
        for value in ["http://auth.openai.com/", "https://auth.openai.com.example.test/", "https://user@auth.openai.com/", "https://auth.openai.com:8443/", "file:///tmp/signin"] {
            expectFalse(CodexProvider.allowsAuthorizationURL(URL(string: value)!))
        }
    }
    func testDiscovery() throws {
        let fixture = try AgentFixture()
        let executable = try fixture.executable("codex", script: "#!/bin/sh\nexit 0\n")
        expectEqual(ExecutableLocator.find(.codex, environment: ["PATH": fixture.root.path], home: fixture.root)?.path, executable.path)
        expectNil(ExecutableLocator.find(.codex, override: fixture.root.appendingPathComponent("missing").path, environment: [:], home: fixture.root))
        expectNil(ExecutableLocator.find(.codex, override: fixture.root.path, environment: [:], home: fixture.root))
    }
    func testExperimentalCleanupIsScopedAndRetryable() throws {
        var attempts = 0
        do {
            try ExperimentalConnectionCleanup.forget { query in
                attempts += 1
                expectEqual(query[kSecAttrService as String] as? String, "dev.local.ai-usage-widget.connections")
                expectEqual(query[kSecAttrAccount as String] as? String, "claude.web.session.v1")
                expectNil(query[kSecReturnData as String])
                return errSecAuthFailed
            }
            fail("A failed removal must not report success")
        } catch { expectTrue(error.localizedDescription.contains("could not be removed")) }
        try ExperimentalConnectionCleanup.forget { _ in attempts += 1; return errSecSuccess }
        try ExperimentalConnectionCleanup.forget { _ in attempts += 1; return errSecItemNotFound }
        expectEqual(attempts, 3)
    }
    func testClaudeProbeWithoutChat() async throws {
        let fixture = try AgentFixture()
        let provider = try fixture.claude()
        let result = try await provider.fetchAccount()
        expectEqual(result.snapshot.windows.first?.remaining, 58)
        expectTrue(result.identity != nil)
        let calls = try String(contentsOf: fixture.root.appendingPathComponent("calls"), encoding: .utf8)
        expectTrue(calls.contains("/usage")); expectFalse(calls.contains("login")); expectFalse(calls.contains("-p"))
        let encoded = String(decoding: try JSONEncoder().encode(result.snapshot), as: UTF8.self)
        expectFalse(encoded.contains("PRIVATE-FIXTURE-OUTPUT"))
        // A second poll must work after all first-poll processes exited.
        _ = try await provider.fetchAccount()
    }
    func testClaudeFailuresAndCancellation() async throws {
        let fixture = try AgentFixture()
        var provider = try fixture.claude(mode: "signedOut")
        do { _ = try await provider.fetchAccount(); fail("Expected sign-in required") }
        catch { expectEqual(error as? AgentError, .signedOut(.claude)) }
        expectFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("calls").path))
        provider = try fixture.claude(mode: "authCommandFailure")
        do { _ = try await provider.fetchAccount(); fail("A command failure must not claim the account is signed out") }
        catch { expectEqual(error as? AgentError, .claudeProbeSetup(.commandFailed)) }
        provider = try fixture.claude(mode: "unknownPrompt")
        provider.probeTimeout = 2
        do { _ = try await provider.fetchAccount(); fail("Expected setup required") }
        catch { expectEqual(error as? AgentError, .claudeProbeSetup(.startupPrompt)) }
        provider = try fixture.claude(mode: "hang")
        provider.probeTimeout = 0.3
        do { _ = try await provider.fetchAccount(); fail("Expected deadline") }
        catch { expectEqual(error as? AgentError, .timeout(.claude)) }
        provider = try fixture.claude(mode: "hang")
        let running = Task { try await provider.fetchAccount() }
        try await Task.sleep(for: .milliseconds(150))
        running.cancel()
        do { _ = try await running.value; fail("Expected cancellation") } catch { expectTrue(error is CancellationError) }
        if let text = try? String(contentsOf: fixture.root.appendingPathComponent("pid"), encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            expectTrue(kill(pid, 0) != 0)
        }
        provider = try fixture.claude(mode: "changedAccount")
        do { _ = try await provider.fetchAccount(); fail("Expected changed-account rejection") }
        catch { expectEqual(error as? AgentError, .identityChanged) }
    }
    func testClaudeRefreshPreservesProbeMetadata() async throws {
        let fixture = try AgentFixture()
        let provider = try fixture.claude(mode: "metadata")
        _ = try await provider.fetchAccount()
        let marker = fixture.root.appendingPathComponent("app/ClaudeProbe/.claude/probe-marker")
        expectTrue(FileManager.default.fileExists(atPath: marker.path))
        _ = try await provider.fetchAccount()
        expectEqual(try String(contentsOf: marker, encoding: .utf8), "synthetic provider metadata")
        let needsTrust = try fixture.claude(mode: "trust")
        do { _ = try await needsTrust.fetchAccount(); fail("A nonempty directory must not receive automatic trust") }
        catch { expectEqual(error as? AgentError, .claudeProbeSetup(.trustRequired)) }
        expectEqual(try String(contentsOf: marker, encoding: .utf8), "synthetic provider metadata")
    }
    func testClaudeDiagnosticOmitsPrivateOutput() throws {
        let fixture = try AgentFixture()
        let provider = try fixture.claude()
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("UsageBridge")
        process.arguments = ["--check-claude", "--claude-path", provider.executableOverride, "--directory", provider.directory.path]
        process.environment = provider.environment
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        expectEqual(process.terminationStatus, 0)
        expectEqual(output, "Claude check: quota read succeeded. Account details and usage values omitted.\n")
        expectFalse(output.contains("PRIVATE-FIXTURE-OUTPUT"))
        expectFalse(output.contains("example.test"))
        expectFalse(output.contains("42"))
    }
    func testClaudeTerminalQueriesAndTrust() async throws {
        let fixture = try AgentFixture()
        _ = try await fixture.claude(mode: "cursorQuery").fetchAccount()
        _ = try await fixture.claude(mode: "trust").fetchAccount()
        let crashing = try fixture.claude(mode: "crash")
        do { _ = try await crashing.fetchAccount(); fail("Expected crashed probe failure") }
        catch { expectEqual(error as? AgentError, .unavailable(.claude)) }
        let target = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("app/ClaudeProbe"))
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("app/ClaudeProbe"), withDestinationURL: target)
        do { _ = try await crashing.fetchAccount(); fail("A redirected probe directory must not be trusted") }
        catch { expectEqual(error as? AgentError, .claudeProbeSetup(.workingDirectory)) }
    }
    func testClaudeWaitsForStartupPrompt() async throws {
        let fixture = try AgentFixture()
        _ = try await fixture.claude(mode: "delayedPrompt").fetchAccount()
    }
    func testCodexAccountAndBrowserLogin() async throws {
        let fixture = try AgentFixture()
        let provider = try fixture.codex()
        let result = try await provider.fetchAccount()
        expectEqual(result.snapshot.windows.first?.remaining, 75)
        let calls = try String(contentsOf: fixture.root.appendingPathComponent("calls"), encoding: .utf8)
        expectFalse(calls.contains("login/start")); expectFalse(calls.contains("turn/")); expectTrue(calls.contains("account/read"))
        let opened = OpenedURLs()
        try await provider.signIn { url in await opened.append(url); return true }
        expectEqual(await opened.count(), 1)
        let failure = try fixture.codex(mode: "badURL")
        do { try await failure.signIn { _ in fail("Must not open foreign URL"); return true }; fail("Expected URL rejection") }
        catch { expectEqual(error as? AgentError, .invalidResponse(.codex)) }
        let changed = try fixture.codex(mode: "changedAccount")
        do { _ = try await changed.fetchAccount(); fail("Expected account isolation") }
        catch { expectEqual(error as? AgentError, .identityChanged) }
    }
    @MainActor
    func testMonitorSerializationPauseAndLateResults() async throws {
        let client = FakeAgentClient()
        let monitor = AgentMonitor(client: client)
        async let first: Void = monitor.refresh(force: true)
        async let duplicate: Void = monitor.refresh(force: true)
        _ = await (first, duplicate)
        expectEqual(await client.readCount(), 1); expectTrue(monitor.state.connected)
        await monitor.setPaused(true)
        expectEqual(monitor.state.phase, .paused); expectNil(monitor.state.snapshot)
        await monitor.refresh(force: true); expectEqual(await client.readCount(), 1)
        await monitor.setPaused(false); expectTrue(monitor.state.connected)
        await client.setError(.unavailable(.claude))
        await monitor.refresh(force: true)
        expectEqual(monitor.state.phase, .unavailable); expectTrue(monitor.state.snapshot != nil)
        expectTrue(monitor.nextRefresh > Date())
        await client.setError(.claudeProbeSetup(.startupPrompt))
        await monitor.refresh(force: true)
        expectEqual(monitor.state.phase, .unavailable); expectTrue(monitor.state.snapshot != nil)
        await client.setError(.signedOut(.claude))
        await monitor.refresh(force: true); expectNil(monitor.state.snapshot); expectEqual(monitor.state.phase, .signInRequired)
        await client.setError(nil)
        let pending = Task { await monitor.refresh(force: true) }
        await Task.yield()
        await monitor.setPaused(true)
        await pending.value
        expectEqual(monitor.state.phase, .paused); expectNil(monitor.state.snapshot)
        await monitor.setPaused(false)
        let login = Task { await monitor.signIn { _ in true } }
        try await Task.sleep(for: .milliseconds(10)); monitor.cancel()
        await login.value
        expectFalse(monitor.state.refreshing); expectEqual(monitor.state.phase, .signInRequired)
        await monitor.refresh(force: true); expectTrue(monitor.state.connected)
        let switching = Task { await monitor.refresh(force: true) }
        try await Task.sleep(for: .milliseconds(10))
        await client.setAccount("switched-during-read")
        await switching.value
        expectEqual(monitor.state.phase, .unavailable); expectNil(monitor.state.snapshot)
    }
    @MainActor
    func testVerifiedCacheAndRateLimitCooldown() async throws {
        let client = FakeAgentClient()
        let cached = UsageSnapshot(provider: .claude, observedAt: Date().addingTimeInterval(-1800), windows: [UsageWindow(id: "session", title: "Session", usedPercent: 75, resetsAt: nil)])
        let identity = AccountIdentity(provider: .claude, accountID: "fixture", displayName: "Sample")
        var scopes: [String] = []
        let monitor = AgentMonitor(client: client, cachedSnapshot: { scope in scopes.append(scope); return cached })
        await client.setError(.unavailable(.claude))
        await monitor.refresh(force: true)
        expectEqual(scopes, [identity.scope]); expectEqual(monitor.state.snapshot, cached)
        expectFalse(monitor.state.connected)
        await client.setAccount("different")
        await monitor.refresh(force: true)
        expectEqual(scopes.last, AccountIdentity(provider: .claude, accountID: "different", displayName: "Sample").scope)
        await client.setError(.rateLimited(Date().addingTimeInterval(60)))
        await monitor.refresh(force: true)
        let reads = await client.readCount()
        await monitor.refresh(force: true)
        expectEqual(await client.readCount(), reads)
        expectTrue(monitor.nextRefresh > Date().addingTimeInterval(50))
    }
}

private actor OpenedURLs {
    var urls: [URL] = []
    func append(_ url: URL) { urls.append(url) }
    func count() -> Int { urls.count }
}

private actor FakeAgentClient: AgentClient {
    nonisolated let provider: ProviderID = .claude
    private var reads = 0
    private var error: AgentError?
    private var account = "fixture"
    func readCount() -> Int { reads }
    func setError(_ error: AgentError?) { self.error = error }
    func setAccount(_ value: String) { account = value }
    func checkAuthentication() async throws -> AccountIdentity? {
        if let error, error.phase != .unavailable { throw error }
        return AccountIdentity(provider: .claude, accountID: account, displayName: "Sample")
    }
    func fetchAccount() async throws -> AccountUsage {
        reads += 1
        // Deliberately ignores task cancellation to exercise the monitor's generation guard.
        try? await Task.sleep(for: .milliseconds(50))
        if let error { throw error }
        return AccountUsage(identity: AccountIdentity(provider: .claude, accountID: account, displayName: "Sample"), snapshot: UsageSnapshot(provider: .claude, observedAt: Date(), windows: [UsageWindow(id: "session", title: "Session", usedPercent: 90, resetsAt: Date().addingTimeInterval(3600))]))
    }
    func signIn(openBrowser: @escaping AgentBrowserOpener) async throws { try? await Task.sleep(for: .milliseconds(50)) }
}

private final class AgentFixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AI Usage agent '\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func executable(_ name: String, script: String) throws -> URL {
        let path = root.appendingPathComponent(name)
        try Data(script.utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        return path
    }
    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["AI_USAGE_FIXTURE"] = root.path
        env["ANTHROPIC_API_KEY"] = "synthetic-not-a-real-key"
        return env
    }
    func claude(mode: String = "success") throws -> ClaudeCLIProvider {
        try Data(mode.utf8).write(to: root.appendingPathComponent("mode"))
        let path = try executable("claude", script: #"""
        #!/usr/bin/python3
        import json, os, pathlib, sys, time, termios, tty
        root = pathlib.Path(os.environ['AI_USAGE_FIXTURE'])
        mode = (root / 'mode').read_text()
        args = sys.argv[1:]
        if args == ['auth', 'status']:
            if mode == 'authCommandFailure': sys.exit(2)
            account = 'b' if mode == 'changedAccount' and (root / 'calls').exists() else 'a'
            print(json.dumps({'loggedIn': mode != 'signedOut', 'authMethod':'claude.ai', 'email':account+'@example.test', 'orgId':'synthetic-org', 'configDirectory':'synthetic-profile'}))
        elif args == ['--help']:
            print('--safe-mode --strict-mcp-config --settings --session-id --no-chrome --disallowed-tools')
        elif args == ['auth', 'login']:
            assert 'BROWSER' not in os.environ
            (root / 'calls').write_text('login')
        else:
            assert os.isatty(0) and os.isatty(1)
            assert '--safe-mode' in args and '--strict-mcp-config' in args
            assert args[args.index('--allowed-tools')+1] == ''
            settings = json.loads(args[args.index('--settings')+1])
            assert settings['disableAllHooks'] and not settings['remoteControlAtStartup']
            assert 'ANTHROPIC_API_KEY' not in os.environ
            assert os.environ['BROWSER'] == '/usr/bin/false'
            assert os.environ['CLAUDE_CODE_SKIP_PROMPT_HISTORY'] == '1'
            (root / 'pid').write_text(str(os.getpid()))
            if mode == 'metadata':
                metadata = pathlib.Path.cwd() / '.claude'
                metadata.mkdir(exist_ok=True)
                (metadata / 'probe-marker').write_text('synthetic provider metadata')
            if mode == 'hang':
                time.sleep(60)
            if mode == 'delayedPrompt':
                print('Starting Claude Code…', flush=True)
                time.sleep(1.6)
            if mode in ['cursorQuery', 'trust']:
                previous = termios.tcgetattr(0)
                tty.setraw(0)
                if mode == 'cursorQuery':
                    os.write(1, b'\x1b[')
                    time.sleep(0.05)
                    os.write(1, b'6n')
                    assert os.read(0, 6) == b'\x1b[1;1R'
                else:
                    print('Do you trust the files in this folder?\r\n  1. Yes, I trust this folder\r\n❯ 2. No, exit', flush=True)
                    assert os.read(0, 3) == b'\x1b[A'
                    print('\x1b[2J\x1b[HDo you trust the files in this folder?\r\n❯ 1. Yes, I trust this folder\r\n  2. No, exit', flush=True)
                    assert os.read(0, 1) == b'\r'
                termios.tcsetattr(0, termios.TCSANOW, previous)
                print('\x1b[2J\x1b[H', end='', flush=True)
            print('Unrecognized setup question' if mode == 'unknownPrompt' else '❯', flush=True)
            command = sys.stdin.readline().strip()
            assert command == '/usage'
            (root / 'calls').write_text(command)
            if mode == 'crash': sys.exit(3)
            print('PRIVATE-FIXTURE-OUTPUT', flush=True)
            print('Current session\n42% used\nResets in 2h\nCurrent week (all models)\n20% used', flush=True)
            time.sleep(60)
        """#)
        return ClaudeCLIProvider(executableOverride: path.path, directory: root.appendingPathComponent("app"), environment: environment)
    }
    func codex(mode: String = "success") throws -> CodexProvider {
        try Data(mode.utf8).write(to: root.appendingPathComponent("mode"))
        let path = try executable("codex", script: #"""
        #!/usr/bin/python3
        import json, os, pathlib, sys
        root = pathlib.Path(os.environ['AI_USAGE_FIXTURE'])
        mode = (root / 'mode').read_text()
        account_reads = 0
        for line in sys.stdin:
            request = json.loads(line)
            method = request['method']
            with (root / 'calls').open('a') as log: log.write(method+'\n')
            if method == 'initialized': continue
            if method == 'initialize': result = {}
            elif method == 'account/read':
                account_reads += 1
                result = {'account':{'type':'chatgpt','email':('b' if mode == 'changedAccount' and account_reads > 1 else 'a')+'@example.test'}}
            elif method == 'account/rateLimits/read':
                result = {'rateLimits':{'primary':{'usedPercent':25,'windowDurationMins':300,'resetsAt':1900000000}}}
            elif method == 'account/login/start':
                result = {'loginId':'synthetic-login','authUrl':'https://example.test/' if mode == 'badURL' else 'https://auth.openai.com/authorize?synthetic=1'}
            else: raise AssertionError('Unexpected method')
            print(json.dumps({'id':request['id'],'result':result}), flush=True)
            if method == 'account/login/start':
                print(json.dumps({'method':'account/login/completed','params':{'loginId':'synthetic-login','success':True}}), flush=True)
        """#)
        return CodexProvider(executableOverride: path.path, environment: environment)
    }
}
