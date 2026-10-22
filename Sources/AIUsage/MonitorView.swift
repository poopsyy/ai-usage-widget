import AppKit
import SwiftUI
import UsageCore

enum Palette {
    static let claude = Color(red: 0.77, green: 0.43, blue: 0.30)
    static let codex = Color(red: 0.16, green: 0.57, blue: 0.48)
    static func accent(_ provider: ProviderID) -> Color { provider == .claude ? claude : codex }
    static func usage(_ used: Double) -> Color { used >= 95 ? .red : used >= 80 ? .orange : codex }
}

struct MonitorView: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.codex)
                    .frame(width: 36, height: 36)
                    .background(Palette.codex.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Usage").font(.system(size: 17, weight: .semibold))
                    Text(store.preview ? "PREVIEW · SAMPLE DATA" : "Your allowance, at a glance")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 26) }
                else {
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 26, height: 28) }
                        .buttonStyle(.plain).help("Refresh usage").accessibilityLabel("Refresh usage")
                }
            }
            .padding(20)

            VStack(spacing: 12) {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    ProviderCard(provider: provider, state: store.providers[provider] ?? ProviderState(), status: store.status(provider), now: store.now, signIn: { store.signIn(provider) }, resume: { store.setPaused(provider, false) }, cancel: { store.cancelSignIn(provider) })
                }
            }.padding(.horizontal, 16)

            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 10))
                Text("Checks every 5 min · No open session needed")
                    .font(.system(size: 10))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary).padding(.horizontal, 21).padding(.vertical, 14)

            Divider()
            HStack {
                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Label("Settings", systemImage: "gearshape") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 364)
        .background(.background)
    }
}

private struct ProviderCard: View {
    let provider: ProviderID
    let state: ProviderState
    let status: String
    let now: Date
    let signIn: () -> Void
    let resume: () -> Void
    let cancel: () -> Void
    var accent: Color { Palette.accent(provider) }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: provider == .claude ? "sun.max" : "terminal")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 30, height: 30).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                Text(provider.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(status).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(state.error != nil || state.snapshot?.isStale(at: now) == true ? Color.orange : .secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.primary.opacity(0.045), in: Capsule())
            }
            if let snapshot = state.snapshot {
                VStack(spacing: 15) {
                    ForEach(snapshot.windows) { window in
                        UsageRow(window: window, stale: snapshot.isStale(at: now) || !state.connected, now: now)
                    }
                }
                if let error = state.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if snapshot.isStale(at: now), provider == .claude {
                    Text("Refresh to request a new reading from Claude Code.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(snapshot.isStale(at: now) || !state.connected ? .orange : accent).frame(width: 4, height: 4)
                    Text("Updated \(age(snapshot.observedAt))").font(.system(size: 10))
                    Spacer()
                    usageLink
                }.foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.error ?? (state.phase == .paused ? "Monitoring is paused. Your agent remains signed in." : "Checking the installed agent and its existing sign-in…"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    usageLink
                }.padding(.bottom, 3)
            }
            if state.phase == .signInRequired { Button("Sign in using default browser", action: signIn).font(.system(size: 11)) }
            if state.phase == .signingIn {
                Text("Complete sign-in in your default browser.").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Cancel sign-in", action: cancel).font(.system(size: 11))
            }
            if state.phase == .paused { Button("Resume monitoring", action: resume).font(.system(size: 11)) }
        }
        .padding(16)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.07), lineWidth: 1))
    }
    var usageLink: some View {
        Button { NSWorkspace.shared.open(provider.usageURL) } label: {
            HStack(spacing: 3) { Text("View usage"); Image(systemName: "arrow.up.right").font(.system(size: 8)) }
        }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
            .accessibilityLabel("View \(provider.title) usage")
    }
    func age(_ date: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

private struct UsageRow: View {
    let window: UsageWindow
    let stale: Bool
    let now: Date
    var expired: Bool { window.isExpired(at: now) }
    var color: Color { stale || expired ? .secondary : Palette.usage(window.usedPercent) }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if expired {
                    Text("Awaiting update").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("\(Int(window.remaining.rounded(.down)))%")
                        .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                    Text(stale ? "last known" : "left").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                Capsule().fill(.primary.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color.opacity(stale ? 0.45 : 0.9))
                            .frame(width: max(0, proxy.size.width * (expired ? 0 : window.remaining / 100)))
                    }
            }.frame(height: 5).accessibilityHidden(true)
            HStack {
                Text(resetDescription).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if stale && !expired { Text("Stale").font(.system(size: 10)).foregroundStyle(.orange) }
            }
        }
        .accessibilityElement(children: .combine)
    }
    var resetDescription: String {
        guard let reset = window.resetsAt else { return "Reset time unavailable" }
        if expired { return "Reset passed · waiting for provider" }
        let seconds = max(0, Int(reset.timeIntervalSince(now)))
        if seconds >= 86400 { return "Resets in \(seconds / 86400)d \((seconds % 86400) / 3600)h" }
        if seconds >= 3600 { return "Resets in \(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return "Resets in \(max(1, seconds / 60))m"
    }
}
