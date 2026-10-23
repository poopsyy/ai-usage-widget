import Foundation

public enum ExecutableLocator {
    public static func codex(override: String = "") -> URL? { find(.codex, override: override) }
    public static func find(_ provider: ProviderID, override: String = "", environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let name = provider == .claude ? "claude" : "codex"
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var candidates = (paths + ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".cargo/bin").path]).map { "\($0)/\(name)" }
        if provider == .codex {
            candidates += ["/Applications/Codex.app/Contents/Resources/codex", home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path]
        }
        if !override.isEmpty { candidates = [(override as NSString).expandingTildeInPath] }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) && !FileManager.default.fileExists(atPath: $0 + "/") }).map { URL(fileURLWithPath: $0) }
    }
}

public struct CodexProvider: UsageProvider, AgentClient {
    public let provider: ProviderID = .codex
    public var executableOverride: String
    public var environment: [String: String]
    public init(executableOverride: String = "", environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executableOverride = executableOverride; self.environment = environment
    }
    public func fetch() async throws -> UsageSnapshot { try await fetchAccount().snapshot }
    public func checkAuthentication() async throws -> AccountIdentity? {
        try await agentOperation { cancellation in
            let session = try self.session(cancellation: cancellation, timeout: 10)
            defer { session.stop() }
            try session.initialize()
            return try self.identity(session.request(method: "account/read", params: ["refreshToken": false]))
        }
    }
    public func fetchAccount() async throws -> AccountUsage {
        try await agentOperation { cancellation in
            let session = try self.session(cancellation: cancellation)
            defer { session.stop() }
            try session.initialize()
            let before = try self.identity(session.request(method: "account/read", params: ["refreshToken": false]))
            let data = try session.request(method: "account/rateLimits/read")
            let snapshot: UsageSnapshot
            do { snapshot = try UsageParser.codex(data) } catch { throw AgentError.unsupported(.codex) }
            let after = try self.identity(session.request(method: "account/read", params: ["refreshToken": false]))
            guard before?.scope == after?.scope else { throw AgentError.identityChanged }
            return AccountUsage(identity: after, snapshot: snapshot)
        }
    }
    public func signIn(openBrowser: @escaping AgentBrowserOpener) async throws {
        let cancellation = AgentCancellation()
        try await withTaskCancellationHandler {
            let session = try await Task.detached { try self.session(cancellation: cancellation, timeout: 300) }.value
            defer { session.stop() }
            let login = try await Task.detached {
                try session.initialize()
                return try session.request(method: "account/login/start", params: ["type": "chatgpt"])
            }.value
            guard let root = try? JSONSerialization.jsonObject(with: login) as? [String: Any],
                  let result = root["result"] as? [String: Any], let loginID = result["loginId"] as? String,
                  let text = result["authUrl"] as? String, let url = URL(string: text), Self.allowsAuthorizationURL(url) else { throw AgentError.invalidResponse(.codex) }
            try cancellation.check()
            guard await openBrowser(url) else { throw AgentError.browserFailed }
            try await Task.detached { try session.waitForLogin(loginID) }.value
            try cancellation.check()
        } onCancel: { cancellation.cancel() }
    }
    public static func allowsAuthorizationURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
            && ["auth.openai.com", "auth0.openai.com", "chatgpt.com"].contains(url.host?.lowercased() ?? "")
    }
    private func session(cancellation: AgentCancellation, timeout: TimeInterval = 30) throws -> AgentRPCSession {
        guard let executable = ExecutableLocator.find(.codex, override: executableOverride, environment: environment) else { throw AgentError.notInstalled(.codex) }
        var env = environment
        env["PATH"] = "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        return try AgentRPCSession(process: AgentProcess(executable: executable, arguments: ["app-server", "--listen", "stdio://"], provider: .codex, directory: FileManager.default.temporaryDirectory, environment: env, timeout: timeout, cancellation: cancellation))
    }
    private func identity(_ data: Data) throws -> AccountIdentity? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let result = root["result"] as? [String: Any] else { throw AgentError.invalidResponse(.codex) }
        guard let account = result["account"] as? [String: Any] else { throw AgentError.signedOut(.codex) }
        guard account["type"] as? String == "chatgpt" else { throw AgentError.unsupported(.codex) }
        guard let id = (account["accountId"] as? String) ?? (account["email"] as? String), !id.isEmpty else { return nil }
        return AccountIdentity(provider: .codex, accountID: id, workspaceID: account["organizationId"] as? String, displayName: "Codex account", profile: environment["CODEX_HOME"] ?? "default")
    }
}

/// Fixed account-only JSON-RPC methods. Notifications are retained for browser-login completion.
final class AgentRPCSession: @unchecked Sendable {
    private let process: AgentProcess
    private var nextID = 0
    private var notifications: [[String: Any]] = []
    init(process: AgentProcess) { self.process = process }
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    func stop() { process.stop() }
    func initialize() throws {
        _ = try request(method: "initialize", params: ["clientInfo": ["name": "ai_usage_widget", "title": "AI Usage", "version": Self.version]])
        try send(["method": "initialized", "params": [:]])
    }
    private func send(_ root: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: root); data.append(10); try process.send(data)
    }
    func request(method: String, params: [String: Any]? = nil) throws -> Data {
        guard ["initialize", "account/read", "account/rateLimits/read", "account/login/start"].contains(method) else { throw AgentError.invalidResponse(.codex) }
        nextID += 1
        var root: [String: Any] = ["id": nextID, "method": method]
        if let params { root["params"] = params }
        try send(root)
        while true {
            let data = try process.readLine()
            guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if response["id"] as? Int == nextID {
                if let error = response["error"] as? [String: Any] {
                    let message = (error["message"] as? String ?? "").lowercased()
                    if ["unauthorized", "401", "not logged in", "login required", "sign in", "authentication required"].contains(where: message.contains) { throw AgentError.signedOut(.codex) }
                    if message.contains("429") || message.contains("rate limit") { throw AgentError.rateLimited(nil) }
                    throw AgentError.unavailable(.codex)
                }
                return data
            }
            if response["method"] as? String == "account/login/completed" { notifications.append(response) }
        }
    }
    func waitForLogin(_ id: String) throws {
        while true {
            let root: [String: Any]
            if !notifications.isEmpty { root = notifications.removeFirst() }
            else {
                let data = try process.readLine()
                guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }; root = value
            }
            guard root["method"] as? String == "account/login/completed", let params = root["params"] as? [String: Any], params["loginId"] as? String == id else { continue }
            guard params["success"] as? Bool == true else { throw AgentError.signedOut(.codex) }
            return
        }
    }
}
