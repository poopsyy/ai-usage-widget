import Foundation

public struct ClaudeCLIProvider: AgentClient {
    public let provider: ProviderID = .claude
    public var executableOverride: String
    public var directory: URL
    public var environment: [String: String]
    public var probeTimeout: TimeInterval
    /// Prefer fresh readings captured by the opt-in Claude Code status line over a `/usage` probe.
    public var useStatusLine: Bool
    public init(executableOverride: String = "", directory: URL = UsageFiles.directory, environment: [String: String] = ProcessInfo.processInfo.environment, probeTimeout: TimeInterval = 45, useStatusLine: Bool = false) {
        self.executableOverride = executableOverride; self.directory = directory; self.environment = environment; self.probeTimeout = probeTimeout
        self.useStatusLine = useStatusLine
    }
    public func checkAuthentication() async throws -> AccountIdentity? {
        try await agentOperation { cancellation in
            try self.auth(self.executable(), directory: self.prepareDirectory(), cancellation: cancellation, deadline: ProcessInfo.processInfo.systemUptime + 20)
        }
    }
    public func fetchAccount() async throws -> AccountUsage {
        try await agentOperation { cancellation in
            let executable = try self.executable()
            let cwd = try self.prepareDirectory()
            let deadline = ProcessInfo.processInfo.systemUptime + min(60, max(0.1, self.probeTimeout))
            let before = try self.auth(executable, directory: cwd, cancellation: cancellation, deadline: deadline)
            if self.useStatusLine, let reading = self.statusLineReading(for: before) { return AccountUsage(identity: before, snapshot: reading) }
            guard try self.supportsProbe(executable, directory: cwd, cancellation: cancellation, deadline: deadline) else { throw AgentError.claudeProbeSetup(.capabilities) }
            let arguments = ["--safe-mode", "--allowed-tools", "", "--disallowed-tools", "*", "--no-chrome", "--strict-mcp-config", "--settings",
                             #"{"disableAllHooks":true,"remoteControlAtStartup":false,"promptSuggestionEnabled":false}"#,
                             "--session-id", UUID().uuidString.lowercased()]
            let snapshot: UsageSnapshot
            do {
                let process = try AgentProcess(executable: executable, arguments: arguments, provider: .claude, directory: cwd, environment: self.probeEnvironment(executable), terminal: true, timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime), cancellation: cancellation)
                defer { process.stop() }
                snapshot = try self.probe(process, directory: cwd)
            }
            let after = try self.auth(executable, directory: cwd, cancellation: cancellation, deadline: deadline)
            guard before?.scope == after?.scope else { throw AgentError.identityChanged }
            if let scope = after?.scope { try? UsageFiles.write(ScopedReading(scope: scope, snapshot: snapshot), to: self.probeURL) }
            return AccountUsage(identity: after, snapshot: snapshot)
        }
    }
    private var probeURL: URL { directory.appendingPathComponent("claude-probe.json") }
    /// Status-line captures carry no account, so one is trusted only when it was observed after this
    /// account was first seen, and only while a full probe from the same account is recent.
    private func statusLineReading(for identity: AccountIdentity?, at now: Date = Date()) -> UsageSnapshot? {
        guard let scope = identity?.scope else { return nil }
        let markerURL = directory.appendingPathComponent("claude-scope.json")
        guard let marker = try? UsageFiles.read(ScopeMarker.self, from: markerURL), marker.scope == scope else {
            try? UsageFiles.write(ScopeMarker(scope: scope, since: now), to: markerURL)
            return nil
        }
        guard let probe = try? UsageFiles.read(ScopedReading.self, from: probeURL), probe.scope == scope,
              now.timeIntervalSince(probe.snapshot.observedAt) < 1800,
              let capture = try? ClaudeCapture.read(directory: directory), capture.observedAt >= marker.since,
              now.timeIntervalSince(capture.observedAt) < 300, capture.observedAt.timeIntervalSince(now) < 60 else { return nil }
        // Keep probe-only windows such as model-specific limits until the next full probe.
        let captured = Set(capture.windows.map(\.id))
        let extra = probe.snapshot.windows.filter { !captured.contains($0.id) && !$0.isExpired(at: now) }
        return UsageSnapshot(provider: .claude, observedAt: capture.observedAt, windows: capture.windows + extra)
    }
    public func signIn(openBrowser: @escaping AgentBrowserOpener) async throws {
        // The official CLI opens the default browser and owns its local callback and credentials.
        try await agentOperation { cancellation in
            let executable = try self.executable(), cwd = try self.prepareDirectory()
            let deadline = ProcessInfo.processInfo.systemUptime + 300
            _ = try self.command(executable, arguments: ["auth", "login"], directory: cwd, cancellation: cancellation, deadline: deadline)
            _ = try self.auth(executable, directory: cwd, cancellation: cancellation, deadline: deadline)
        }
    }
    private func executable() throws -> URL {
        guard let result = ExecutableLocator.find(.claude, override: executableOverride, environment: environment) else { throw AgentError.notInstalled(.claude) }
        return result
    }
    /// Flags are read from `--help` once per installed Claude Code build.
    private func supportsProbe(_ executable: URL, directory: URL, cancellation: AgentCancellation, deadline: TimeInterval) throws -> Bool {
        let resolved = executable.resolvingSymlinksInPath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(resolved.path)|\(modified)|\((attributes?[.size] as? NSNumber)?.intValue ?? -1)"
        if let known = CapabilityCache.shared.value(for: key) { return known }
        let help = try command(executable, arguments: ["--help"], directory: directory, cancellation: cancellation, deadline: deadline)
        let text = String(decoding: help, as: UTF8.self)
        let supported = ["--safe-mode", "--strict-mcp-config", "--settings", "--session-id", "--no-chrome", "--disallowed-tools"].allSatisfy(text.contains)
        CapabilityCache.shared.store(supported, for: key)
        return supported
    }
    private func prepareDirectory() throws -> URL {
        do {
            try UsageFiles.prepare(directory)
            let root = directory.resolvingSymlinksInPath()
            let cwd = root.appendingPathComponent("ClaudeProbe", isDirectory: true)
            try UsageFiles.prepare(cwd)
            guard cwd.resolvingSymlinksInPath().standardizedFileURL == cwd.standardizedFileURL else { throw AgentError.claudeProbeSetup(.workingDirectory) }
            // Claude can leave local metadata after a successful read. Preserve it and keep polling;
            // directory emptiness is required only if a new trust confirmation is actually requested.
            return cwd
        } catch { throw AgentError.claudeProbeSetup(.workingDirectory) }
    }
    private func probeEnvironment(_ executable: URL, allowBrowser: Bool = false) -> [String: String] {
        var env = environment
        // Follow the native subscription profile, never inherited API/token overrides.
        for key in env.keys where key.hasPrefix("ANTHROPIC_") || key.hasPrefix("CLAUDE_CODE_OAUTH") { env.removeValue(forKey: key) }
        for key in ["BROWSER", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"] { env.removeValue(forKey: key) }
        env["PATH"] = "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["DISABLE_AUTOUPDATER"] = "1"
        env["CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION"] = "false"
        env["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
        if !allowBrowser { env["BROWSER"] = "/usr/bin/false" }
        env["TERM"] = "xterm-256color"; env["LANG"] = "en_US.UTF-8"; env["LC_ALL"] = "en_US.UTF-8"
        return env
    }
    private func command(_ executable: URL, arguments: [String], directory: URL, cancellation: AgentCancellation, deadline: TimeInterval) throws -> Data {
        let process = try AgentProcess(executable: executable, arguments: arguments, provider: .claude, directory: directory, environment: probeEnvironment(executable, allowBrowser: arguments == ["auth", "login"]), timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime), cancellation: cancellation)
        defer { process.stop() }
        let data = try process.collect()
        guard process.exitCode == 0 else {
            if arguments == ["auth", "status"],
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               root["loggedIn"] as? Bool == false { throw AgentError.signedOut(.claude) }
            throw AgentError.claudeProbeSetup(.commandFailed)
        }
        return data
    }
    private func auth(_ executable: URL, directory: URL, cancellation: AgentCancellation, deadline: TimeInterval) throws -> AccountIdentity? {
        let data = try command(executable, arguments: ["auth", "status"], directory: directory, cancellation: cancellation, deadline: deadline)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let loggedIn = root["loggedIn"] as? Bool else { throw AgentError.claudeProbeSetup(.authenticationFormat) }
        guard loggedIn else { throw AgentError.signedOut(.claude) }
        guard let method = root["authMethod"] as? String, ["claude.ai", "oauth_token"].contains(method) else { throw AgentError.unsupported(.claude) }
        let account = (root["accountUuid"] as? String) ?? (root["email"] as? String)
        guard let account, !account.isEmpty else { return nil }
        return AccountIdentity(provider: .claude, accountID: account, workspaceID: root["orgId"] as? String,
                               displayName: "Claude account", profile: (root["configDirectory"] as? String) ?? environment["CLAUDE_CONFIG_DIR"] ?? "default")
    }
    private func probe(_ process: AgentProcess, directory: URL) throws -> UsageSnapshot {
        var terminal = ClaudeCLIScreen()
        var sawOutput = false, commandSent = false, trustResponses = 0
        var lastOutput = ProcessInfo.processInfo.systemUptime
        var ready = lastOutput + 1
        var previousScreen = ""
        var queryTail = Data()
        // Derived from the screen only when new output arrives; the loop otherwise just waits.
        var screen = "", lower = "", lines: [String] = [], promptReady = false, parsed: UsageSnapshot?
        func update() {
            screen = terminal.text
            lower = screen.lowercased()
            lines = screen.components(separatedBy: "\n")
            let lastMarker = lines.lastIndex(where: { $0.contains("❯") })
            promptReady = lastMarker.map { index in
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                return line == "❯" || line.hasPrefix("❯ Try ")
            } ?? lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == ">" })
            parsed = commandSent ? try? ClaudeCLIUsage.snapshot(screen: screen) : nil
        }
        update()
        while true {
            let chunk: Data
            do { chunk = try process.readChunk() }
            catch let problem as AgentError {
                if problem == .timeout(.claude), !commandSent, sawOutput { throw AgentError.claudeProbeSetup(.startupPrompt) }
                throw problem
            }
            if !chunk.isEmpty {
                sawOutput = true; lastOutput = ProcessInfo.processInfo.systemUptime
                queryTail.append(chunk)
                let query = Data([0x1b, 0x5b, 0x36, 0x6e])
                while let range = queryTail.range(of: query) {
                    try process.send("\u{1b}[1;1R")
                    queryTail.removeSubrange(..<range.upperBound)
                }
                queryTail = Data(queryTail.suffix(3))
                terminal.feed(chunk)
                update()
            }
            let trustPending = !commandSent && !promptReady && lower.contains("yes, i trust this folder")
            if screen != previousScreen {
                previousScreen = screen
                if trustPending {
                    guard directory.resolvingSymlinksInPath().standardizedFileURL == directory.standardizedFileURL,
                          (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true else { throw AgentError.claudeProbeSetup(.trustRequired) }
                    guard trustResponses < 4 else { throw AgentError.claudeProbeSetup(.startupPrompt) }
                    guard let yes = lines.firstIndex(where: { $0.lowercased().contains("yes, i trust this folder") }),
                          let selected = lines.firstIndex(where: { $0.contains("❯") && ($0.lowercased().contains("trust") || $0.lowercased().contains("exit")) }) else { throw AgentError.claudeProbeSetup(.startupPrompt) }
                    try process.send(selected == yes ? "\r" : (selected < yes ? "\u{1b}[B" : "\u{1b}[A"))
                    trustResponses += 1; ready = ProcessInfo.processInfo.systemUptime + 1
                    continue
                }
            }
            if trustPending { if process.hasExited { throw AgentError.unavailable(.claude) }; continue }
            // `auth status` already confirmed sign-in; only a startup screen may contradict it, never tips or menus later.
            if !commandSent, !promptReady, lower.contains("sign in") || lower.contains("not logged in") || lower.contains("/login") { throw AgentError.signedOut(.claude) }
            if lower.contains("rate limited") || lower.contains("too many requests") { throw AgentError.rateLimited(nil) }
            if lower.contains("choose the text style") || lower.contains("select login method") || (!promptReady && lower.contains("do you trust")) || lower.contains("permission required") { throw AgentError.claudeProbeSetup(.startupPrompt) }
            let idle = ProcessInfo.processInfo.systemUptime - lastOutput
            if !commandSent, promptReady, ProcessInfo.processInfo.systemUptime >= ready, idle >= 0.3 {
                // Only a recognized empty Claude prompt may receive the built-in command.
                // A quiet startup banner is not a setup failure: wait for the actual prompt.
                try process.send("/usage\r"); commandSent = true
                terminal = ClaudeCLIScreen(); update(); continue
            }
            if commandSent, idle >= 0.5, let snapshot = parsed {
                // A screen still loading its weekly row gets extra time before a partial reading is accepted.
                let ids = Set(snapshot.windows.map(\.id))
                if (ids.contains("five_hour") && ids.contains("seven_day")) || idle >= 2 { return snapshot }
            }
            if commandSent, idle >= 1, lower.contains("subscription") && (lower.contains("only available") || lower.contains("not available")) { throw AgentError.unsupported(.claude) }
            if process.hasExited { throw AgentError.unavailable(.claude) }
        }
    }
}

private final class CapabilityCache: @unchecked Sendable {
    static let shared = CapabilityCache()
    private let lock = NSLock()
    private var values: [String: Bool] = [:]
    func value(for key: String) -> Bool? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func store(_ value: Bool, for key: String) { lock.lock(); defer { lock.unlock() }; values[key] = value }
}

private struct ScopeMarker: Codable {
    var scope: String
    var since: Date
}

private struct ScopedReading: Codable {
    var scope: String
    var snapshot: UsageSnapshot
}
