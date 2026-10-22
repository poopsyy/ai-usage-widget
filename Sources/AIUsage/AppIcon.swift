import AppKit
import SwiftUI
import UsageCore

enum AppImages {
    /// Packaged apps keep the SwiftPM bundle in Contents/Resources.
    static let providers: Bundle = {
        if let url = Bundle.main.url(forResource: "AIUsage_AIUsage", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    static let claude = providerImage("claude")
    static let codexLight = providerImage("codex-light")
    static let codexDark = providerImage("codex-dark")

    private static func providerImage(_ name: String) -> NSImage {
        guard let url = providers.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            fatalError("Missing bundled provider logo: \(name)")
        }
        return image
    }

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
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var colorScheme

    private var image: NSImage {
        provider == .claude ? AppImages.claude : (colorScheme == .dark ? AppImages.codexDark : AppImages.codexLight)
    }

    var body: some View {
        Group {
            if provider == .claude {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: size * 0.65, height: size * 0.65)
                    .frame(width: size, height: size)
                    .background(Palette.claude.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3))
            } else {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: size, height: size)
            }
        }.accessibilityHidden(true)
    }
}
