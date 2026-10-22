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
            Text("C \(store.menuValue(.claude)) · O \(store.menuValue(.codex))")
                .monospacedDigit()
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
}
