import AppKit
import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    var body: some View {
        Form {
            if store.preview { Text("PREVIEW · SAMPLE DATA").font(.caption).foregroundStyle(.secondary) }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                Toggle("Low allowance alerts", isOn: Binding(get: { store.alertsEnabled }, set: { value in Task { await store.setAlerts(value) } }))
                Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
            } header: { Text("General") }

            ForEach(ProviderID.allCases, id: \.self) { provider in
                Section {
                    let state = store.providers[provider] ?? ProviderState()
                    Text(provider == .claude
                         ? "Uses your installed Claude Code login. The experimental /usage probe sends no test chat and exits after each read. Live compatibility is not yet verified."
                         : "Uses your installed Codex login and its account quota interface. No chat or open Terminal session is needed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Label(store.status(provider), systemImage: state.connected ? "checkmark.circle.fill" : "person.crop.circle")
                    if let error = state.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        TextField("Auto-detect executable", text: provider == .claude ? $store.claudePath : $store.codexPath)
                            .textFieldStyle(.roundedBorder).onSubmit { store.savePath(provider) }
                        Button("Choose…") { store.chooseExecutable(provider) }
                    }
                    HStack {
                        Button("Save and refresh") { store.savePath(provider) }
                        if state.phase == .signInRequired {
                            Button("Sign in") { store.signIn(provider) }.buttonStyle(.borderedProminent)
                        }
                        if state.phase == .signingIn { Button("Cancel sign-in") { store.cancelSignIn(provider) } }
                        Spacer()
                        Button(state.phase == .paused ? "Resume monitoring" : "Pause monitoring") {
                            store.setPaused(provider, state.phase != .paused)
                        }
                    }
                    if state.phase == .signingIn { Text("Complete sign-in in your default browser. This can take up to five minutes.").font(.caption).foregroundStyle(.secondary) }
                } header: { Text(provider.title) }
            }

            Section {
                Text("The widget follows each agent's existing account. Pausing does not sign the agent out. Credentials remain managed by the official agents.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.integrationInstalled {
                    Button("Restore previous status line") { store.restoreClaude() }
                    Text("For an older status-line installation. Restoration preserves unrelated settings and refuses to overwrite later edits.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Forget experimental connection") { store.forgetExperimentalConnection() }
                Button("Open data folder") { store.openDataFolder() }
            } header: { Text("Local data and migration") }

            if let message = store.settingsMessage {
                Text(message).font(.caption).foregroundStyle(store.settingsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped).frame(width: 540, height: 750)
        .disabled(store.preview)
        .task { if !store.preview { await store.updateNotificationStatus() } }
    }
}
