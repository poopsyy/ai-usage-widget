import AppKit
import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    var body: some View {
        Form {
            if store.preview { Text("Sample data").font(.caption).foregroundStyle(.secondary) }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                Toggle("Low allowance alerts", isOn: Binding(get: { store.alertsEnabled }, set: { value in Task { await store.setAlerts(value) } }))
                Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
            } header: { Text("General") }

            ForEach(ProviderID.allCases, id: \.self) { provider in
                Section {
                    let state = store.providers[provider] ?? ProviderState()
                    Text(provider == .claude
                         ? "Requires Claude Code. Experimental; live support unverified."
                         : "Uses your Codex login.")
                        .font(.caption).foregroundStyle(.secondary)
                    Label(store.status(provider), systemImage: state.connected ? "checkmark.circle.fill" : "person.crop.circle")
                    if let error = state.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        TextField("Automatic path", text: provider == .claude ? $store.claudePath : $store.codexPath)
                            .textFieldStyle(.roundedBorder).onSubmit { store.savePath(provider) }
                            .accessibilityLabel("\(provider.title) executable path")
                            .help("Leave blank to find the agent automatically")
                        Button("Choose…") { store.chooseExecutable(provider) }
                    }
                    HStack {
                        Button("Save") { store.savePath(provider) }.help("Save path and refresh usage")
                        if state.phase == .signInRequired {
                            Button("Sign in") { store.signIn(provider) }.buttonStyle(.borderedProminent)
                        }
                        if state.phase == .signingIn { Button("Cancel sign-in") { store.cancelSignIn(provider) } }
                        Spacer()
                        Button {
                            store.setPaused(provider, state.phase != .paused)
                        } label: {
                            Label(state.phase == .paused ? "Resume" : "Pause", systemImage: state.phase == .paused ? "play.fill" : "pause.fill")
                        }.help("\(state.phase == .paused ? "Resume" : "Pause") \(provider.title) monitoring")
                    }
                    if state.phase == .signingIn { Text("Finish sign-in in your browser.").font(.caption).foregroundStyle(.secondary) }
                    if provider == .claude {
                        Toggle("Faster updates during Claude Code sessions", isOn: Binding(get: { store.statusLineEnabled }, set: { store.setStatusLine($0) }))
                            .help("Adds a status line to Claude Code settings. Turn off to restore your previous status line.")
                        Text("Reads usage that Claude Code reports to its status line. Your existing status line keeps working.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Label { Text(provider.title) } icon: { ProviderIcon(provider: provider, size: 18) }
                }
            }

            Section {
                Text("Accounts stay with your agents. Pause keeps you signed in.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Forget experimental connection") { store.forgetExperimentalConnection() }
                    .help("Remove the widget's old saved connection. Agent sign-ins stay unchanged.")
                Button("Open data folder") { store.openDataFolder() }
            } header: { Text("Local data") }

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
