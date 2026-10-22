import Foundation

public enum AgentPhase: String, Sendable {
    case notInstalled, signInRequired, signingIn, connected, paused, unsupported, unavailable
    public var title: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .signInRequired: return "Sign-in required"
        case .signingIn: return "Signing in"
        case .connected: return "Connected"
        case .paused: return "Paused"
        case .unsupported: return "Unsupported"
        case .unavailable: return "Unavailable"
        }
    }
}

public enum ClaudeProbeIssue: String, Sendable {
    case workingDirectory, trustRequired, capabilities, authenticationFormat, startupPrompt, commandFailed
}

public enum AgentError: Error, LocalizedError, Equatable {
    case notInstalled(ProviderID), signedOut(ProviderID), unsupported(ProviderID)
    case unavailable(ProviderID), timeout(ProviderID), invalidResponse(ProviderID)
    case setupRequired(ProviderID), browserFailed, identityChanged, rateLimited(Date?)
    case claudeProbeSetup(ClaudeProbeIssue)
    public var phase: AgentPhase {
        switch self {
        case .notInstalled: return .notInstalled
        case .signedOut: return .signInRequired
        case .unsupported, .setupRequired: return .unsupported
        case .claudeProbeSetup(.capabilities), .claudeProbeSetup(.authenticationFormat): return .unsupported
        default: return .unavailable
        }
    }
    public var errorDescription: String? {
        switch self {
        case .notInstalled(let provider): return "Install \(provider == .claude ? "Claude Code" : "Codex"), or choose its path in Settings."
        case .signedOut(let provider): return "Sign in to \(provider.title), or run \(provider == .claude ? "claude auth login" : "codex login") in Terminal."
        case .unsupported(let provider): return "\(provider.title) reported no supported subscription limits. API usage isn't supported."
        case .unavailable(let provider): return "Can't reach \(provider.title). Check your connection."
        case .timeout(let provider): return "\(provider.title) timed out. Try refreshing."
        case .invalidResponse(let provider): return "Can't read \(provider.title) usage. Update the agent."
        case .setupRequired(let provider): return "Open \(provider == .claude ? "Claude Code" : "Codex") to finish setup or update."
        case .browserFailed: return "Can't open sign-in. Sign in through your agent, then refresh."
        case .identityChanged: return "Account changed. Refresh for current usage."
        case .rateLimited: return "Please wait before refreshing."
        case .claudeProbeSetup(let issue):
            switch issue {
            case .workingDirectory: return "Claude's probe folder is unavailable or redirected. Check app-folder permissions."
            case .trustRequired: return "Claude's probe folder needs trust, but isn't empty. Its files were left untouched."
            case .capabilities: return "This Claude Code version lacks a background-probe option. Update Claude Code."
            case .authenticationFormat: return "Claude Code returned an unsupported sign-in status. Update Claude Code."
            case .startupPrompt: return "Claude's background prompt wasn't recognized. Refresh, or finish setup in Claude Code."
            case .commandFailed: return "Claude's background command failed. Refresh or update Claude Code."
            }
        }
    }
}

public typealias AgentBrowserOpener = @Sendable (URL) async -> Bool

public protocol AgentClient: Sendable {
    var provider: ProviderID { get }
    func checkAuthentication() async throws -> AccountIdentity?
    func fetchAccount() async throws -> AccountUsage
    func signIn(openBrowser: @escaping AgentBrowserOpener) async throws
}

public struct AgentState: Sendable {
    public var snapshot: UsageSnapshot?
    public var scope: String?
    public var error: String?
    public var refreshing: Bool
    public var phase: AgentPhase
    public var connected: Bool { phase == .connected }
    public init(snapshot: UsageSnapshot? = nil, scope: String? = nil, error: String? = nil, refreshing: Bool = false, phase: AgentPhase = .unavailable) {
        self.snapshot = snapshot; self.scope = scope; self.error = error; self.refreshing = refreshing; self.phase = phase
    }
}

/// A serial operation slot per provider. Generation checks prevent cancelled work from publishing.
@MainActor
public final class AgentMonitor {
    public private(set) var state: AgentState { didSet { onChange?(state) } }
    public var onChange: ((AgentState) -> Void)?
    public private(set) var nextRefresh = Date.distantPast
    private let client: any AgentClient
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var failures = 0
    private var cooldown = Date.distantPast
    private var paused: Bool
    private let cachedSnapshot: (String) -> UsageSnapshot?

    public init(client: any AgentClient, paused: Bool = false, cachedSnapshot: @escaping (String) -> UsageSnapshot? = { _ in nil }) {
        self.client = client; self.paused = paused
        self.cachedSnapshot = cachedSnapshot
        state = AgentState(phase: paused ? .paused : .unavailable)
    }
    public func refresh(force: Bool = false) async {
        guard !paused, operation == nil, Date() >= cooldown, force || Date() >= nextRefresh else { return }
        await launch(login: false, openBrowser: { _ in false })
    }
    public func signIn(openBrowser: @escaping AgentBrowserOpener) async {
        guard !paused, state.phase != .signingIn else { return }
        await launch(login: true, openBrowser: openBrowser)
    }
    public func setPaused(_ value: Bool) async {
        paused = value
        cancel()
        if value { state = AgentState(phase: .paused) }
        else {
            state = AgentState()
            let previous = operation
            await previous?.value
            guard !paused else { return }
            await refresh(force: true)
        }
    }
    public func cancel() {
        generation += 1
        operation?.cancel()
        state.refreshing = false
        if state.phase == .signingIn { state.phase = .signInRequired; state.error = "Sign-in cancelled." }
    }
    private func launch(login: Bool, openBrowser: @escaping AgentBrowserOpener) async {
        let previous = operation
        generation += 1
        let epoch = generation
        previous?.cancel()
        state.refreshing = true
        if login { state.phase = .signingIn; state.error = nil; state.snapshot = nil; state.scope = nil }
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                // A cancelled slot is cleared unless a newer slot replaced it.
                if self.slot == epoch { self.operation = nil; self.state.refreshing = false }
            }
            guard epoch == self.generation, !self.paused, !Task.isCancelled else { return }
            do {
                if login { try await self.client.signIn(openBrowser: openBrowser) }
                try Task.checkCancellation()
                let identity = try await self.client.checkAuthentication()
                guard epoch == self.generation, !self.paused, !Task.isCancelled else { return }
                if let scope = identity?.scope {
                    if self.state.scope != scope {
                        if !login { self.state.phase = .unavailable }
                        self.state.snapshot = self.cachedSnapshot(scope)
                        self.state.scope = scope
                    }
                } else { self.state.snapshot = nil; self.state.scope = nil }
                let reading = try await self.client.fetchAccount()
                guard epoch == self.generation, !self.paused, !Task.isCancelled else { return }
                guard identity?.scope == reading.identity?.scope else { throw AgentError.identityChanged }
                self.failures = 0; self.nextRefresh = Date().addingTimeInterval(300)
                self.state = AgentState(snapshot: reading.snapshot, scope: reading.identity?.scope, phase: .connected)
            } catch {
                guard epoch == self.generation, !self.paused, !Task.isCancelled else { return }
                let problem = error as? AgentError ?? .unavailable(self.client.provider)
                self.state.phase = problem.phase; self.state.error = problem.localizedDescription
                // Only transient failures retain the last known account's reading.
                if problem.phase != .unavailable || problem == .identityChanged { self.state.snapshot = nil; self.state.scope = nil }
                self.failures = min(self.failures + 1, 5)
                let delay = problem.phase == .unavailable ? min(300, 30 * pow(2, Double(self.failures - 1))) : 300
                self.nextRefresh = Date().addingTimeInterval(delay)
                if case .rateLimited(let until) = problem {
                    self.cooldown = until ?? Date().addingTimeInterval(300)
                    self.nextRefresh = max(self.nextRefresh, self.cooldown)
                }
            }
        }
        slot = epoch; operation = task
        await task.value
    }
    private var slot = 0
}
