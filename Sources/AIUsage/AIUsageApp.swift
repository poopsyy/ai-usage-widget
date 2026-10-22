import AppKit
import SwiftUI
import UsageCore

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = MonitorStore(preview: CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--render-preview"))

    var body: some Scene {
        MenuBarExtra {
            MonitorView(store: store)
        } label: {
            Image(nsImage: AppImages.menuBar)
                .accessibilityLabel("AI Usage. Claude \(store.menuValue(.claude)) remaining. Codex \(store.menuValue(.codex)) remaining.")
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView(store: store) }

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.indices.contains(flag + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                    let renderer = ImageRenderer(content: MonitorView(store: MonitorStore(preview: true)).environment(\.colorScheme, scheme))
                    renderer.scale = 2
                    guard let data = renderer.nsImage?.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else {
                        throw UsageError.unavailable("Could not render preview.")
                    }
                    try png.write(to: directory.appendingPathComponent("preview-\(name).png"))
                }
                // Exercise new connection states without reading local account data or launching agents.
                for (name, phase, message) in [
                    ("sign-in", AgentPhase.signInRequired, AgentError.signedOut(.claude).localizedDescription),
                    ("signing-in", .signingIn, "Finish sign-in in your browser."),
                    ("paused", .paused, "Paused. Your agent stays signed in."),
                    ("unavailable", .unavailable, AgentError.unavailable(.claude).localizedDescription),
                    ("unsupported", .unsupported, AgentError.setupRequired(.claude).localizedDescription)
                ] {
                    let sample = MonitorStore(preview: true)
                    if phase == .unavailable {
                        sample.providers[.claude]?.phase = phase
                        sample.providers[.claude]?.error = message
                    } else { sample.providers[.claude] = ProviderState(error: message, phase: phase) }
                    let renderer = ImageRenderer(content: MonitorView(store: sample).environment(\.colorScheme, .light))
                    renderer.scale = 2
                    guard let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                        throw UsageError.unavailable("Could not render sample connection state.")
                    }
                    try png.write(to: directory.appendingPathComponent("preview-\(name).png"))
                }
                let settingsSample = MonitorStore(preview: true)
                settingsSample.integrationInstalled = true
                // Form contains native scroll views, which ImageRenderer omits. Render its own sample window.
                let settingsHost = NSHostingView(rootView: SettingsView(store: settingsSample).environment(\.colorScheme, .light))
                let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
                settingsWindow.isReleasedWhenClosed = false
                settingsWindow.title = "AI Usage Settings — SAMPLE DATA"
                settingsWindow.contentView = settingsHost
                settingsWindow.orderFront(nil)
                settingsHost.layoutSubtreeIfNeeded()
                settingsWindow.display()
                guard let bitmap = settingsHost.bitmapImageRepForCachingDisplay(in: settingsHost.bounds) else {
                    throw UsageError.unavailable("Could not render sample Settings.")
                }
                settingsHost.cacheDisplay(in: settingsHost.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw UsageError.unavailable("Could not encode sample Settings.") }
                try png.write(to: directory.appendingPathComponent("preview-settings.png"))
                settingsWindow.close()
                print("Rendered sample-data previews in \(directory.path)")
                exit(0)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--preview") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 364, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "AI Usage Preview"
            window.contentView = NSHostingView(rootView: MonitorView(store: MonitorStore(preview: true)))
            window.center(); window.makeKeyAndOrderFront(nil)
            previewWindow = window
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NotificationCenter.default.post(name: .agentMonitoringWillStop, object: nil)
        // Give cancelled workers time to terminate/reap their process groups before the app exits.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { NotificationCenter.default.post(name: .agentMonitoringWillStop, object: nil) }
}
