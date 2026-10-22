import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import UsageCore

struct ProviderState {
    var snapshot: UsageSnapshot?
    var error: String?
    var refreshing = false
    var connected = false
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published var providers: [ProviderID: ProviderState] = [:]
    @Published var now = Date()
    @Published var alertsEnabled = UserDefaults.standard.bool(forKey: "alertsEnabled")
    @Published var notificationStatus = ""
    @Published var integrationInstalled = false
    @Published var settingsMessage: String?
    @Published var settingsError = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var codexPath = UserDefaults.standard.string(forKey: "codexPath") ?? ""
    let preview: Bool
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var nextCodexRefresh = Date.distantPast
    private var failureCount = 0
    private var lastClaudeModification: Date?
    private var ledger: AlertLedger
    private var evaluatingAlerts = false
    private let notifications = NotificationDelegate()
    private let directory: URL

    init(preview: Bool = false, directory: URL = UsageFiles.directory) {
        self.preview = preview
        self.directory = directory
        ledger = (try? UsageFiles.read(AlertLedger.self, from: directory.appendingPathComponent("alerts.json"))) ?? AlertLedger()
        for provider in ProviderID.allCases {
            providers[provider] = ProviderState(snapshot: try? UsageFiles.read(UsageSnapshot.self, from: directory.appendingPathComponent("\(provider.rawValue).json")))
        }
        if preview {
            providers[.claude] = ProviderState(snapshot: UsageSnapshot(provider: .claude, observedAt: now.addingTimeInterval(-32), windows: [
                UsageWindow(id: "five_hour", title: "5 hours", usedPercent: 58, resetsAt: now.addingTimeInterval(8040)),
                UsageWindow(id: "seven_day", title: "Weekly", usedPercent: 31, resetsAt: now.addingTimeInterval(268800))
            ]), connected: true)
            providers[.codex] = ProviderState(snapshot: UsageSnapshot(provider: .codex, observedAt: now.addingTimeInterval(-8), windows: [
                UsageWindow(id: "codex.primary", title: "5 hours", usedPercent: 24, resetsAt: now.addingTimeInterval(12240)),
                UsageWindow(id: "codex.secondary", title: "Weekly", usedPercent: 46, resetsAt: now.addingTimeInterval(432000))
            ], plan: "plus"), connected: true)
            return
        }
        UNUserNotificationCenter.current().delegate = notifications
        integrationInstalled = ClaudeIntegration(directory: directory).isInstalled
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
        Task { await refresh(); await updateNotificationStatus() }
    }
    deinit {
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    var isRefreshing: Bool { providers.values.contains(where: \.refreshing) }
    func menuValue(_ provider: ProviderID) -> String {
        guard let state = providers[provider], state.connected,
              let remaining = state.snapshot?.remaining(at: now) else { return "—" }
        return "\(Int(remaining.rounded(.down)))%"
    }
    func status(_ provider: ProviderID) -> String {
        guard let state = providers[provider] else { return "Set up" }
        if state.refreshing { return "Updating" }
        if state.error != nil { return state.snapshot == nil ? "Needs attention" : "Unavailable" }
        guard let snapshot = state.snapshot else { return "Set up" }
        if snapshot.isStale(at: now) { return "Stale" }
        if snapshot.windows.allSatisfy({ $0.isExpired(at: now) }) { return "Awaiting update" }
        return provider == .claude ? "Claude Code" : "Connected"
    }
    private func tick() async {
        now = Date()
        await refreshClaude()
        if now >= nextCodexRefresh { await refreshCodex() }
        await evaluateAlerts()
    }
    func refresh() async {
        guard !preview else { return }
        now = Date()
        await refreshClaude(force: true)
        await refreshCodex()
        await evaluateAlerts()
    }
    private func refreshClaude(force: Bool = false) async {
        let url = directory.appendingPathComponent("claude.json")
        let modification = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard force || modification != lastClaudeModification else { return }
        lastClaudeModification = modification
        do {
            let snapshot = try await ClaudeProvider(directory: directory).fetch()
            providers[.claude] = ProviderState(snapshot: snapshot, connected: true)
        } catch {
            providers[.claude]?.error = error.localizedDescription
            providers[.claude]?.connected = false
        }
    }
    private func refreshCodex() async {
        guard providers[.codex]?.refreshing != true else { return }
        providers[.codex]?.refreshing = true
        nextCodexRefresh = Date().addingTimeInterval(300)
        do {
            let snapshot = try await CodexProvider(executableOverride: codexPath).fetch()
            providers[.codex] = ProviderState(snapshot: snapshot, connected: true)
            failureCount = 0
            do { try UsageFiles.write(snapshot, to: directory.appendingPathComponent("codex.json")) }
            catch { settingsMessage = "Usage updated, but the local cache could not be saved."; settingsError = true }
        } catch {
            providers[.codex]?.refreshing = false
            providers[.codex]?.error = error.localizedDescription
            providers[.codex]?.connected = false
            failureCount = min(failureCount + 1, 6)
            nextCodexRefresh = Date().addingTimeInterval(min(300, 15 * pow(2, Double(failureCount - 1))))
        }
        now = Date()
    }
    func saveCodexPath() {
        codexPath = codexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(codexPath, forKey: "codexPath")
        Task { await refresh() }
    }
    func chooseCodex() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex executable"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { codexPath = url.path; saveCodexPath() }
    }
    func connectClaude() {
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/UsageBridge")
            try ClaudeIntegration(directory: directory).install(helper: helper)
            integrationInstalled = true
            settingsMessage = "Connected. Start a new Claude Code session and send a message to publish usage."
            settingsError = false
        } catch { settingsMessage = error.localizedDescription; settingsError = true }
    }
    func restoreClaude() {
        do {
            try ClaudeIntegration(directory: directory).restore()
            integrationInstalled = false
            settingsMessage = "Your previous Claude status line is restored. Restart Claude Code to stop capture."
            settingsError = false
        } catch { settingsMessage = error.localizedDescription; settingsError = true }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            settingsMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow AI Usage in System Settings → General → Login Items." : nil
            settingsError = false
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; settingsMessage = error.localizedDescription; settingsError = true }
    }
    func setAlerts(_ enabled: Bool) async {
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
        notificationStatus = status.authorizationStatus == .denied ? "Notifications are blocked. Allow AI Usage in System Settings → Notifications." : "Alerts at 80% and 95% used, once per usage window."
    }
    private func evaluateAlerts() async {
        guard alertsEnabled, !preview, !evaluatingAlerts else { return }
        evaluatingAlerts = true
        defer { evaluatingAlerts = false }
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        guard authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional else { return }
        for provider in ProviderID.allCases {
            guard let state = providers[provider], state.connected, let snapshot = state.snapshot else { continue }
            for alert in ledger.candidates(for: snapshot, at: Date()) {
                let content = UNMutableNotificationContent()
                content.title = "\(provider.title) allowance is running low"
                content.body = "\(alert.window.title): \(Int(alert.window.remaining.rounded(.down)))% remaining."
                content.sound = .default
                do {
                    try await center.add(UNNotificationRequest(identifier: alert.key, content: content, trigger: nil))
                    ledger.markDelivered(alert, at: Date())
                    try UsageFiles.write(ledger, to: directory.appendingPathComponent("alerts.json"))
                } catch { /* Retry delivery on the next refresh; never mark a failed delivery. */ }
            }
        }
    }
    func openDataFolder() { try? UsageFiles.prepare(directory); NSWorkspace.shared.open(directory) }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
