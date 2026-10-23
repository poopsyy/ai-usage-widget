import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import UsageCore

extension Notification.Name { static let agentMonitoringWillStop = Notification.Name("AIUsageAgentMonitoringWillStop") }
typealias ProviderState = AgentState

private struct ScopedSnapshot: Codable {
    var scope: String
    var snapshot: UsageSnapshot
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published var providers: [ProviderID: ProviderState] = [:]
    @Published var now = Date()
    @Published var alertsEnabled = false
    @Published var notificationStatus = ""
    @Published var integrationInstalled = false
    @Published var settingsMessage: String?
    @Published var settingsError = false
    @Published var loginEnabled = false
    @Published var codexPath = ""
    @Published var claudePath = ""
    let preview: Bool
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var stopObserver: NSObjectProtocol?
    private var monitors: [ProviderID: AgentMonitor] = [:]
    private var ledgers: [String: AlertLedger] = [:]
    private var evaluatingAlerts = false
    private var alertsPending = false
    private let notifications = NotificationDelegate()
    private let directory: URL

    init(preview: Bool = false, directory: URL = UsageFiles.directory) {
        self.preview = preview; self.directory = directory
        if preview {
            providers[.claude] = ProviderState(snapshot: UsageSnapshot(provider: .claude, observedAt: now.addingTimeInterval(-32), windows: [
                UsageWindow(id: "five_hour", title: "Session", usedPercent: 58, resetsAt: now.addingTimeInterval(8040)),
                UsageWindow(id: "seven_day", title: "Weekly", usedPercent: 31, resetsAt: now.addingTimeInterval(268800))
            ]), phase: .connected)
            providers[.codex] = ProviderState(snapshot: UsageSnapshot(provider: .codex, observedAt: now.addingTimeInterval(-8), windows: [
                UsageWindow(id: "codex.primary", title: "5 hours", usedPercent: 24, resetsAt: now.addingTimeInterval(12240)),
                UsageWindow(id: "codex.secondary", title: "Weekly", usedPercent: 46, resetsAt: now.addingTimeInterval(432000))
            ], plan: "plus"), phase: .connected)
            return
        }
        let preferences = UserDefaults.standard
        alertsEnabled = preferences.bool(forKey: "alertsEnabled")
        loginEnabled = SMAppService.mainApp.status == .enabled
        codexPath = preferences.string(forKey: "codexPath") ?? ""
        claudePath = preferences.string(forKey: "claudePath") ?? ""
        UNUserNotificationCenter.current().delegate = notifications
        integrationInstalled = ClaudeIntegration(directory: directory).isInstalled
        for provider in ProviderID.allCases { configure(provider) }
        // Readings change every few minutes and the UI shows minutes, so a coarse, coalescable timer suffices.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in await self?.tick() } }
        timer?.tolerance = 10
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        stopObserver = NotificationCenter.default.addObserver(forName: .agentMonitoringWillStop, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        Task { [weak self] in await self?.refresh(); await self?.updateNotificationStatus() }
    }
    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let stopObserver { NotificationCenter.default.removeObserver(stopObserver) }
    }
    private func configure(_ provider: ProviderID) {
        monitors[provider]?.cancel()
        let client: any AgentClient = provider == .claude
            ? ClaudeCLIProvider(executableOverride: claudePath, directory: directory)
            : CodexProvider(executableOverride: codexPath)
        let monitor = AgentMonitor(client: client, paused: UserDefaults.standard.bool(forKey: "paused.\(provider.rawValue)"), cachedSnapshot: { [directory] scope in
            guard let cached = try? UsageFiles.read(ScopedSnapshot.self, from: directory.appendingPathComponent("quota-\(provider.rawValue).json")),
                  cached.scope == scope, cached.snapshot.provider == provider,
                  !cached.snapshot.windows.isEmpty,
                  cached.snapshot.windows.allSatisfy({ $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) }) else { return nil }
            return cached.snapshot
        })
        monitors[provider] = monitor; providers[provider] = monitor.state
        monitor.onChange = { [weak self, weak monitor] state in
            guard let self, let monitor, self.monitors[provider] === monitor else { return }
            let previous = self.providers[provider]?.snapshot
            self.providers[provider] = state
            if state.connected, let scope = state.scope, let snapshot = state.snapshot, snapshot != previous {
                do { try UsageFiles.write(ScopedSnapshot(scope: scope, snapshot: snapshot), to: self.directory.appendingPathComponent("quota-\(provider.rawValue).json")) }
                catch { self.settingsMessage = "Usage updated. Couldn't save the reading."; self.settingsError = true }
                Task { await self.evaluateAlerts() }
            }
        }
    }
    var isRefreshing: Bool { providers.values.contains(where: \.refreshing) }
    func menuValue(_ provider: ProviderID) -> String {
        guard let state = providers[provider], state.connected, let remaining = state.snapshot?.remaining(at: now) else { return "—" }
        return "\(Int(remaining.rounded(.down)))%"
    }
    func status(_ provider: ProviderID) -> String {
        guard let state = providers[provider] else { return "Checking" }
        if state.phase == .signingIn { return state.phase.title }
        if state.refreshing { return "Updating" }
        guard state.connected, let snapshot = state.snapshot else { return state.phase.title }
        if snapshot.isStale(at: now) { return "Stale" }
        if snapshot.windows.allSatisfy({ $0.isExpired(at: now) }) { return "Awaiting update" }
        return "Connected"
    }
    private func tick() async {
        now = Date()
        async let claude: Void = monitors[.claude]?.refresh() ?? ()
        async let codex: Void = monitors[.codex]?.refresh() ?? ()
        _ = await (claude, codex)
    }
    func refresh() async {
        guard !preview else { return }
        now = Date()
        async let claude: Void = monitors[.claude]?.refresh(force: true) ?? ()
        async let codex: Void = monitors[.codex]?.refresh(force: true) ?? ()
        _ = await (claude, codex)
        now = Date()
    }
    func signIn(_ provider: ProviderID) {
        guard !preview else { return }
        Task { [weak self] in
            await self?.monitors[provider]?.signIn { url in await MainActor.run { NSWorkspace.shared.open(url) } }
            await self?.evaluateAlerts()
        }
    }
    func cancelSignIn(_ provider: ProviderID) { monitors[provider]?.cancel() }
    func setPaused(_ provider: ProviderID, _ value: Bool) {
        guard !preview else { return }
        UserDefaults.standard.set(value, forKey: "paused.\(provider.rawValue)")
        Task { [weak self] in await self?.monitors[provider]?.setPaused(value) }
    }
    func savePath(_ provider: ProviderID) {
        guard !preview else { return }
        if provider == .claude { claudePath = claudePath.trimmingCharacters(in: .whitespacesAndNewlines) }
        else { codexPath = codexPath.trimmingCharacters(in: .whitespacesAndNewlines) }
        UserDefaults.standard.set(provider == .claude ? claudePath : codexPath, forKey: provider == .claude ? "claudePath" : "codexPath")
        configure(provider)
        Task { [weak self] in await self?.monitors[provider]?.refresh(force: true) }
    }
    func chooseExecutable(_ provider: ProviderID) {
        guard !preview else { return }
        let panel = NSOpenPanel(); panel.title = "Choose the \(provider == .claude ? "Claude Code" : "Codex") executable"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if provider == .claude { claudePath = url.path } else { codexPath = url.path }
            savePath(provider)
        }
    }
    func restoreClaude() {
        guard !preview else { return }
        do {
            try ClaudeIntegration(directory: directory).restore(); integrationInstalled = false
            settingsMessage = "Status line restored. Restart older Claude Code sessions."; settingsError = false
        } catch { settingsMessage = error.localizedDescription; settingsError = true }
    }
    func forgetExperimentalConnection() {
        guard !preview else { return }
        do {
            try ExperimentalConnectionCleanup.forget()
            settingsMessage = "Old connection removed. Agents stay signed in."; settingsError = false
        } catch { settingsMessage = error.localizedDescription; settingsError = true }
    }
    func stop() { timer?.invalidate(); for monitor in monitors.values { monitor.cancel() } }
    func setLogin(_ enabled: Bool) {
        guard !preview else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            settingsMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow AI Usage in System Settings → General → Login Items." : nil
            settingsError = false
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; settingsMessage = error.localizedDescription; settingsError = true }
    }
    func setAlerts(_ enabled: Bool) async {
        guard !preview else { return }
        if enabled {
            do {
                alertsEnabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch { alertsEnabled = false }
        } else { alertsEnabled = false }
        UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled")
        await updateNotificationStatus()
        await evaluateAlerts()
    }
    func updateNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = status.authorizationStatus == .denied ? "Allow AI Usage in System Settings → Notifications." : "Alerts at 80% and 95% used."
    }
    /// Runs when a reading changes. A request during a run is queued, never dropped.
    private func evaluateAlerts() async {
        guard alertsEnabled, !preview else { return }
        guard !evaluatingAlerts else { alertsPending = true; return }
        evaluatingAlerts = true; defer { evaluatingAlerts = false }
        repeat {
            alertsPending = false
            await deliverAlerts()
        } while alertsPending
    }
    private func deliverAlerts() async {
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        guard authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional else { return }
        for provider in ProviderID.allCases {
            guard let state = providers[provider], state.connected, let scope = state.scope, let snapshot = state.snapshot else { continue }
            let url = directory.appendingPathComponent("alerts-\(scope).json")
            var ledger = ledgers[scope] ?? (try? UsageFiles.read(AlertLedger.self, from: url)) ?? AlertLedger()
            for alert in ledger.candidates(for: snapshot, at: Date()) {
                guard providers[provider]?.connected == true, providers[provider]?.scope == scope else { break }
                let content = UNMutableNotificationContent()
                content.title = "\(provider.title) allowance low"
                content.body = "\(alert.window.title): \(Int(alert.window.remaining.rounded(.down)))% remaining."
                content.sound = .default
                do {
                    try await center.add(UNNotificationRequest(identifier: scope + "|" + alert.key, content: content, trigger: nil))
                    ledger.markDelivered(alert, at: Date()); ledgers[scope] = ledger
                    try UsageFiles.write(ledger, to: url)
                } catch { /* Retry failed notification deliveries; never mark a failed delivery. */ }
            }
        }
    }
    func openDataFolder() { guard !preview else { return }; try? UsageFiles.prepare(directory); NSWorkspace.shared.open(directory) }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
