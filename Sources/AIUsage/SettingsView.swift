import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                Toggle("Low allowance alerts", isOn: Binding(get: { store.alertsEnabled }, set: { value in Task { await store.setAlerts(value) } }))
                Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
            } header: { Text("General") }

            Section {
                Text("Usage updates when Claude Code publishes its status line. Pro or Max is required. Browser and desktop activity can make the last reading stale.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.integrationInstalled {
                    Label("Claude Code connected", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.codex)
                    Button("Restore previous status line") { store.restoreClaude() }
                } else {
                    Text("Connecting updates your Claude user settings and keeps a private backup. Your existing status-line output is preserved.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Connect Claude Code") { store.connectClaude() }.buttonStyle(.borderedProminent).tint(Palette.claude)
                }
            } header: { Text("Claude") }

            Section {
                Text("Uses your local Codex CLI sign-in. Run codex login with your ChatGPT account if needed.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Auto-detect Codex executable", text: $store.codexPath).textFieldStyle(.roundedBorder)
                        .onSubmit { store.saveCodexPath() }
                    Button("Choose…") { store.chooseCodex() }
                }
                Button("Save and refresh") { store.saveCodexPath() }
            } header: { Text("Codex") }

            Section {
                Text("Usage snapshots and preferences stay on this Mac. No API keys or conversation content are collected.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open data folder") { store.openDataFolder() }
            } header: { Text("Local data") }

            if let message = store.settingsMessage {
                Text(message).font(.caption).foregroundStyle(store.settingsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 490, height: 650)
        .task { if !store.preview { await store.updateNotificationStatus() } }
    }
}
