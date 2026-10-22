import AppKit
import SwiftUI
import UsageCore

enum AppImages {
    /// A template image stays legible in both menu bar appearances.
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 13, height: 14), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 4, height: 8), xRadius: 1.3, yRadius: 1.3).fill()
            NSBezierPath(roundedRect: NSRect(x: 8, y: 1, width: 4, height: 12), xRadius: 1.3, yRadius: 1.3).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

struct AppIcon: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Capsule().fill(Palette.claude).frame(width: 7, height: 14)
            Capsule().fill(Palette.codex).frame(width: 7, height: 22)
        }
        .frame(width: 36, height: 36)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.22, blue: 0.23), Color(red: 0.06, green: 0.12, blue: 0.13)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
        .accessibilityHidden(true)
    }
}

struct ProviderIcon: View {
    let provider: ProviderID
    var body: some View {
        Image(systemName: provider == .claude ? "sun.max.fill" : "terminal.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Palette.accent(provider))
            .frame(width: 30, height: 30)
            .background(Palette.accent(provider).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}
