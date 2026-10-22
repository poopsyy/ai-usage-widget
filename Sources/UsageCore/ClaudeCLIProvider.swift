import Foundation

public struct ClaudeCLIProvider: AgentClient {
    public let provider: ProviderID = .claude
    public var executableOverride: String
    public var directory: URL
    public var environment: [String: String]
    public var probeTimeout: TimeInterval
    public init(executableOverride: String = "", directory: URL = UsageFiles.directory, environment: [String: String] = ProcessInfo.processInfo.environment, probeTimeout: TimeInterval = 30) {
        self.executableOverride = executableOverride; self.directory = directory; self.environment = environment; self.probeTimeout = probeTimeout
    }
    public func checkAuthentication() async throws -> AccountIdentity? {
        try await agentOperation { cancellation in
            try self.auth(self.executable(), directory: self.prepareDirectory(), cancellation: cancellation, deadline: ProcessInfo.processInfo.systemUptime + 10)
        }
    }
    public func fetchAccount() async throws -> AccountUsage {
        try await agentOperation { cancellation in
            let executable = try self.executable()
            let cwd = try self.prepareDirectory()
            let deadline = ProcessInfo.processInfo.systemUptime + min(30, max(0.1, self.probeTimeout))
            let before = try self.auth(executable, directory: cwd, cancellation: cancellation, deadline: deadline)
            let help = try self.command(executable, arguments: ["--help"], directory: cwd, cancellation: cancellation, deadline: deadline)
            let helpText = String(decoding: help, as: UTF8.self)
            guard ["--safe-mode", "--strict-mcp-config", "--settings", "--session-id", "--no-chrome", "--disallowed-tools"].allSatisfy(helpText.contains) else { throw AgentError.claudeProbeSetup(.capabilities) }
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
            return AccountUsage(identity: after, snapshot: snapshot)
        }
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
        var captured = Data(), commandSent = false, trustResponses = 0
        var lastOutput = ProcessInfo.processInfo.systemUptime
        var ready = lastOutput + 1
        var previousScreen = ""
        var queryTail = Data()
        while true {
            let chunk: Data
            do { chunk = try process.readChunk() }
            catch let problem as AgentError {
                if problem == .timeout(.claude), !commandSent, !captured.isEmpty { throw AgentError.claudeProbeSetup(.startupPrompt) }
                throw problem
            }
            if !chunk.isEmpty { captured.append(chunk); lastOutput = ProcessInfo.processInfo.systemUptime }
            queryTail.append(chunk)
            let query = Data([0x1b, 0x5b, 0x36, 0x6e])
            while let range = queryTail.range(of: query) {
                try process.send("\u{1b}[1;1R")
                queryTail.removeSubrange(..<range.upperBound)
            }
            queryTail = Data(queryTail.suffix(3))
            let screen = ClaudeCLIScreen.render(String(decoding: captured, as: UTF8.self))
            let lower = screen.lowercased()
            let lines = screen.components(separatedBy: "\n")
            let lastMarker = lines.lastIndex(where: { $0.contains("❯") })
            let promptReady = lastMarker.map { index in
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                return line == "❯" || line.hasPrefix("❯ Try ")
            } ?? lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == ">" })
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
            if lower.contains("sign in") || lower.contains("not logged in") || lower.contains("/login") { throw AgentError.signedOut(.claude) }
            if lower.contains("rate limited") || lower.contains("too many requests") { throw AgentError.rateLimited(nil) }
            if lower.contains("choose the text style") || lower.contains("select login method") || (!promptReady && lower.contains("do you trust")) || lower.contains("permission required") { throw AgentError.claudeProbeSetup(.startupPrompt) }
            let idle = ProcessInfo.processInfo.systemUptime - lastOutput
            if !commandSent, promptReady, ProcessInfo.processInfo.systemUptime >= ready, idle >= 0.3 {
                // Only a recognized empty Claude prompt may receive the built-in command.
                // A quiet startup banner is not a setup failure: wait for the actual prompt.
                try process.send("/usage\r"); commandSent = true; captured.removeAll(); continue
            }
            if commandSent, idle >= 0.5, let snapshot = try? ClaudeCLIUsage.snapshot(screen: screen) { return snapshot }
            if commandSent, idle >= 1, lower.contains("subscription") && (lower.contains("only available") || lower.contains("not available")) { throw AgentError.unsupported(.claude) }
            if process.hasExited { throw AgentError.unavailable(.claude) }
        }
    }
}
