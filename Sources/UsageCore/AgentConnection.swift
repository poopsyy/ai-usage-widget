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
        case .unavailable: return "Temporarily unavailable"
        }
    }
}

public enum AgentError: Error, LocalizedError, Equatable {
    case notInstalled(ProviderID), signedOut(ProviderID), unsupported(ProviderID)
    case unavailable(ProviderID), timeout(ProviderID), invalidResponse(ProviderID)
    case setupRequired(ProviderID), browserFailed, identityChanged, rateLimited(Date?)
    public var phase: AgentPhase {
        switch self {
        case .notInstalled: return .notInstalled
        case .signedOut: return .signInRequired
        case .unsupported, .setupRequired: return .unsupported
        default: return .unavailable
        }
    }
    public var errorDescription: String? {
        switch self {
        case .notInstalled(let provider): return "Install \(provider == .claude ? "Claude Code" : "Codex") or choose its executable in Settings."
        case .signedOut(let provider): return "Sign in to \(provider.title) to read subscription limits. You can also use \(provider == .claude ? "claude auth login" : "codex login") in Terminal."
        case .unsupported(let provider): return "\(provider.title) did not report supported subscription limits. API-key billing is not a subscription allowance."
        case .unavailable(let provider): return "\(provider.title) could not be reached. Check your connection and try again."
        case .timeout(let provider): return "\(provider.title) took too long to respond. Try refreshing."
        case .invalidResponse(let provider): return "\(provider.title) returned an unsupported usage format. Update the agent and try again."
        case .setupRequired(let provider): return "This \(provider.title) installation needs setup or does not support a safe background probe. Open the official agent to finish setup or update it."
        case .browserFailed: return "Could not open the official sign-in page. Sign in through the installed agent, then refresh."
        case .identityChanged: return "The agent account changed during this read. Refresh to read the new account."
        case .rateLimited: return "The provider asked us to wait before refreshing again."
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
        if state.phase == .signingIn { state.phase = .signInRequired; state.error = "Sign-in was cancelled." }
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
